#!/usr/bin/env python3
"""Launch exactly one detached L-B VVP and return at its durable handshake."""
from __future__ import annotations
import hashlib,json,os,subprocess,sys,time
from datetime import datetime,timezone
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];OUT=Path('/private/tmp/jt10-lb-targeted-detached');VVP=OUT/'lb_targeted.vvp';SIDE=ROOT/'tb/jt10_natural_start_monitor_fix/lb_sidecar.py'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def write(p,o):
 t=p.with_name(p.name+'.tmp');t.write_text(json.dumps(o,indent=2,sort_keys=True)+'\n');os.replace(t,p)
if not VVP.is_file(): raise SystemExit('missing compiled VVP')
meta={'sidecar_argv':[sys.executable,str(SIDE),str(OUT),str(VVP),str(ROOT)],'vvp_sha256':sha(VVP),'launch_timestamp':datetime.now(timezone.utc).isoformat()}
write(OUT/'launcher_metadata.json',meta)
p=subprocess.Popen(meta['sidecar_argv'],cwd=ROOT,stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,shell=False,start_new_session=True)
deadline=time.monotonic()+5
while time.monotonic()<deadline and not (OUT/'launch_metadata.json').exists():time.sleep(.02)
if not (OUT/'launch_metadata.json').exists():raise SystemExit('sidecar handshake missing')
child=json.loads((OUT/'launch_metadata.json').read_text());meta.update({'sidecar_pid':p.pid,'vvp_pid':child.get('pid'),'alive_at_handoff':child.get('alive_at_handoff')});write(OUT/'launcher_metadata.json',meta)
if not meta['vvp_pid'] or not meta['alive_at_handoff']:raise SystemExit('VVP not alive at handoff')
print(json.dumps(meta,sort_keys=True))
