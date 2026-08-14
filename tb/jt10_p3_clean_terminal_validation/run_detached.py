#!/usr/bin/env python3
from __future__ import annotations
import hashlib,json,os,subprocess,sys,time
from datetime import datetime,timezone
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];OUT=Path('/private/tmp/jt10-p3-clean-target-detached-v2');VVP=OUT/'p3_clean_target.vvp';MAN=OUT/'compile_manifest.json';SIDE=Path(__file__).resolve().parent/'sidecar.py'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def write(p,o):
 t=p.with_name(p.name+'.tmp');t.write_text(json.dumps(o,indent=2,sort_keys=True)+'\n');os.replace(t,p)
def main():
 if not VVP.is_file() or not MAN.is_file():raise SystemExit('compiled VVP or manifest missing')
 m={'sidecar_argv':[sys.executable,str(SIDE),str(OUT),str(VVP),str(MAN),str(ROOT)],'vvp_sha256':sha(VVP),'compile_manifest_sha256':sha(MAN),'launch_timestamp':datetime.now(timezone.utc).isoformat()};write(OUT/'launcher_metadata.json',m)
 p=subprocess.Popen(m['sidecar_argv'],cwd=ROOT,stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,shell=False,start_new_session=True)
 end=time.monotonic()+5
 while time.monotonic()<end and not (OUT/'launch_metadata.json').exists():time.sleep(.02)
 if not (OUT/'launch_metadata.json').exists():raise SystemExit('sidecar launch handshake missing')
 c=json.loads((OUT/'launch_metadata.json').read_text());m.update({'sidecar_pid':p.pid,'vvp_pid':c.get('pid'),'alive_at_handoff':c.get('alive_at_handoff')});write(OUT/'launcher_metadata.json',m)
 if not m['vvp_pid'] or not m['alive_at_handoff']:raise SystemExit('VVP not alive at handoff')
 print(json.dumps(m,sort_keys=True))
if __name__=='__main__':main()
