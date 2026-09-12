#!/usr/bin/env python3
"""Packed decoder simulation only. Frozen SID, scheduler and C4 transport."""
import argparse
from dataclasses import replace
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import struct
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT/'tools/engine_c_packed_v2'))
import packed
v=packed.v1
spec=importlib.util.spec_from_file_location('c4_tests',ROOT/'tools/engine_c_c4/run_tests.py')
c4=importlib.util.module_from_spec(spec);spec.loader.exec_module(c4)
extra=[ROOT/'rtl/engine_c_packed_v2'/n for n in ('packed_byte_reader.sv','packed_stream.sv','version_dispatch.sv')]

def sources():
    return [ROOT/'rtl/engine_c_packed_v2/engine_c_lab.sv' if p.name=='engine_c_lab.sv' else p for p in c4.sources()]+extra

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--out',type=Path,required=True)
    ap.add_argument('--only',choices=['decoder','audio','transport','capacity','baseline','timing','all'],default='all')
    ap.add_argument('--reuse-build',action='store_true')
    args=ap.parse_args();out=args.out.resolve();out.mkdir(parents=True,exist_ok=True)
    prior=Path('/Users/daizo/Projects/MegaVGMPlayer_EngineC_PhaseC3_Artifacts')
    corpus=Path('/Users/daizo/Projects/MegaVGMPlayer_EngineC_PackedV2_Artifacts')
    results=[]
    def run(name,cmd,env=None):
        r=subprocess.run(list(map(str,cmd)),cwd=ROOT,capture_output=True,text=True,env=env)
        (out/(name+'.log')).write_text(r.stdout+r.stderr)
        results.append(dict(name=name,passed=r.returncode==0,output=r.stdout+r.stderr))
        (out/('results-'+args.only+'.json')).write_text(json.dumps(results,indent=2)+'\n')
        print(name,r.stdout.strip(),r.stderr.strip(),flush=True)
        if r.returncode:raise RuntimeError(name)
    def build(name,top,files,cpp=None):
        if not args.reuse_build:c4.cap.build(out/name,top,files,cpp)
    def vector(name,raw,good=True):
        path=out/(name+'.mvgmsid2');path.write_bytes(raw)
        tracepath=out/(name+'.trace')
        if good:
            t=packed.decode(raw)
            tracepath.write_bytes(b''.join(struct.pack('<QBB',*w) for w in t.writes)+struct.pack('<QBB',t.metadata.stream_cycles,255,0))
        else:tracepath.write_bytes(b'')
        run(name,[out/'decoder/Vdecoder_top',path,tracepath,'good' if good else 'reject'])
    if args.only in ('decoder','all'):
        build('decoder','decoder_top',extra[:2]+[ROOT/'rtl/engine_c_c2_capacity/c2_ddr_mux.sv',HERE/'decoder_top.sv'],HERE/'decoder_main.cpp')
        for timing in ('pal','ntsc'):
            for model in (6581,8580):
                name=f'tone-{timing}-{model}';vector(name,packed.pack((prior/(name+'.mvgmsid')).read_bytes()))
        evidence=json.loads((corpus/'results.json').read_text())
        for r in evidence:
            a=(Path('/Users/daizo/Downloads')/r['source_name']).read_bytes()
            b=(corpus/r['output_name']).read_bytes();packed.equivalent(a,b)
            vector(Path(r['source_name']).stem,b)
        for delta in (0,1,127,128,16383,16384,1<<32,1<<63,(1<<64)-1):
            t=packed.Trace(packed.Metadata(stream_cycles=delta),((delta,24,15),))
            vector('delta-'+str(delta),packed.encode(t))
        vector('eof-only',packed.encode(packed.Trace(packed.Metadata(),())))
        vector('final-wait',packed.encode(packed.Trace(packed.Metadata(stream_cycles=30000),((0,0,0),(1,0,0)))))
        # Corrupt wire data; bypass encoder intentionally. Host must reject too.
        def wire(body,count=0,cycles=0):
            h=bytearray(packed.encode(packed.Trace(packed.Metadata(),()))[:128])
            struct.pack_into('<3Q',h,40,count,len(body),cycles)
            return bytes(h)+body
        bads={
            'noncanonical':wire(b'\x80\x00\xff'),
            'overflow-varint':wire(b'\xff'*9+b'\x02\xff'),
            'truncated-varint':wire(b'\x80\x80'),
            'overlong':wire(b'\x80'*10+b'\x01\xff'),
            'invalid-reg':wire(b'\x00\x19\x00\x00\xff',1),
            'missing-eof':wire(b'\x80\x80\x01\x00\x00',1,16384),
            'trailing':wire(b'\x00\xff\x00'),
            'same-cycle':wire(b'\x00\x00\x00\x00\x01\x01\x00\xff',2),
            'cycle-overflow':wire(packed.uleb(v.U64_MAX)+b'\x00\x00\x01\xff',1,v.U64_MAX),
            'truncated-data':wire(b'\x80\x80\x80\x01\x00',1,1<<21),
        }
        good=packed.encode(packed.Trace(packed.Metadata(stream_cycles=10),((1,0,0),)))
        for off,data in [(8,b'\x03'),(10,b'\x01'),(12,b'\x7f'),(14,b'\x10'),(16,b'\x20'),
                         (20,bytes(4)),(24,bytes(4)),(28,b'\x00'),(29,b'\x03'),(30,b'\x02'),
                         (31,b'\x01'),(36,b'\x01'),(40,b'\xff'*8),(48,b'\xff'*8),(64,b'\x01')]:
            raw=bytearray(good);raw[off:off+len(data)]=data;bads[f'header-{off}']=bytes(raw)
        for name,raw in bads.items():
            try:packed.decode(raw)
            except packed.FormatError:pass
            else:raise AssertionError('host unexpectedly accepted '+name)
            vector(name,raw,False)
        for name,raw in [('loop-unsupported',packed.encode(packed.Trace(packed.Metadata(flags=v.LOOP_VALID,
                            stream_cycles=10,loop_start_cycle=1,loop_end_cycle=10),((1,0,0),)))),
                         ('wrong-clock',packed.encode(packed.Trace(packed.Metadata(clock_num=1),())))]:
            vector(name,raw,False) # Valid format; explicitly outside C4 admitted subset.
        run('ddr-short',[out/'decoder/Vdecoder_top',out/'Commando_60s.mvgmsid2',out/'Commando_60s.trace','short'])
        for delay in (128,256,512):
            run('latency-'+str(delay),[out/'decoder/Vdecoder_top',out/'Volfied_10s.mvgmsid2',out/'Volfied_10s.trace','good',delay])
    if args.only in ('capacity','all'):
        build('decoder','decoder_top',extra[:2]+[ROOT/'rtl/engine_c_c2_capacity/c2_ddr_mux.sv',HERE/'decoder_top.sv'],HERE/'decoder_main.cpp')
        for n in (131071,131072,131073,4194303,4194304,4194305):
            count,extra_bytes=divmod(n-130,3)
            first_delta=(1,128,16384)[extra_bytes]
            body=packed.uleb(first_delta)+b'\x00\x00'+b'\x01\x00\x00'*(count-1)+b'\x00\xff'
            raw=packed.Header(packed.Metadata(stream_cycles=first_delta+count-1),count,len(body)).encode()+body
            assert len(raw)==n
            vector('packed-bytes-'+str(n),raw,n<=4194304)
    if args.only in ('baseline','all'):
        build('raw','c2_sim_top',sources()+[ROOT/'tools/engine_c_c4/sim_top.sv'],HERE/'sim_main.cpp')
        for r in json.loads((prior/'results.json').read_text()):
            path=prior/(r['name']+'.mvgmsid')
            if not path.exists() or r['name'].startswith('tone-'):continue
            run('baseline-'+r['name'],[out/'raw/Vc2_sim_top',path,'good' if 'SESSION 0' in r['output'] else 'reject'])
        for name in ('minimal','same-value-rewrite','consecutive-waits'):
            a=prior/(name+'.mvgmsid');b=out/(name+'.v2');b.write_bytes(packed.pack(a.read_bytes()))
            run('v2-scheduler-'+name,[out/'raw/Vc2_sim_top',b,'good'],dict(os.environ,GOLDEN_V1=str(a)))
    if args.only in ('timing','all'):
        build('raw','c2_sim_top',sources()+[ROOT/'tools/engine_c_c4/sim_top.sv'],HERE/'sim_main.cpp')
        a=prior/'record-capacity.mvgmsid';b=out/'dense.mvgmsid2';b.write_bytes(packed.pack(a.read_bytes()))
        for delay in (64,128,256,512):
            run('dense-native-latency-'+str(delay),[out/'raw/Vc2_sim_top',b,'good'],dict(os.environ,GOLDEN_V1=str(a),DDR_DELAY=str(delay)))
        original=v.Stream.decode(a.read_bytes())
        ntsc=v.Stream(replace(original.header,timing_standard=2,clock_num=1022727),original.events)
        na=out/'dense-ntsc.v1';nb=out/'dense-ntsc.v2';na.write_bytes(ntsc.encode());nb.write_bytes(packed.pack(na.read_bytes()))
        run('dense-native-ntsc-latency-512',[out/'raw/Vc2_sim_top',nb,'good'],dict(os.environ,GOLDEN_V1=str(na),DDR_DELAY='512'))
        a=Path('/Users/daizo/Downloads/Commando_270s.mvg');b=corpus/'Commando_270s.mvgmsid2'
        run('integrated-commando270',[out/'raw/Vc2_sim_top',b,'prefix'],dict(os.environ,GOLDEN_V1=str(a),DDR_DELAY='64'))
    if args.only in ('audio','all'):
        build('raw','c2_sim_top',sources()+[ROOT/'tools/engine_c_c4/sim_top.sv'],HERE/'sim_main.cpp')
        for timing in ('pal','ntsc'):
            for model in (6581,8580):
                name=f'tone-{timing}-{model}';a=prior/(name+'.mvgmsid');b=out/(name+'.mvgmsid2')
                b.write_bytes(packed.pack(a.read_bytes()))
                run('v1-'+name,[out/'raw/Vc2_sim_top',a,'good',out/(name+'-v1.pcm')],dict(os.environ,NATIVE_PCM=str(out/(name+'-v1.native32'))))
                run('v2-'+name,[out/'raw/Vc2_sim_top',b,'good',out/(name+'-v2.pcm')],dict(os.environ,GOLDEN_V1=str(a),NATIVE_PCM=str(out/(name+'-v2.native32'))))
                assert (out/(name+'-v1.pcm')).read_bytes()==(out/(name+'-v2.pcm')).read_bytes(),'PCM differs'
                assert (out/(name+'-v1.native32')).read_bytes()==(out/(name+'-v2.native32')).read_bytes(),'full-width native publication differs'
                assert (out/(name+'-v2.native32')).stat().st_size==(v.Stream.decode(a.read_bytes()).header.stream_cycles-1)*4,'native sample count'
                print('PCM BIT-EXACT',name,hashlib.sha256((out/(name+'-v1.pcm')).read_bytes()).hexdigest(),flush=True)
        a=prior/'sequence.mvgmsid';b=out/'sequence.mvgmsid2';b.write_bytes(packed.pack(a.read_bytes()))
        run('v1-v2-v1',[out/'raw/Vc2_sim_top',a,'good'],dict(os.environ,ALTERNATE_V2=str(b)))
        a=prior/'record-capacity.mvgmsid';b=out/'dense.mvgmsid2';b.write_bytes(packed.pack(a.read_bytes()))
        run('fifo-starvation',[out/'raw/Vc2_sim_top',b,'starve'],dict(os.environ,GOLDEN_V1=str(a)))
        run('v1-commando270-oversize',[out/'raw/Vc2_sim_top','/Users/daizo/Downloads/Commando_270s.mvg','reject'])
    if args.only in ('transport','all'):
        shell=[ROOT/'rtl/engine_c_c4'/n for n in ('mister_vgm_md_top.sv','c4_profile.sv','ddr_health.sv','transport.sv','megavgm_playlist_status_export.sv')]
        shell += [ROOT/'rtl/transport_v1_3/megavgm_transport_owner.sv',ROOT/'rtl/engine_c_c2/shell/golden_player_shell_upload.sv',ROOT/'rtl/vgm_ddram_backend.sv',*sources()]
        build('transport','tb_transport',[ROOT/'tools/engine_c_c4/defines.sv',HERE/'tb_transport.sv',*shell])
        tone=Path('/Users/daizo/Projects/MegaVGMPlayer_EngineC_C4_CoreName_Artifacts/tail.mvgmsid')
        for name,opts in [('v2',[]),('mixed',['+MIXED']),('v1',['+V1_ONLY'])]:
            run('transport-'+name,[out/'transport/Vtb_transport','+STREAM='+str(tone),*opts])

if __name__=='__main__':main()
