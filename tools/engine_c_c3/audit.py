#!/usr/bin/env python3
"""Source-only scope, capacity, QSF resolution and emu elaboration audit."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT=Path(__file__).resolve().parents[2]
BASE='c9fc9a1b35740c616f72af5116359ee41db944e7'
ALLOWED=('rtl/engine_c_c3/','hw/engine_c_c3/',
         'tools/engine_c_c3/','docs/engine_c_c3/')
def run(*args): return subprocess.check_output(args,cwd=ROOT,text=True)
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,default=Path('/Users/daizo/Projects/MegaVGMPlayer_EngineC_PhaseC3_Artifacts'))
    args=ap.parse_args();out=args.out;out.mkdir(parents=True,exist_ok=True)
    changed=run('git','diff','--name-only',BASE).splitlines()
    untracked=run('git','ls-files','--others','--exclude-standard').splitlines()
    assert all(p.startswith(ALLOWED) for p in changed+untracked),(changed,untracked)
    # Stronger than selected hashes: EVERY previously tracked file is frozen.
    previous=run('git','ls-tree','-r','--name-only',BASE).splitlines()
    assert not set(previous).intersection(changed),'modified frozen file'
    qsf=ROOT/'hw/engine_c_c3/MegaVGMPlayer_EngineC_C3_Lab_MiSTer.qsf'
    resolved=run('tclsh','tools/engine_c_c2/audit_qsf.tcl',str(qsf))
    entries=[s.split('\t',1) for s in resolved.splitlines()]
    files=[Path(v) for k,v in entries if k in ('SYSTEMVERILOG_FILE','VERILOG_FILE','VHDL_FILE')]
    assert len(files)==len(set(files))
    modules={}
    for f in files:
        if f.suffix.lower() in ('.v','.sv'):
            for m in re.findall(r'^\s*module\s+(\w+)',f.read_text(),re.M):
                modules.setdefault(m,[]).append(str(f.relative_to(ROOT)))
    names=('emu','mister_vgm_md_top','golden_player_shell_v1_1_profile',
           'mvgmsid_loader','engine_c_lab','c2_ddr_mux','c2_record_store',
           'sid_native_scheduler','sid_session_wrapper','sid_top','sid_filter')
    for n in names: assert len(modules.get(n,[]))==1,(n,modules.get(n))
    for n in ('mvgmsid_loader','engine_c_lab','sid_native_scheduler'):
        assert 'engine_c_c3/' in modules[n][0]
    for n in ('sid_session_wrapper',):
        assert modules[n][0].startswith('rtl/engine_c_c2/')
    for f in ('rtl/engine_c_c2/engine_c_lab.sv','rtl/engine_c_c2/mvgmsid_loader.sv',
              'rtl/engine_c_c2/shell/c2_profile.sv','rtl/mister_vgm_md_top.sv','rtl/vgm_loaded_player.sv'):
        assert ROOT/f not in files,f
    macros=['+define+'+v for k,v in entries if k=='MACRO']
    assert '+define+C2_MAX_FILE_BYTES=4194304' in macros
    core=[str(f) for f in files if str(f.relative_to(ROOT)).startswith('rtl/') and '/pll' not in str(f)]
    with (out/'emu-elaboration.log').open('w') as log:
        subprocess.run(['verilator','--lint-only','--timing','-Wno-fatal','--top-module','emu',
                        '-I.','-Itb',*macros,'tb/hps_io_elab_stub.sv','tb/megavgm_pll_elab_stubs.sv',*core],
                       cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,check=True)
    report=dict(base=BASE,all_preexisting_files_unchanged=True,source_files=len(files),
                modules=modules,macros=macros,qsf_resolution='Tcl audit, not Quartus',
                elaboration='emu with HPS/PLL simulation stubs',
                max_file_bytes=4194304,max_events=262136,max_writes=131068,max_records=131069,
                raw_ddr_bytes=['0x30000000','0x30800000 (exclusive)'],
                record_ddr_bytes=['0x30800000','0x30c00000 (exclusive)'])
    (out/'source-audit.json').write_text(json.dumps(report,indent=2)+'\n')
    (out/'resolved-sources.txt').write_text(resolved)
    print(json.dumps({k:v for k,v in report.items() if k!='modules'},indent=2))
if __name__=='__main__': main()
