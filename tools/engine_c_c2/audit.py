#!/usr/bin/env python3
"""Read-only source/provenance audit and open-source emu elaboration gate."""
from collections import Counter
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent

def run(*cmd):
    return subprocess.check_output(cmd,cwd=ROOT,text=True)

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--out',type=Path,default=Path('/tmp/megavgm-engine-c-c2'))
    ap.add_argument('--upstream',type=Path)
    args=ap.parse_args(); args.out.mkdir(parents=True,exist_ok=True)
    lock=json.loads((HERE/'source_lock.json').read_text())
    for name,expected in lock['upstream_sha256'].items():
        data=(ROOT/'rtl/engine_c_c2/vendor/upstream'/name).read_bytes()
        assert hashlib.sha256(data).hexdigest()==expected,name
        if args.upstream:
            upstream=subprocess.check_output(['git','-C',str(args.upstream),'show',
                                             lock['sid_commit']+':rtl/sid/'+name])
            assert data==upstream,name
    # All pre-existing files, not just C0/C1, must remain identical to C1.
    changed=run('git','diff','--name-only',lock['base']).splitlines()
    allowed=('rtl/engine_c_c2/','hw/engine_c_c2/','tools/engine_c_c2/','docs/engine_c_c2/')
    assert all(f.startswith(allowed) for f in changed),changed
    assert not run('git','diff',lock['base'],'--','tools/engine_c_c0','tools/engine_c_c1')
    qsf=ROOT/'hw/engine_c_c2/MegaVGMPlayer_EngineC_C2_Lab_MiSTer.qsf'
    resolved=run('tclsh',str(HERE/'audit_qsf.tcl'),str(qsf))
    entries=[line.split('\t',1) for line in resolved.splitlines()]
    files=[Path(v) for k,v in entries if k in ('SYSTEMVERILOG_FILE','VERILOG_FILE','VHDL_FILE')]
    assert len(files)==len(set(files)),'duplicate source file'
    module_paths={}
    for f in files:
        if f.suffix.lower() in ('.v','.sv'):
            for name in re.findall(r'^\s*module\s+(\w+)',f.read_text(),re.M):
                module_paths.setdefault(name,[]).append(str(f.relative_to(ROOT)))
    for name in ['sid_top','sid_voice','sid_filter','sid_tables','sid_dac','sid_envelope',
                 'mister_vgm_md_top','emu','golden_player_shell_v1_1_profile','engine_c_lab']:
        assert len(module_paths.get(name,[]))==1,(name,module_paths.get(name))
    assert all('/vendor/upstream/' not in str(f) for f in files)
    for banned in ['rtl/mister_vgm_md_top.sv','rtl/vgm_loaded_player.sv','rtl/emu.sv']:
        assert ROOT/banned not in files,banned
    # Only active macros in exact QSF, simulator-specific HPS/PLL stubs only here.
    macros=['+define+'+v for k,v in entries if k=='MACRO']
    core=[str(f) for f in files if str(f.relative_to(ROOT)).startswith('rtl/') and '/pll' not in str(f)]
    cmd=['verilator','--lint-only','--timing','-Wno-fatal','--top-module','emu',
         '-I.','-Itb',*macros,'tb/hps_io_elab_stub.sv','tb/megavgm_pll_elab_stubs.sv',*core]
    with (args.out/'emu-elaboration.log').open('w') as log:
        subprocess.run(cmd,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,check=True)
    report={'source_files':len(files),'modules':module_paths,'macros':macros,
            'upstream_sha_exact':True,'c0_c1_unchanged':True,
            'qsf_tcl_source_resolution':'OK (not Quartus)',
            'emu_elaboration':'OK (HPS/PLL simulation stubs; not full sys_top)',
            'production_files_unchanged':True}
    (args.out/'source-audit.json').write_text(json.dumps(report,indent=2)+'\n')
    (args.out/'resolved-sources.txt').write_text(resolved)
    print(json.dumps({k:v for k,v in report.items() if k!='modules'},indent=2))

if __name__=='__main__': main()
