#!/usr/bin/env python3
"""Generate original C0-valid synthetic streams and execute the actual C2 RTL.

Build/output stays outside tracked sources. C0/C1 files are only imported/read.
"""
import argparse
from dataclasses import replace
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import sys
import wave

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/engine_c_c0'))
from mvgmsid import Header, Event, Stream, WAIT, WRITE, EOF, END_IS_CAPTURE_LIMIT

def make(events):
    cycles = sum(e.operand for e in events if e.opcode == WAIT)
    return Stream(Header(flags=END_IS_CAPTURE_LIMIT, event_count=len(events),
                         stream_bytes=16*len(events), stream_cycles=cycles), tuple(events)).encode()

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', type=Path, default=Path('/tmp/megavgm-engine-c-c2'))
    args = ap.parse_args(); out=args.out.resolve(); out.mkdir(parents=True, exist_ok=True)
    rtl=ROOT/'rtl/engine_c_c2'
    sources=sorted(rtl.glob('*.sv'))+sorted((rtl/'vendor/lab').glob('*.sv'))
    cmd=['verilator','--cc','--exe','--build','-j','4','--top-module','c2_sim_top',
         '-Wno-fatal','--Mdir',str(out/'obj'),'-CFLAGS','-O2',
         *map(str,sources),str(Path(__file__).with_name('sim_top.sv')),
         str(Path(__file__).with_name('sim_main.cpp'))]
    with (out/'build.log').open('w') as log:
        subprocess.run(cmd,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,check=True)
    tone=[]
    # Original 440 Hz saw, voice 1, ADSR and lowpass filter; no external music.
    freq=round(440*(1<<24)/985248)
    for addr,data in [(0,freq&255),(1,freq>>8),(5,0x09),(6,0xf6),
                      (0x15,7),(0x16,0x70),(0x17,0x31),(0x18,0x1f),(4,0x21)]:
        if tone: tone.append(Event(WAIT,operand=1))
        tone.append(Event(WRITE,addr,data))
    tone += [Event(WAIT,operand=985248*2-8),Event(WRITE,4,0x20),
             Event(WAIT,operand=985248),Event(EOF)]
    cases={'minimal':(make([Event(EOF)]),True),
           'tone-pal-6581':(make(tone),True),
           'same-value-rewrite':(make([Event(WRITE,0,1),Event(WAIT,operand=1),
                                     Event(WRITE,0,1),Event(EOF)]),True),
           'consecutive-waits':(make([Event(WAIT,operand=1),Event(WAIT,operand=1),Event(EOF)]),True)}
    base=make([Event(WAIT,operand=100),Event(EOF)])
    mutations={'magic':(0,b'X'),'major':(8,b'\x02'),'minor':(10,b'\x01'),
               'header-size':(12,b'\x7f'),'event-size':(14,b'\x08'),
               'flags':(16,b'\x80'),'loop-flag':(16,b'\x02'),
               'clock':(20,bytes(4)),'denominator':(24,bytes(4)),
               'model':(28,b'\x03'),'8580-unsupported':(28,b'\x02'),
               'ntsc-unsupported':(29,b'\x02'),'dual':(30,b'\x02'),
               'reserved1':(31,b'\x01'),'subtune':(32,bytes(4)),
               'reserved2':(36,b'\x01'),'count-overflow':(40,struct.pack('<Q',1<<63)),
               'count-zero':(40,bytes(8)),'byte-size':(48,b'\x10'),
               'cycle-sum':(56,b'\x65'),'duration-flag':(16,b'\x05'),
               'duration-value':(64,b'\x01'),'loop-metadata':(72,b'\x01'),
               'unknown-op':(128,b'\x7f'),'wait-address':(129,b'\x01'),
               'event-reserved':(131,b'\x01'),'zero-wait':(136,bytes(8)),
               'eof-payload':(145,b'\x01'),'missing-eof':(144,b'\x00'),
               'early-eof':(128,Event(EOF).encode())}
    for name,(offset,value) in mutations.items():
        b=bytearray(base); b[offset:offset+len(value)]=value; cases[name]=(bytes(b),False)
    for n in [0,127,128,143,159]: cases[f'truncated-{n}']=(base[:n],False)
    cases['trailing-byte']=(base+b'\0',False)
    # Build malformed records without weakening the C0 validator.
    def raw(events,cycles):
        h=Header(event_count=len(events),stream_bytes=len(events)*16,stream_cycles=cycles)
        return h.encode()+b''.join(events)
    w=Event(WRITE,0,1).encode(); eof=Event(EOF).encode()
    cases['same-cycle-writes']=(raw([w,w,eof],0),False)
    cases['wait-overflow']=(raw([Event(WAIT,operand=(1<<64)-1).encode(),Event(WAIT,operand=1).encode(),eof],0),False)
    cases['invalid-register']=(raw([bytes([1,25,0])+bytes(13),eof],0),False)
    cases['write-operand']=(raw([bytes([1])+bytes(7)+struct.pack('<Q',1),eof],0),False)
    many=[]
    for i in range(4096):
        if i: many.append(Event(WAIT,operand=1))
        many.append(Event(WRITE,0,1))
    cases['record-capacity']=(make(many+[Event(EOF)]),False)
    results=[]
    for name,(data,good) in cases.items():
        path=out/(name+'.mvgmsid'); path.write_bytes(data)
        if good: Stream.decode(data).validate()
        cmd=[str(out/'obj/Vc2_sim_top'),str(path),'good' if good else 'reject']
        if name=='tone-pal-6581': cmd += [str(out/'tone.pcm')]
        p=subprocess.run(cmd,capture_output=True,text=True)
        results.append({'name':name,'passed':p.returncode==0,'output':p.stdout+p.stderr})
        print(name,p.stdout.strip(),p.stderr.strip(),flush=True)
        if p.returncode: raise RuntimeError(name)
    with wave.open(str(out/'tone-pal-6581.wav'),'wb') as wav:
        wav.setnchannels(1); wav.setsampwidth(2); wav.setframerate(44100)
        wav.writeframes((out/'tone.pcm').read_bytes())
    samples=[s[0] for s in struct.iter_unpack('<h',(out/'tone.pcm').read_bytes())]
    section=samples[22050:66150]; mean=sum(section)/len(section)
    crossings=sum(a<mean<=b for a,b in zip(section,section[1:]))
    assert 438<=crossings<=442,('synthetic frequency',crossings)
    wav_stats={'sample_rate':44100,'frames':len(samples),'min':min(samples),
               'max':max(samples),'one_second_rising_crossings':crossings,
               'wav_sha256':hashlib.sha256((out/'tone-pal-6581.wav').read_bytes()).hexdigest(),
               'stream_sha256':hashlib.sha256(cases['tone-pal-6581'][0]).hexdigest()}
    (out/'tone-stats.json').write_text(json.dumps(wav_stats,indent=2)+'\n')
    print('WAV',wav_stats)
    cmd=['verilator','--binary','--timing','--assert','-j','4','-Wno-fatal',
         '--top-module','tb_contracts','--Mdir',str(out/'contracts'),
         str(Path(__file__).with_name('tb_contracts.sv')),
         str(rtl/'sid_native_scheduler.sv'),str(rtl/'sid_session_wrapper.sv'),
         *map(str,sorted((rtl/'vendor/lab').glob('*.sv')))]
    with (out/'contracts-build.log').open('w') as log:
        subprocess.run(cmd,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,check=True)
    p=subprocess.run([str(out/'contracts/Vtb_contracts')],capture_output=True,text=True,check=True)
    print(p.stdout)
    results.append({'name':'underflow-and-one-edge-reset','passed':True,'output':p.stdout})
    shell_stream=out/'shell-tone.mvg'
    shell_stream.write_bytes(make(tone[:-4]+[Event(WAIT,operand=10000),Event(EOF)]))
    (out/'tone-pal-6581.mvg').write_bytes(cases['tone-pal-6581'][0])
    shell=rtl/'shell'
    cmd=['verilator','--binary','--timing','--assert','-j','4','-Wno-fatal',
         '--top-module','tb_shell','-I'+str(ROOT),'--Mdir',str(out/'shell'),
         str(Path(__file__).with_name('tb_shell.sv')),
         str(shell/'mister_vgm_md_top_v1_1.sv'),str(shell/'golden_player_shell_upload.sv'),
         str(shell/'c2_profile.sv'),str(ROOT/'rtl/vgm_ddram_backend.sv'),*map(str,sources)]
    with (out/'shell-build.log').open('w') as log:
        subprocess.run(cmd,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,check=True)
    p=subprocess.run([str(out/'shell/Vtb_shell'),'+STREAM='+str(shell_stream)],
                     capture_output=True,text=True,check=True)
    print(p.stdout)
    results.append({'name':'golden-shell-ddr-upload-repeat','passed':True,'output':p.stdout})
    (out/'results.json').write_text(json.dumps(results,indent=2)+'\n')
    print(f'{len(results)} RTL cases passed (simulation only); outputs: {out}')

if __name__=='__main__': main()
