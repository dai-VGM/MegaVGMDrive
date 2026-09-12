#!/usr/bin/env python3
"""Read-only source-resolution/freeze and emu elaboration gates; not Quartus."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT=Path(__file__).resolve().parents[2]
BASE='bb467fca2c9ea982345645c419d9da7d21a5d095'

def run(*args):return subprocess.check_output(args,cwd=ROOT,text=True)

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,required=True);args=ap.parse_args()
    out=args.out.resolve();out.mkdir(parents=True,exist_ok=True)
    previous=set(run('git','ls-tree','-r','--name-only',BASE).splitlines())
    changed=set(run('git','diff','--name-only',BASE).splitlines())
    assert not previous.intersection(changed),'existing source was changed'
    before=(ROOT/'rtl/engine_c_c4/engine_c_lab.sv').read_text()
    after=(ROOT/'rtl/engine_c_packed_v2/engine_c_lab.sv').read_text()
    anchor='    sid_native_scheduler #'
    assert before[before.index(anchor):]==after[after.index(anchor):],'scheduler/audio/publication wiring changed'
    h=ROOT/'hw/engine_c_packed_v2'
    for name in ('sys_golden_shell.qip','sys_golden_shell.tcl'):
        assert (h/name).read_bytes()==(ROOT/'hw/engine_c_c4'/name).read_bytes()
    qsf=h/'MegaVGMPlayer_EngineC_PackedV2_Validation_MiSTer.qsf'
    lines=lambda s:[l for l in s.splitlines() if l and not l.startswith('#')]
    old=(ROOT/'hw/engine_c_c4/MegaVGMPlayer_EngineC_C4_Transport_Validation_MiSTer.qsf').read_text()
    expect=old.replace('output_files_validation','output_files_packed_v2').replace('files_engine_c_c4.qip','files_engine_c_packed_v2.qip')
    assert lines(qsf.read_text())==lines(expect),'unexpected QSF assignment'
    resolved=run('tclsh','tools/engine_c_c2/audit_qsf.tcl',str(qsf))
    entries=[line.split('\t',1) for line in resolved.splitlines()]
    files=[Path(value) for key,value in entries if key in ('SYSTEMVERILOG_FILE','VERILOG_FILE','VHDL_FILE')]
    assert len(files)==len(set(files)),'duplicate source assignment'
    modules={}
    for f in files:
        if f.suffix.lower() in ('.v','.sv'):
            for name in re.findall(r'^\s*module\s+(\w+)',f.read_text(),re.M):modules.setdefault(name,[]).append(str(f.relative_to(ROOT)))
    for name in ('emu','engine_c_lab','packed_stream','packed_byte_reader','version_dispatch','mvgmsid_loader',
                 'sid_native_scheduler','sid_session_wrapper','sid_top','sid_filter','c2_record_store','c2_ddr_mux'):
        assert len(modules.get(name,[]))==1,(name,modules.get(name))
    assert modules['mvgmsid_loader']==['rtl/engine_c_c3/mvgmsid_loader.sv']
    assert modules['sid_native_scheduler']==['rtl/engine_c_c4/sid_native_scheduler.sv']
    assert modules['engine_c_lab']==['rtl/engine_c_packed_v2/engine_c_lab.sv']
    macros=['+define+'+value for key,value in entries if key=='MACRO']
    assert '+define+C2_MAX_FILE_BYTES=4194304' in macros
    assert '+define+ENGINE_C_C4_MEGAVGMDRIVE_CORENAME=1' in macros
    core=[str(f) for f in files if str(f.relative_to(ROOT)).startswith('rtl/') and '/pll' not in str(f)]
    with (out/'emu-elaboration.log').open('w') as log:
        subprocess.run(['verilator','--lint-only','--timing','-Wno-fatal','--top-module','emu','-I.','-Itb',
                        *macros,'tools/engine_c_c4/hps_io_elab_stub.sv','tb/megavgm_pll_elab_stubs.sv',*core],
                       cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,check=True)
    hashes={str(f.relative_to(ROOT)):hashlib.sha256(f.read_bytes()).hexdigest() for f in files if str(f.relative_to(ROOT)).startswith('rtl/')}
    report=dict(base=BASE,preexisting_files_unchanged=True,qsf_assignments_only_output_and_qip_changed=True,
                canonical_scheduler_and_audio_wiring_identical=True,max_file_bytes=4194304,
                module_map=modules,source_sha256=hashes,source_count=len(files),
                elaboration='Verilator emu with HPS/PLL stubs; not Quartus',hardware='UNVERIFIED')
    (out/'source-audit.json').write_text(json.dumps(report,indent=2)+'\n')
    (out/'resolved-sources.txt').write_text(resolved)
    print('Source freeze, QSF exact-once resolution, emu elaboration passed:',len(files),'sources; no Quartus')

if __name__=='__main__':main()
