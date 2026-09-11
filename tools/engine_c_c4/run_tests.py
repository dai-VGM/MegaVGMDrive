#!/usr/bin/env python3
"""C4 reproducible simulation gates. No hardware/Quartus invocation."""
import argparse
from dataclasses import replace
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('c3_tests',ROOT/'tools/engine_c_c3/run_tests.py')
c3=importlib.util.module_from_spec(spec);spec.loader.exec_module(c3)
cap=c3.cap
from mvgmsid import Stream, Event, WAIT, WRITE, EOF

def sources():
    return [ROOT/str(p.relative_to(ROOT)).replace('engine_c_c3/engine_c_lab.sv','engine_c_c4/engine_c_lab.sv')
            .replace('engine_c_c3/sid_native_scheduler.sv','engine_c_c4/sid_native_scheduler.sv') for p in c3.sources()]

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--out',type=Path,default=Path('/Users/daizo/Projects/MegaVGMPlayer_EngineC_PhaseC4_Artifacts'))
    ap.add_argument('--c3-artifacts',type=Path,default=Path('/Users/daizo/Projects/MegaVGMPlayer_EngineC_PhaseC3_Artifacts'))
    ap.add_argument('--only',choices=['raw','transport','capacity','owner','all'],default='all')
    args=ap.parse_args();out=args.out.resolve();out.mkdir(parents=True,exist_ok=True)
    here=Path(__file__).parent;prior=args.c3_artifacts.resolve();results=[]
    def run(name,cmd,cwd=ROOT):
        p=subprocess.run(list(map(str,cmd)),cwd=cwd,capture_output=True,text=True)
        (out/(name+'.log')).write_text(p.stdout+p.stderr)
        results.append(dict(name=name,passed=p.returncode==0,output=p.stdout+p.stderr))
        print(name,p.stdout.strip(),p.stderr.strip(),flush=True)
        (out/('results-'+args.only+'.json')).write_text(json.dumps(results,indent=2)+'\n')
        if p.returncode: raise RuntimeError(name)
    if args.only in ('raw','all'):
        # Both builds use the identical new raw-publication harness, so EOF's
        # intentionally removed busy gate cannot conceal an algorithm change.
        cap.build(out/'raw','c2_sim_top',sources()+[here/'sim_top.sv'],here/'sim_main.cpp')
        cap.build(out/'reference','c2_sim_top',c3.sources()+[ROOT/'tools/engine_c_c3/sim_top.sv'],here/'sim_main.cpp')
        for timing in ('pal','ntsc'):
            for model in (6581,8580):
                name=f'tone-{timing}-{model}'
                run('raw-'+name,[out/'raw/Vc2_sim_top',prior/(name+'.mvgmsid'),'good',out/(name+'.pcm')])
        run('reference-pal',[out/'reference/Vc2_sim_top',prior/'tone-pal-6581.mvgmsid','good',out/'reference-pal.pcm'])
        assert (out/'reference-pal.pcm').read_bytes()==(out/'tone-pal-6581.pcm').read_bytes(),'C3 raw pre-gain PCM changed'
        print('C3 pre-gain PAL/6581 3-second PCM BIT-EXACT',hashlib.sha256((out/'reference-pal.pcm').read_bytes()).hexdigest(),flush=True)
        for mode in ('sequence','starve','corrupt'):
            path=prior/('sequence.mvgmsid' if mode=='sequence' else 'record-capacity.mvgmsid')
            run('raw-'+mode,[out/'raw/Vc2_sim_top',path,mode])
        # Every prepared C3 strict/header/capacity vector is reused, not rebuilt
        # with a different format implementation. Native timing is unchanged.
        previous=json.loads((prior/'results.json').read_text())
        for r in previous:
            path=prior/(r['name']+'.mvgmsid')
            if not path.exists() or r['name'].startswith('tone-'): continue
            good='SESSION 0' in r['output']
            run('vector-'+r['name'],[out/'raw/Vc2_sim_top',path,'good' if good else 'reject'])
    shell_sources=[ROOT/'rtl/engine_c_c4/mister_vgm_md_top.sv',ROOT/'rtl/engine_c_c4/c4_profile.sv',
        ROOT/'rtl/engine_c_c4/ddr_health.sv',ROOT/'rtl/engine_c_c4/transport.sv',
        ROOT/'rtl/engine_c_c4/megavgm_playlist_status_export.sv',ROOT/'rtl/transport_v1_3/megavgm_transport_owner.sv',
        ROOT/'rtl/engine_c_c2/shell/golden_player_shell_upload.sv',ROOT/'rtl/vgm_ddram_backend.sv',*sources()]
    # A define file is a simulation-only compile unit; QSF declares same macro.
    defines=here/'defines.sv'
    if args.only in ('transport','all'):
        # Sustain voice 1 beyond EOF: a hard busy gate would cut audible audio.
        ev=[]
        for i,(addr,data) in enumerate(((24,15),(0,0x44),(1,0x1d),(5,0x09),(6,0xf0),(4,0x21))):
            if i: ev.append(Event(WAIT,operand=1))
            ev.append(Event(WRITE,addr,data))
        ev += [Event(WAIT,operand=49995),Event(EOF)]
        tone=out/'tail.mvgmsid';tone.write_bytes(cap.make(ev));Stream.decode(tone.read_bytes()).validate()
        cap.build(out/'transport','tb_transport',[defines,here/'tb_transport.sv',*shell_sources])
        run('full-transport',[out/'transport/Vtb_transport','+STREAM='+str(tone)])
        cap.build(out/'health','tb_health',[here/'tb_health.sv',ROOT/'rtl/engine_c_c4/ddr_health.sv'])
        run('ddr-health',[out/'health/Vtb_health'])
        cap.build(out/'fault','tb_fault',[defines,here/'tb_fault.sv',*shell_sources])
        for mode in ('STARVE','CORRUPT'):
            run('full-fault-'+mode,[out/'fault/Vtb_fault','+STREAM='+str(prior/'record-capacity.mvgmsid'),'+'+mode])
    if args.only in ('capacity','all'):
        cap.build(out/'shell','tb_shell',[defines,here/'tb_capacity.sv',*shell_sources])
        for filename,opts in [('sequence.mvgmsid',['+MODEL_SEQUENCE']),('maximum-dense.mvgmsid',[]),
                              ('unaligned-4194305.mvgmsid',['+REJECT'])]:
            run('shell-'+filename,[out/'shell/Vtb_shell','+STREAM='+str(prior/filename),*opts])
    if args.only in ('owner','all'):
        for name in ('tb_fade_only_owner','tb_legacy_owner'):
            run('build-'+name,['iverilog','-g2012','-s','tb_owner','-I'+str(ROOT),'-o',out/name,
                ROOT/'rtl/transport_v1_3/megavgm_transport_owner.sv',here/(name+'.sv')])
            run(name,['vvp',out/name])
        for name,top in [('tb_abi','tb_transport'),('tb_status','tb_megavgm_playlist_loop_status_export')]:
            run('build-'+name,['iverilog','-g2012','-DMEGAVGMDRIVE_PLAYLIST_LOOP_PHASE1E',
                '-s',top,'-o',out/name,ROOT/'rtl/engine_c_c4/transport.sv',
                ROOT/'rtl/engine_c_c4/megavgm_playlist_status_export.sv',here/(name+'.sv')])
            run(name,['vvp',out/name])
    print('SIMULATION GATES',len(results),'passed (not hardware)',flush=True)

if __name__=='__main__':main()
