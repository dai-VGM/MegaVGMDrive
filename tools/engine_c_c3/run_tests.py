#!/usr/bin/env python3
"""C3 model/timing simulation, reusing frozen C0 and C2-capacity fixtures."""
import argparse
from dataclasses import replace
import hashlib
import importlib.util
import json
from pathlib import Path
import struct
import subprocess
import sys
import wave

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('capacity_tests',ROOT/'tools/engine_c_c2_capacity/run_tests.py')
cap=importlib.util.module_from_spec(spec);spec.loader.exec_module(cap)
from mvgmsid import Stream, Event, WAIT, WRITE, EOF

def sources():
    replacements={
        'rtl/engine_c_c2_capacity/engine_c_lab.sv':'rtl/engine_c_c3/engine_c_lab.sv',
        'rtl/engine_c_c2_capacity/mvgmsid_loader.sv':'rtl/engine_c_c3/mvgmsid_loader.sv',
        'rtl/engine_c_c2/sid_native_scheduler.sv':'rtl/engine_c_c3/sid_native_scheduler.sv'}
    return [ROOT/replacements.get(str(p.relative_to(ROOT)),str(p.relative_to(ROOT))) for p in cap.sources()]

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--out',type=Path,default=Path('/Users/daizo/Projects/MegaVGMPlayer_EngineC_PhaseC3_Artifacts'))
    ap.add_argument('--reference',type=Path,default=Path('/tmp/megavgm-c3-c2-reference'))
    ap.add_argument('--reuse-reference',action='store_true')
    args=ap.parse_args();out=args.out.resolve();out.mkdir(parents=True,exist_ok=True)
    ref=args.reference.resolve();here=Path(__file__).parent
    if not args.reuse_reference:
        subprocess.run([sys.executable,str(ROOT/'tools/engine_c_c2_capacity/run_tests.py'),'--out',str(ref)],check=True)
    prior=json.loads((ref/'results.json').read_text());assert len(prior)==67 and all(r['passed'] for r in prior)
    cap.build(out/'obj','c2_sim_top',sources()+[here/'sim_top.sv'],here/'sim_main.cpp')
    cases={}
    for r in prior:
        if 'bytes' not in r: continue
        data=(ref/(r['name']+'.mvgmsid')).read_bytes()
        good='SESSION 0' in r['output'] or r['name']=='8580-unsupported'
        cases[r['name']]=(data,good)
    original=Stream.decode((ref/'tone-pal-6581.mvgmsid').read_bytes())
    tones=[]
    for timing,hz in ((1,985248),(2,1022727)):
        for model in (1,2):
            name=f'tone-{"pal" if timing==1 else "ntsc"}-{6581 if model==1 else 8580}'
            freq=round(440*(1<<24)/hz)
            events=[]
            for e in original.events:
                if e.opcode==WRITE and e.addr in (0,1): e=replace(e,data=(freq>>(8*e.addr))&255)
                if e.opcode==WAIT and e.operand>1: e=replace(e,operand=hz*2-8 if e.operand==985248*2-8 else hz)
                events.append(e)
            h=replace(original.header,sid_model=model,timing_standard=timing,clock_num=hz,clock_den=1,stream_cycles=3*hz)
            cases[name]=(Stream(h,tuple(events)).encode(),True);tones.append(name)
    short=Stream.decode(cap.make([Event(WAIT,operand=5000),Event(EOF)]))
    for timing,hz in ((1,985248),(2,1022727)):
        for factor in (2,((1<<32)-1)//hz):
            h=replace(short.header,clock_num=hz*factor,clock_den=factor,timing_standard=timing,sid_model=2)
            cases[f'rational-{timing}-{factor}']=(Stream(h,short.events).encode(),True)
    bads={
        'model-unknown':(28,b'\x00'),'model-255':(28,b'\xff'),
        'timing-unknown':(29,b'\x00'),'timing-3':(29,b'\x03'),
        'zero-den':(24,bytes(4)),'zero-num':(20,bytes(4)),
        'off-by-one-clock':(20,struct.pack('<I',985249)),
        'ntsc-with-pal-clock':(29,b'\x02'),
        'pal-with-ntsc-clock':(20,struct.pack('<I',1022727)),
        'den-overflow':(24,struct.pack('<I',0xffffffff))}
    for name,(offset,value) in bads.items():
        b=bytearray(short.encode());b[offset:offset+len(value)]=value;cases[name]=(bytes(b),False)
    b=bytearray(short.encode());struct.pack_into('<II',b,20,(985248*65537)&0xffffffff,65537)
    cases['32-bit-multiply-wrap']=(bytes(b),False)
    results=[]
    for name,(data,good) in cases.items():
        path=out/(name+'.mvgmsid');path.write_bytes(data)
        if good: Stream.decode(data).validate()
        cmd=[str(out/'obj/Vc2_sim_top'),str(path),'good' if good else 'reject']
        if name in tones: cmd.append(str(out/(name+'.pcm')))
        p=subprocess.run(cmd,capture_output=True,text=True)
        print(name,p.stdout.strip(),p.stderr.strip(),flush=True)
        results.append(dict(name=name,passed=p.returncode==0,output=p.stdout+p.stderr))
        if p.returncode: raise RuntimeError(name)
    assert (out/'tone-pal-6581.pcm').read_bytes()==(ref/'tone.pcm').read_bytes(),'PAL/6581 PCM changed'
    wavs=[]
    for name in tones:
        pcm=(out/(name+'.pcm')).read_bytes();path=out/(name+'.wav')
        with wave.open(str(path),'wb') as wav:
            wav.setnchannels(1);wav.setsampwidth(2);wav.setframerate(44100);wav.writeframes(pcm)
        values=[s[0] for s in struct.iter_unpack('<h',pcm)]
        assert len(values)==132300 and max(values)>min(values)
        info=dict(name=name,path=str(path),frames=len(values),minimum=min(values),maximum=max(values),
                  sha256=hashlib.sha256(path.read_bytes()).hexdigest())
        wavs.append(info);print('WAV',info,flush=True)
    # Eight sequential loads in one instance, all four combinations; previous
    # session state is dirty and every publication is checked against clean SID.
    sequence=Stream.decode(cases['tone-pal-6581'][0])
    ev=tuple(replace(e,operand=30000 if e.operand>1 else 1) if e.opcode==WAIT else e for e in sequence.events)
    sequence=Stream(replace(sequence.header,stream_cycles=sum(e.operand for e in ev if e.opcode==WAIT)),ev)
    sequence_path=out/'sequence.mvgmsid';sequence_path.write_bytes(sequence.encode())
    p=subprocess.run([str(out/'obj/Vc2_sim_top'),str(sequence_path),'sequence'],capture_output=True,text=True,check=True)
    print(p.stdout,flush=True);results.append(dict(name='eight-mixed-sessions',passed=True,output=p.stdout))
    for fault in ('starve','corrupt'):
        p=subprocess.run([str(out/'obj/Vc2_sim_top'),str(out/'record-capacity.mvgmsid'),fault],capture_output=True,text=True,check=True)
        print(p.stdout,flush=True);results.append(dict(name='ddr-'+fault,passed=True,output=p.stdout))
    cap.build(out/'clock','tb_clock',[here/'tb_clock.sv',ROOT/'rtl/engine_c_c3/sid_native_scheduler.sv'])
    p=subprocess.run([str(out/'clock/Vtb_clock')],capture_output=True,text=True,check=True)
    print(p.stdout,flush=True);results.append(dict(name='clock-input-latch-and-large-denominator',passed=True,output=p.stdout))
    cap.build(out/'shell','tb_shell',[here/'tb_shell.sv',
        ROOT/'rtl/engine_c_c2_capacity/mister_vgm_md_top_v1_1.sv',ROOT/'rtl/engine_c_c2_capacity/c2_profile.sv',
        ROOT/'rtl/engine_c_c2/shell/golden_player_shell_upload.sv',ROOT/'rtl/vgm_ddram_backend.sv',*sources()])
    for filename,opts in [('sequence.mvgmsid',['+MODEL_SEQUENCE']),('maximum-dense.mvgmsid',[]),
                          ('unaligned-4194305.mvgmsid',['+REJECT'])]:
        p=subprocess.run([str(out/'shell/Vtb_shell'),'+STREAM='+str(out/filename),*opts],capture_output=True,text=True,check=True)
        print(p.stdout,flush=True);results.append(dict(name='shell-'+filename,passed=True,output=p.stdout))
    (out/'results.json').write_text(json.dumps(results,indent=2)+'\n')
    (out/'wavs.json').write_text(json.dumps(wavs,indent=2)+'\n')
    print('SIMULATION',len(results),'cases; four WAVs; PAL PCM bit-exact')

if __name__=='__main__': main()
