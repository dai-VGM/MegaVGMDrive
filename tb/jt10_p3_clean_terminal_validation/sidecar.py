#!/usr/bin/env python3
from __future__ import annotations
import hashlib,json,os,subprocess,sys,time
from datetime import datetime,timezone
from pathlib import Path
OUT,VVP,MANIFEST,CWD=map(Path,sys.argv[1:5])
def sha(p):
 h=hashlib.sha256()
 with p.open('rb') as f:
  for b in iter(lambda:f.read(1048576),b''):h.update(b)
 return h.hexdigest()
def write(n,o):
 p=OUT/n;t=p.with_name(p.name+'.tmp');t.write_text(json.dumps(o,indent=2,sort_keys=True)+'\n');os.replace(t,p)
OUT.mkdir(parents=True,exist_ok=True);so=OUT/'stdout.log';se=OUT/'stderr.log'
m={'argv':['vvp','-n',str(VVP)],'cwd':str(CWD),'vvp_sha256':sha(VVP),'compile_manifest_sha256':sha(MANIFEST),'start_timestamp':datetime.now(timezone.utc).isoformat(),'start_monotonic_ns':time.monotonic_ns(),'pid':None,'timeout':False,'exception':None,'stdout_path':str(so),'stderr_path':str(se)}
write('launch_metadata.json',m)
try:
 with so.open('wb') as out,se.open('wb') as err:
  c=subprocess.Popen(m['argv'],cwd=CWD,stdin=subprocess.DEVNULL,stdout=out,stderr=err,shell=False);m['pid']=c.pid;m['alive_at_handoff']=c.poll() is None;write('launch_metadata.json',m);(OUT/'pid.txt').write_text(str(c.pid)+'\n');m['raw_child_returncode']=c.wait()
except Exception as e:m['raw_child_returncode']=None;m['exception']={'type':type(e).__name__,'message':str(e)}
m['end_timestamp']=datetime.now(timezone.utc).isoformat();m['end_monotonic_ns']=time.monotonic_ns();m['elapsed_ns']=m['end_monotonic_ns']-m['start_monotonic_ns']
for n,p in [('stdout',so),('stderr',se)]:m[n+'_bytes']=p.stat().st_size if p.exists() else 0;m[n+'_sha256']=sha(p) if p.exists() else hashlib.sha256(b'').hexdigest()
write('exit_status.json',m)
