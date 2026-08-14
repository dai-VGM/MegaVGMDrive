#!/usr/bin/env python3
"""Durable detached child status recorder for the sole L-B actual-DUT launch."""
from __future__ import annotations
import hashlib,json,os,subprocess,sys,time
from datetime import datetime,timezone
from pathlib import Path
OUT,VVP,CWD=map(Path,sys.argv[1:4])
def sha(p):
 h=hashlib.sha256()
 with p.open('rb') as f:
  for b in iter(lambda:f.read(1048576),b''):h.update(b)
 return h.hexdigest()
def write(name,obj):
 p=OUT/name;t=p.with_name(p.name+'.tmp');t.write_text(json.dumps(obj,indent=2,sort_keys=True)+'\n');os.replace(t,p)
OUT.mkdir(parents=True,exist_ok=True); so=OUT/'stdout.log'; se=OUT/'stderr.log'
meta={'argv':['vvp','-n',str(VVP)],'cwd':str(CWD),'vvp_sha256':sha(VVP),'start_timestamp':datetime.now(timezone.utc).isoformat(),'start_monotonic_ns':time.monotonic_ns(),'pid':None,'timeout':False,'exception':None,'stdout_path':str(so),'stderr_path':str(se)}
write('launch_metadata.json',meta)
try:
 with so.open('wb') as out,se.open('wb') as err:
  child=subprocess.Popen(meta['argv'],cwd=CWD,stdin=subprocess.DEVNULL,stdout=out,stderr=err,shell=False)
  meta['pid']=child.pid;meta['alive_at_handoff']=child.poll() is None;write('launch_metadata.json',meta);(OUT/'pid.txt').write_text(str(child.pid)+'\n');rc=child.wait()
 meta['raw_child_returncode']=rc
except Exception as e: meta['raw_child_returncode']=None;meta['exception']={'type':type(e).__name__,'message':str(e)}
meta['end_timestamp']=datetime.now(timezone.utc).isoformat();meta['end_monotonic_ns']=time.monotonic_ns();meta['elapsed_ns']=meta['end_monotonic_ns']-meta['start_monotonic_ns']
for n,p in [('stdout',so),('stderr',se)]: meta[n+'_bytes']=p.stat().st_size if p.exists() else 0;meta[n+'_sha256']=sha(p) if p.exists() else hashlib.sha256(b'').hexdigest()
write('exit_status.json',meta)
