#!/usr/bin/env python3
"""Read-only v2.4 RC identity/evidence/guard checks; no build/deploy/publication."""
from pathlib import Path
import argparse,hashlib,json,subprocess,zipfile
ROOT=Path(__file__).resolve().parents[1]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(n):return json.loads((ROOT/n).read_text())
def git(p,*args):return subprocess.check_output(['git','-C',str(p),*args],text=True)
def verify(allow_staged=False):
 m=read('release/v2.4.0/adoption-manifest.json');old=read('release/v2.4.0/v23-final-authorities.json');assert m['version']=='2.4.0'
 common=read('audit/common-consistency.json')['shared_hashes'];graphs=read('validation/v240/artifact-graph-checks.json')
 counts={}
 for e,v in m['engines'].items():
  p=ROOT/v['RBF']['integrated_path'];assert sha(p)==v['RBF']['sha256']and p.stat().st_size==v['RBF']['bytes'],e
  assert sha(Path(v['RBF']['path']))==sha(p)
  assert v['canonical_launch_path']=='/media/fat/_Custom Cores/Cores/MegaVGMDrive_'+e+'.rbf'and v['CORENAME']=='MegaVGMDrive'
  git(Path(v['source_worktree']),'cat-file','-e',v['source_commit']+'^{commit}')
  if e=='C':
   oldrbf=next(x for x in old['payloads']if x['destination'].endswith('MegaVGMDrive_C.rbf'));assert p.stat().st_size==oldrbf['bytes']and sha(p)==oldrbf['sha256']
   x=v['legacy_source_snapshot'];assert sha(ROOT/x['path'])==x['sha256']
   source=read('audit/source-audit.json')['C']['files']
   with zipfile.ZipFile(ROOT/x['path'])as z:
    assert set(z.namelist())==set(source)
    for rel,h in source.items():assert hashlib.sha256(z.read(rel)).hexdigest()==h
   counts[e]={'legacy_source_files':len(source),'RBF_unchanged':True};continue
  x=v['source_artifact'];p=ROOT/x['integrated_path'];assert sha(p)==x['source_artifact_sha256']
  assert graphs[e]['graph']['gate']=='BUILD_ARTIFACT_FRESH_EXTRACT_PASS'and not graphs[e]['compatibility']['HDL']['blockers']
  assert not graphs[e]['current_source_origin_mismatches']
  with zipfile.ZipFile(p)as z:
   names=z.namelist();assert len(names)==len(set(names));assert not any(n.startswith('/')or'..'in Path(n).parts for n in names)
   a=json.loads(z.read('ARTIFACT_MANIFEST.json'));assert a['source_commit']==v['source_commit']
   assert [n for n in names if n.endswith('.qpf')]==[a['policy']['project']+'.qpf']
   for l in z.read('SHA256SUMS.txt').decode().splitlines():h,rel=l.split(None,1);assert hashlib.sha256(z.read(rel.lstrip('* '))).hexdigest()==h
   for rel,h in common.items():assert hashlib.sha256(z.read(rel)).hexdigest()==h,(e,rel)
   counts[e]={'exact_build_inputs':len(a['origins']),'common_files':len(common),'helper_required':False}
 a=read('validation/v240/A2/windows-results.json');checks=a['all_corner_timing'];assert len(checks)==20 and all(x['worst_slack_ns']>=0 and x['violating_endpoints']==0 and x['endpoint_TNS_ns']==0 for x in checks)
 assert min(x['worst_slack_ns']for x in checks if x['check']=='setup')==0.088
 b=read('audit/B-timing-seed3.json');assert b['reproduction']['timing_PASS_both']and b['reproduction']['RBF_byte_hash_exact']
 d=read('audit/D-timing-review.json');assert d['gate']=='PASS_CONSTRAINED_ALL4_CORNERS'and d['TNS_ns_all_entries']==0
 windows=read('validation/v240/windows-input-result.json');assert not windows['mismatches']and windows['expected_hash_checks']==491
 # Required unchanged public-host payloads and protected repository state.
 guard=read('validation/v240/protected-before.json')
 for name,x in guard['repositories'].items():
  p=Path(name);now={'HEAD':git(p,'rev-parse','HEAD').strip(),'status':git(p,'status','--porcelain'),'diff':hashlib.sha256(subprocess.check_output(['git','-C',name,'diff','HEAD','--binary'])).hexdigest()};assert now==x,(name,'protected repository changed')
 for name,h in guard['files'].items():assert sha(Path(name))==h,name
 for p in (ROOT/'canonical/current').glob('*.md'):
  assert p.read_text().strip()and '2026-10-09'in p.read_text()
  if not allow_staged:assert p.read_bytes()==(Path('/Users/daizo/Projects')/p.name).read_bytes(),p.name
 # Frozen host mapping and embedded PWA: no rebuilt Runtime allowed.
 runtime=Path('/Users/daizo/Projects/MegaVGMPlayer_vNext_4Engine_Runtime')
 source=runtime/'tools/megavgm_profile/profile.cpp';snapshot=ROOT/'audit/runtime-profile.cpp';assert source.read_bytes()==snapshot.read_bytes()
 for e in m['engines']:assert ('MegaVGMDrive_'+e+'.rbf')in source.read_text()
 publicroot=Path('/Users/daizo/Projects/MegaVGMPlayer_vNext_4Engine_RC');pwa=publicroot/old['embedded_pwa']['path'];assert sha(pwa)==old['embedded_pwa']['sha256'];remote=next(x for x in old['payloads']if x['destination'].endswith('/megavgm_remote'));assert pwa.read_bytes()in (Path('/Users/daizo/Projects')/remote['source']).read_bytes()
 return {'gate':'V240_IDENTITY_AND_EVIDENCE_PASS','engines':counts,'RBFs_exact':4,'canonical_runtime_names':4,'Common_files_exact_ABD':10,'Windows_inputs_exact':488,'Windows_RBFs_exact':3,'A_B_D_constrained_timing':'PASS_REUSED_WINDOWS_EVIDENCE','C':'UNCHANGED_LEGACY','protected_repositories':len(guard['repositories']),'protected_files':len(guard['files']),'Runtime_PWA_payload_changes':0,'new_Quartus_build':False,'new_hardware_test':False,'deployment':False,'publication':False}
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--allow-staged-canonical',action='store_true');a=p.parse_args();print(json.dumps(verify(a.allow_staged_canonical),indent=2))
