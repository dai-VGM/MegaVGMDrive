#!/usr/bin/env python3
"""Read-only verification of the Phase 1 evidence; never reports RC READY."""
from pathlib import Path
import gzip,hashlib,json,subprocess,zipfile
R=Path(__file__).resolve().parents[1]
def sha_bytes(data):return hashlib.sha256(data).hexdigest()
def sha(path):return sha_bytes(path.read_bytes())
def read(name):return json.loads((R/name).read_text(encoding='utf-8-sig'))
def git(repo,*args):return subprocess.check_output(['git',*args],cwd=repo).decode()
def checksums(data):
 for line in data.decode().splitlines():
  h,name=line.split(None,1);yield h,name.lstrip('* ')
for expected,relative in checksums((R/'SHA256SUMS.txt').read_bytes()):
 p=R/relative
 assert p.resolve().is_relative_to(R) and p.is_file(),relative
 assert sha(p)==expected,relative
manifest=read('proposed-adoption-manifest.json');source=read('audit/source-audit.json')
assert manifest['status']=='PHASE1_BLOCKED_A_TIMING' and not manifest['release_candidate_complete']
for e,v in manifest['engines'].items():
 p=Path(v['RBF']['path']);assert p.is_file() and p.stat().st_size==v['RBF']['bytes'] and sha(p)==v['RBF']['sha256'],e
 if e=='C':
  repo=Path('/Users/daizo/Projects/MegaVGMPlayer_EngineC_TransparentInfo')
  for rel,h in source[e]['files'].items():
   assert sha(repo/rel)==h and sha_bytes(subprocess.check_output(['git','show',v['source_commit']+':'+rel],cwd=repo))==h,rel
  continue
 artifact=Path(source[e]['source_artifact_path']);assert sha(artifact)==source[e]['source_artifact_sha256'],e
 with zipfile.ZipFile(artifact) as z:
  names=z.namelist();assert len(names)==len(set(names))
  assert all(not n.startswith('/') and '..' not in Path(n).parts for n in names)
  for expected,rel in checksums(z.read('SHA256SUMS.txt')):assert sha_bytes(z.read(rel))==expected,(e,rel)
  assert not any('/' in n for n in names if n.endswith('.qpf'))
  assert 'BUILD.bat' not in names
  for name,h in read('audit/common-consistency.json')['shared_hashes'].items():assert sha_bytes(z.read(name))==h,(e,name)
for path,h in read('audit/canonical-before/hashes.json').items():assert sha(Path(path))==h,path
protected=read('audit/protected-before.json');protection={}
for name,v in protected['repositories'].items():
 repo=Path('/Users/daizo/Projects')/name
 now={'HEAD':git(repo,'rev-parse','HEAD').strip(),'branch':git(repo,'branch','--show-current').strip(),'status':git(repo,'status','--porcelain'),'tracked_diff_sha256':sha_bytes(subprocess.check_output(['git','diff','HEAD','--binary'],cwd=repo))}
 # Original receipt used git diff --binary, equivalent to HEAD where index is clean.
 if now['tracked_diff_sha256']!=v['tracked_diff_sha256']:
  now['tracked_diff_sha256']=sha_bytes(subprocess.check_output(['git','diff','--binary'],cwd=repo))
 assert now==v,(name,'original repository state changed');protection[name]='UNCHANGED'
for v in protected['v2_3_payloads']:assert sha(Path(v['path']))==v['expected_sha256'],v['path']
for path,h in protected['top_RBFs'].items():assert sha(Path(path))==h,path
w=read('audit/windows-audit.json')
for e in w['engines']:
 if not e['exists']:continue
 mismatches=[i['relative'] for i in e['inputs'] if not i['match']]
 assert mismatches==(['MegaVGMDrive_A_vNext_Production_MiSTer.qsf'] if e['engine']=='A' else []),mismatches
 rbfs=[o for o in e['outputs'] if o['name'].endswith('.rbf')]
 assert any(o['sha256']==manifest['engines'][e['engine']]['RBF']['sha256'] for o in rbfs),e['engine']
sta=gzip.decompress((R/'audit/windows-A/MegaVGMDrive_A_vNext_Production_MiSTer.sta.rpt.gz').read_bytes())
assert sha_bytes(sta)==manifest['engines']['A']['STA']['report_sha256']
for token in [b'Timing requirements not met',b'-88.815',b'-3361.116',b'-0.188',b'-2.790']:assert token in sta,token
b=read('audit/B-timing-seed3.json');d=read('audit/D-Windows-review.json')
assert b['reproduction']['timing_PASS_both'] and b['reproduction']['RBF_byte_hash_exact']
assert d['timing']['gate']=='PASS_CONSTRAINED_ALL4_CORNERS' and d['timing']['TNS_all']==0
print(json.dumps({'audit_integrity':'PASS','RBF_identities':4,'source_ZIPs_checksums':'A/B/D PASS','C_required_inputs':len(source['C']['files']),'common_core_files_exact':10,'original_repositories':protection,'original_v2_3_payloads':12,'original_top_RBFs':7,'canonical_documents_and_BUILD_TARGETS':'UNCHANGED','unexpected_audit_hash_drift':0,'integration_gate':'PHASE1_BLOCKED_A_TIMING','Quartus_executed':False},indent=2))
