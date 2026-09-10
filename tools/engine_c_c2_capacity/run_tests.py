#!/usr/bin/env python3
"""Capacity regression: frozen C2 baseline + new DDR-backed C2 lab, no Quartus.

All valid fixtures use the frozen C0 encoder/strict validator. Boundary +/-1
files cannot be v1 aligned; they must reject, NOT be padded or truncated.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'tools/engine_c_c2'))
from run_tests import make, Event, WAIT, WRITE, EOF, Stream

def sources():
    old=ROOT/'rtl/engine_c_c2'
    new=ROOT/'rtl/engine_c_c2_capacity'
    return [new/n for n in ('engine_c_lab.sv','mvgmsid_loader.sv','c2_record_store.sv','c2_ddr_mux.sv')]+[
        old/'sid_native_scheduler.sv',old/'sid_session_wrapper.sv',*sorted((old/'vendor/lab').glob('*.sv'))]

def build(out, top, files, cpp=None):
    cmd=['verilator', '--cc' if cpp else '--binary','--assert','-Wno-fatal','-j','4',
         '-I'+str(ROOT),'--top-module',top,'--Mdir',str(out)]
    if cpp: cmd+=['--exe','--build','-CFLAGS','-O2']
    else: cmd+=['--timing']
    cmd+=list(map(str,files))
    if cpp: cmd.append(str(cpp))
    with out.with_suffix('.log').open('w') as log:
        subprocess.run(cmd,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,check=True)

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--out',type=Path,default=Path('/tmp/megavgm-c2-capacity'))
    ap.add_argument('--baseline',type=Path,default=Path('/tmp/megavgm-c2-capacity-baseline'))
    ap.add_argument('--reuse-baseline',action='store_true')
    args=ap.parse_args(); out=args.out.resolve(); out.mkdir(parents=True,exist_ok=True)
    baseline=args.baseline.resolve()
    if not args.reuse_baseline:
        subprocess.run([sys.executable,str(ROOT/'tools/engine_c_c2/run_tests.py'),'--out',str(baseline)],check=True)
    here=Path(__file__).parent
    build(out/'obj','c2_sim_top',sources()+[here/'sim_top.sv'],here/'sim_main.cpp')
    good_names={'minimal','tone-pal-6581','same-value-rewrite','consecutive-waits','record-capacity'}
    original=json.loads((baseline/'results.json').read_text())[:45]
    cases={r['name']:((baseline/(r['name']+'.mvgmsid')).read_bytes(),r['name'] in good_names) for r in original}
    def sized(n,dense=False):
        assert n>=144 and (n-128)%16==0
        count=(n-128)//16
        ev=[Event(WRITE,0,(i//2)%256) if dense and i%2==0 else Event(WAIT,operand=1) for i in range(count-1)]
        return make(ev+[Event(EOF)])
    for n in (131056,131072,131088,131200,131216,4194288,4194304):
        cases[f'bytes-{n}']=(sized(n),True)
    cases['maximum-dense']=(sized(4194304,True),True)
    for n in (131071,131073,4194303,4194305):
        aligned=(n//16)*16
        cases[f'unaligned-{n}']=(sized(aligned)+bytes(n-aligned),False)
    cases['oversize-aligned']=(sized(4194320),False)
    bad=bytearray(cases['maximum-dense'][0]);bad[-15]=1
    cases['maximum-bad-eof']=(bytes(bad),False)
    results=[]
    for name,(data,good) in cases.items():
        path=out/(name+'.mvgmsid');path.write_bytes(data)
        if good: Stream.decode(data).validate()
        cmd=[str(out/'obj/Vc2_sim_top'),str(path),'good' if good else 'reject']
        if name=='tone-pal-6581': cmd.append(str(out/'tone.pcm'))
        p=subprocess.run(cmd,capture_output=True,text=True)
        print(name,p.stdout.strip(),p.stderr.strip(),flush=True)
        results.append(dict(name=name,bytes=len(data),passed=p.returncode==0,output=p.stdout+p.stderr))
        if p.returncode: raise RuntimeError(name)
    assert (out/'tone.pcm').read_bytes()==(baseline/'tone.pcm').read_bytes(), 'audio changed'
    for fault in ('starve','corrupt'):
        p=subprocess.run([str(out/'obj/Vc2_sim_top'),str(out/'record-capacity.mvgmsid'),fault],
                         capture_output=True,text=True,check=True)
        print(p.stdout,flush=True)
        results.append(dict(name='ddr-'+fault,passed=True,output=p.stdout))
    # Direct old/new contrast. Above 8192 events rejects before reads; dense old
    # 8192-event stream rejects at the independent 4096th WRITE.
    for name in ('bytes-131200','bytes-131216','record-capacity'):
        good=name=='bytes-131200'
        p=subprocess.run([str(baseline/'obj/Vc2_sim_top'),str(out/(name+'.mvgmsid')),
                          'good' if good else 'reject'],capture_output=True,text=True,check=True)
        results.append(dict(name='baseline-'+name,passed=True,output=p.stdout))
        print('BASELINE',name,p.stdout.strip(),flush=True)
    build(out/'shell','tb_shell',[
        here/'tb_shell.sv',ROOT/'rtl/engine_c_c2_capacity/mister_vgm_md_top_v1_1.sv',
        ROOT/'rtl/engine_c_c2_capacity/c2_profile.sv',
        ROOT/'rtl/engine_c_c2/shell/golden_player_shell_upload.sv',
        ROOT/'rtl/vgm_ddram_backend.sv',*sources()])
    for path,reject in [(baseline/'shell-tone.mvg',False),(out/'maximum-dense.mvgmsid',False),
                        (out/'unaligned-4194305.mvgmsid',True)]:
        cmd=[str(out/'shell/Vtb_shell'),'+STREAM='+str(path)]
        if reject: cmd+=['+REJECT']
        p=subprocess.run(cmd,capture_output=True,text=True,check=True)
        print(p.stdout,flush=True)
        results.append(dict(name='shell-'+path.stem,passed=True,output=p.stdout))
    (out/'results.json').write_text(json.dumps(results,indent=2)+'\n')
    print('SIMULATION',len(results),'cases; PCM exact SHA256',hashlib.sha256((out/'tone.pcm').read_bytes()).hexdigest())

if __name__=='__main__': main()
