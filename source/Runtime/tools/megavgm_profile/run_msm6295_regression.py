#!/usr/bin/env python3
"""Full-file real VGM admission/raw identity audit, not an audio renderer."""
from pathlib import Path
import argparse,json,subprocess,hashlib,os
p=argparse.ArgumentParser();p.add_argument('--binaries',type=Path,required=True);p.add_argument('--corpus',type=Path,required=True);p.add_argument('--audit',type=Path,required=True);p.add_argument('--out',type=Path,required=True);a=p.parse_args();a.out.mkdir(parents=True,exist_ok=False)
reference=json.load(a.audit.open());paths=[];rows=[]
for v in reference['files']:
 f=a.corpus/v['path'];assert hashlib.sha256(f.read_bytes()).hexdigest()==v['sha256'];paths.append(f)
q=subprocess.run([str(a.binaries/'test_msm6295'),*[str(f) for f in paths]],capture_output=True,text=True);(a.out/'classification.tsv').write_text(q.stdout);assert q.returncode==0;lines=q.stdout.splitlines();assert len(lines)==len(paths)==64
for line,f,v in zip(lines,paths,reference['files']):
 fields=line.split('\t');expected='YM2151,MSM6295' if v['commands'].get('0xb8',0) else 'YM2151';assert fields[0]=='SUPPORTED_PROFILE_D' and fields[1]==expected;assert int(fields[2])==sum(v['commands'].values());assert hashlib.sha256(f.read_bytes()).hexdigest()==v['sha256'];rows.append({'path':str(f),'sha256':v['sha256'],'profile':fields[0],'chips':fields[1],'commands':int(fields[2]),'original_unchanged':True})
(a.out/'corpus-list.txt').write_text(''.join(str(f)+'\n' for f in paths));env=os.environ.copy();env['MEGAVGM_MSM_CORPUS_LIST']=str((a.out/'corpus-list.txt').resolve());env['MEGAVGM_MSM_CORPUS_ROOT']=str(a.corpus.resolve())
q=subprocess.run([str(a.binaries/'test_phase2a')],capture_output=True,text=True,env=env);(a.out/'controller.log').write_text(q.stdout+q.stderr);assert q.returncode==0 and 'MSM_REAL64_GENERIC_CONTROLLER_ROUTE_PASS' in q.stdout
(a.out/'results.json').write_text(json.dumps({'gate':'PASS_SCOPED_REAL64_HOST_ADMISSION_GENERIC_ROUTE','files':rows,'commands':sum(v['commands'] for v in rows),'scope':'Full-file classifier vs independent prior grammar counts and hashes; existing Controller/SwitchOwner/mock Main; original path/bytes preserved; no sound/hardware claim'},indent=2)+'\n');print('PASS full-file real64 Host admission/generic route/immutable identity')
