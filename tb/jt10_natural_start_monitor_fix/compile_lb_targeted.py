#!/usr/bin/env python3
"""Compile the L-B target with the existing repo-relative P3 graph."""
from __future__ import annotations
import hashlib,json,re,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
OLD=Path('/private/tmp/jt10-p3-gate-i-detached/compile_manifest.json')
OUT=Path('/private/tmp/jt10-lb-targeted-detached')
REPLACE={'tb/jt10_phase_monitor_contract_fix/tb_gate_i_actual.sv':'tb/jt10_natural_start_monitor_fix/tb_lb_targeted_actual.sv'}
MON='tb/jt10_natural_start_monitor_fix/natural_start_monitors.sv'
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    old=json.loads(OLD.read_text())
    src=[REPLACE.get(x['path'],x['path']) for x in old['sources']]
    # Z3 already provides the versioned semantic_timeline_adapter authority.
    for x in (MON,):
        if x not in src: src.insert(1,x)
    if len(src)!=len(set(src)): raise SystemExit('duplicate HDL source')
    if any(Path(x).is_absolute() for x in src): raise SystemExit('absolute HDL source')
    if any(not (ROOT/x).is_file() for x in src): raise SystemExit('missing HDL source')
    OUT.mkdir(parents=True,exist_ok=True)
    vvp=OUT/'lb_targeted.vvp'
    cmd=['iverilog','-g2012','-s','jt10_lb_targeted_actual','-o',str(vvp),*src]
    run=subprocess.run(cmd,cwd=ROOT,text=True,capture_output=True)
    (OUT/'compile.stdout').write_text(run.stdout); (OUT/'compile.stderr').write_text(run.stderr)
    manifest={'command':cmd,'returncode':run.returncode,'absolute_hdl_inputs':0,'sources':[{'path':x,'sha256':sha(ROOT/x),'size':(ROOT/x).stat().st_size} for x in src],'vvp_sha256':sha(vvp) if vvp.exists() else None}
    (OUT/'compile_manifest.json').write_text(json.dumps(manifest,indent=2,sort_keys=True)+'\n')
    if run.returncode: raise SystemExit(run.returncode)
    print(json.dumps({'absolute_hdl_inputs':0,'vvp_sha256':manifest['vvp_sha256'],'manifest_sha256':sha(OUT/'compile_manifest.json')},sort_keys=True))
if __name__=='__main__': main()
