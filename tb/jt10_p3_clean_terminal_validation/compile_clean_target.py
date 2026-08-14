#!/usr/bin/env python3
"""Compile the isolated clean P3 graph; all HDL inputs are repo-relative."""
from __future__ import annotations
import hashlib,json,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
REFERENCE=ROOT/'docs/jt10_phase_monitor_contract_fix/COMPILE_MANIFEST.json'
OUT=Path('/private/tmp/jt10-p3-clean-target-detached-v2')
CAN='tb/jt10_p3_clean_terminal_validation/generated/canonical_pr.sv'
REP={'tb/jt10_phase_monitor_contract_fix/tb_phase_contract_targeted.sv':'tb/jt10_p3_clean_terminal_validation/tb_p3_clean_target_actual.sv','tb/jt10_final_public_zero_dwell/candidates/s3_v3_wrapper.sv':'tb/jt10_p3_clean_terminal_validation/generated/p3_clean_v3_wrapper.sv','tb/jt10_phase_monitor_contract_fix/candidates/p3_combined.sv':'tb/jt10_p3_clean_terminal_validation/generated/p3_clean_s4_top.sv','/private/tmp/jt10-final-dwell-target/canonical_pr.sv':CAN}
B3='tb/jt10_natural_start_monitor_fix/natural_start_monitors.sv'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def role(p):
 if p==CAN:return 'CANONICAL_P_R'
 if p.endswith('p3_clean_s4_top.sv'):return 'CLEAN_LEGACY_DIAGNOSTIC_NO_TERMINAL_OWNER'
 if p.endswith('p3_clean_v3_wrapper.sv'):return 'H4_V3_CLEAN_WRAPPER'
 if p.endswith('phase_monitor_contract.sv'):return 'P3'
 if p.endswith('natural_start_monitors.sv'):return 'B3'
 if p.endswith('tb_p3_clean_target_actual.sv'):return 'TARGET_TB'
 if p.endswith('z3_fm_ssg_zero.sv'):return 'A1_Z3'
 if p.endswith('semantic_silence_monitor.sv'):return 'S3'
 if p.endswith('gatee_v3_epoch_interface.sv'):return 'V3'
 if p.startswith('rtl/'):return 'DUT'
 return 'SUPPORT'
def main():
 src=[REP.get(x['path'],x['path']) for x in json.loads(REFERENCE.read_text())['sources']]
 if B3 not in src:src.insert(2,B3)
 if len(src)!=len(set(src)):raise SystemExit('duplicate HDL source')
 if any(Path(x).is_absolute() for x in src):raise SystemExit('absolute HDL input')
 if any(not (ROOT/x).is_file() for x in src):raise SystemExit('missing HDL input')
 OUT.mkdir(parents=True,exist_ok=True);vvp=OUT/'p3_clean_target.vvp';cmd=['iverilog','-g2012','-s','jt10_p3_clean_isolated_target','-o',str(vvp),*src]
 r=subprocess.run(cmd,cwd=ROOT,text=True,capture_output=True);(OUT/'compile.stdout').write_text(r.stdout);(OUT/'compile.stderr').write_text(r.stderr)
 m={'command':cmd,'returncode':r.returncode,'absolute_hdl_inputs':0,'sources':[{'path':x,'sha256':sha(ROOT/x),'size':(ROOT/x).stat().st_size,'role':role(x)} for x in src],'vvp_sha256':sha(vvp) if vvp.exists() else None}
 mp=OUT/'compile_manifest.json';mp.write_text(json.dumps(m,indent=2,sort_keys=True)+'\n')
 if r.returncode:raise SystemExit(r.returncode)
 print(json.dumps({'absolute_hdl_inputs':0,'compile_manifest_sha256':sha(mp),'vvp_sha256':m['vvp_sha256']},sort_keys=True))
if __name__=='__main__':main()
