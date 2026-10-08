#!/usr/bin/env python3
"""Assemble an isolated v2.4.0 RC from pinned bytes. Never deploy/build/tag/push."""
from pathlib import Path
import argparse,hashlib,json,shutil,zipfile,stat
ROOT=Path(__file__).resolve().parents[1]
BASE_SHA='b33397b2868a11ea83a99614d003429bcde7dfa70a2dcdb6ef712e7fcc34c61b'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def unzip(z,d):
 names=z.namelist();assert len(names)==len(set(names))
 for n in names:assert not n.startswith('/') and '..' not in Path(n).parts and not stat.S_ISLNK(z.getinfo(n).external_attr>>16),n
 z.extractall(d)
 for n in names:
  p=d/n
  if p.is_file():p.chmod((z.getinfo(n).external_attr>>16)&0o777 or 0o644)
def sums(root):
 (root/'SHA256SUMS').write_text(''.join(sha(p)+'  '+p.relative_to(root).as_posix()+'\n' for p in sorted(root.rglob('*'))if p.is_file()and p!=root/'SHA256SUMS'))
def verify(package):
 records=json.loads((package/'provenance/final_authorities.json').read_text())
 assert records['package_version']=='2.4.0' and records['status']=='RC_READY_NOT_DEPLOYED'
 rels=set()
 for x in records['payloads']:
  p=package/'media/fat'/x['destination'];assert p.stat().st_size==x['bytes']and sha(p)==x['sha256'];assert p.stat().st_mode&0o777==int(x['mode'],8);rels.add(x['destination'])
 assert len(rels)==12 and rels=={p.relative_to(package/'media/fat').as_posix()for p in (package/'media/fat').rglob('*')if p.is_file()}
 checked=set()
 for l in (package/'SHA256SUMS').read_text().splitlines():
  h,n=l.split('  ',1);assert n not in checked and not n.startswith('/')and '..'not in Path(n).parts;assert sha(package/n)==h;checked.add(n)
 assert checked=={p.relative_to(package).as_posix()for p in package.rglob('*')if p.is_file()and p!=package/'SHA256SUMS'}
 return {'package_files':len(checked)+1,'payloads':12,'checksum_members':len(checked),'status':'PASS'}
def archive(package,path):
 assert not path.exists()
 with zipfile.ZipFile(path,'w',zipfile.ZIP_DEFLATED,compresslevel=9)as z:
  for p in sorted(package.rglob('*')):
   if not p.is_file():continue
   n=package.name+'/'+p.relative_to(package).as_posix();i=zipfile.ZipInfo(n,(2026,10,9,0,0,0));i.create_system=3;i.external_attr=(0o100000|(p.stat().st_mode&0o777))<<16;z.writestr(i,p.read_bytes(),compress_type=zipfile.ZIP_DEFLATED,compresslevel=9)
 (path.with_suffix('.zip.sha256')).write_text(sha(path)+'  '+path.name+'\n')
def build(base,out,integration_commit=None):
 assert sha(base)==BASE_SHA;assert not out.exists(),'refusing overwrite';out.mkdir(parents=True)
 with zipfile.ZipFile(base)as z:unzip(z,out)
 package=out/'MegaVGMPlayer-v2.3';assert package.is_dir();package.rename(out/'MegaVGMPlayer-v2.4.0');package=out/'MegaVGMPlayer-v2.4.0'
 # Verify predecessor before any replacement.
 for l in (package/'SHA256SUMS').read_text().splitlines():h,n=l.split('  ',1);assert sha(package/n)==h
 adoption=json.loads((ROOT/'release/v2.4.0/adoption-manifest.json').read_text());assert adoption['status']=='RC_READY'
 old=json.loads((ROOT/'release/v2.4.0/v23-final-authorities.json').read_text());new=json.loads(json.dumps(old));new.update(package_version='2.4.0',status='RC_READY_NOT_DEPLOYED',hardware_acceptance='Scoped DAI receipts in adoption-manifest.json; no blanket all-track or long-duration guarantee')
 for e,v in adoption['engines'].items():
  rel='_Custom Cores/Cores/MegaVGMDrive_'+e+'.rbf';p=ROOT/v['RBF']['integrated_path'];assert sha(p)==v['RBF']['sha256'];shutil.copy2(p,package/'media/fat'/rel);(package/'media/fat'/rel).chmod(0o644)
  x=next(x for x in new['payloads']if x['destination']==rel)
  x.update(source=v['RBF']['integrated_path'],bytes=v['RBF']['bytes'],sha256=v['RBF']['sha256'],source_head=v['source_commit'],worktree=v['source_worktree'],mode='0644')
  if e=='B':x['implementation_head']=v['implementation_commit'];x['fitter_seed']=3
  source=v['source_artifact'].get('integrated_path') or v['legacy_source_snapshot']['path'];t=package/'source/engines'/e/Path(source).name;t.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/source,t)
 # Only packaging namespace changes; service/startup/transaction algorithms remain exact.
 for n in ['install.sh','rollback.sh']:
  p=package/n;p.write_text(p.read_text().replace('backups-v2.3-','backups-v2.4.0-').replace('.v23-','.v240-'));p.chmod(0o755)
 for n in ['README.md','README.ja.md','RELEASE_NOTES.md','BUILD.md','KNOWN_LIMITATIONS.md','TIMING.md','HARDWARE_ACCEPTANCE.md','ARTIFACT_MANIFEST.md']:
  shutil.copy2(ROOT/'release/v2.4.0'/n,package/n)
 for n in ['adoption-manifest.json','final_authorities.json']:
  target=package/'provenance'/n
  if n=='final_authorities.json':target.write_text(json.dumps(new,indent=2,ensure_ascii=False)+'\n')
  else:shutil.copy2(ROOT/'release/v2.4.0'/n,target)
 (package/'provenance/PROVENANCE.md').write_text('# v2.4.0 Architecture Refresh RC provenance\n\nA/B/D are selected immutable RBF copies; C and all eight non-engine payloads retain v2.3 bytes/modes. Exact source/config/seed/Artifact and scoped hardware evidence are in adoption-manifest.json. Original v2.3 ZIP SHA256: '+BASE_SHA+'. No compilation, hardware test, deployment, tag, push or publication occurs during assembly.\n\nsource/megavgm_sid_prepare and provenance/LICENSE.backend retain unchanged corresponding source/licenses. source/engines contains exact A/B/D Build Artifacts and unchanged legacy C source-closure snapshot. C is not represented as a newly migrated root-QPF project.\n')
 if integration_commit:
  assert len(integration_commit)==40 and all(c in '0123456789abcdef' for c in integration_commit)
  (package/'provenance/INTEGRATION_COMMIT.txt').write_text(integration_commit+'\n')
 sums(package);result=verify(package);path=out/'MegaVGMPlayer-v2.4.0.zip';archive(package,path)
 return package,path,result
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--base-v23',type=Path,required=True);p.add_argument('--out',type=Path,required=True);p.add_argument('--integration-commit');a=p.parse_args();package,path,result=build(a.base_v23,a.out,a.integration_commit);print(json.dumps(dict(result,ZIP=str(path),SHA256=sha(path)),indent=2))
