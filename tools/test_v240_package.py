#!/usr/bin/env python3
"""Metadata-only RC regression, isolated temporary FAT; never runs target ARM binaries."""
from pathlib import Path
import argparse,json,os,shutil,subprocess,tempfile,zipfile
from build_v240 import verify,sha,unzip
from verify_artifact_identity import check

def test(archive,base):
 result=check(archive)
 with tempfile.TemporaryDirectory(prefix='megavgm-v240-tests-')as t:
  t=Path(t).resolve()
  with zipfile.ZipFile(archive)as z:unzip(z,t/'new')
  with zipfile.ZipFile(base)as z:unzip(z,t/'old')
  new=t/'new/MegaVGMPlayer-v2.4.0';old=t/'old/MegaVGMPlayer-v2.3'
  changes=[]
  for p in (old/'media/fat').rglob('*'):
   if p.is_file()and sha(p)!=sha(new/'media/fat'/p.relative_to(old/'media/fat')):changes.append(p.relative_to(old/'media/fat').as_posix())
  assert sorted(changes)==['_Custom Cores/Cores/MegaVGMDrive_'+e+'.rbf'for e in 'ABD']
  for n in ['common.sh','upgrade.sh','startup.block']:
   assert (new/n).read_bytes()==(old/n).read_bytes()
  for n in ['install.sh','rollback.sh']:
   assert (new/n).read_text()==(old/n).read_text().replace('backups-v2.3-','backups-v2.4.0-').replace('.v23-','.v240-')
  for p in (old/'source/megavgm_sid_prepare').rglob('*'):
   if p.is_file():assert (new/'source/megavgm_sid_prepare'/p.relative_to(old/'source/megavgm_sid_prepare')).read_bytes()==p.read_bytes()
  for n in ['install.sh','upgrade.sh','rollback.sh','common.sh']:
   subprocess.run(['sh','-n',str(new/n)],check=True)
  # Reject corruption, missing checksum coverage, payload mode and missing payload.
  victim=new/'media/fat/_Custom Cores/Cores/MegaVGMDrive_A.rbf';data=victim.read_bytes();mode=victim.stat().st_mode&0o777
  rejected=[]
  def reject(name):
   try:verify(new)
   except (AssertionError,OSError,KeyError,ValueError):rejected.append(name);return
   raise AssertionError('negative control accepted: '+name)
  victim.write_bytes(data+b'corrupt');reject('RBF corruption');victim.write_bytes(data)
  sums=new/'SHA256SUMS';saved=sums.read_bytes();sums.write_bytes(b'\n'.join(saved.splitlines()[1:])+b'\n');reject('missing checksum coverage');sums.write_bytes(saved)
  victim.chmod(0o755);reject('wrong payload mode');victim.chmod(mode)
  victim.unlink();reject('missing payload');victim.write_bytes(data);victim.chmod(mode);verify(new)
  # v2.3 -> v2.4 upgrade, idempotent rerun and rollback in temporary directories only.
  fat=t/'isolated-fat';shutil.copytree(old/'media/fat',fat,copy_function=shutil.copy2)
  startup=fat/'linux/user-startup.sh';startup.parent.mkdir(exist_ok=True);startup.write_text('#!/bin/sh\n# preserved user startup\n\n'+(old/'startup.block').read_text());startup.chmod(0o755)
  users={fat/'MegaVGMPlayer/playlists.json':b'{"preserve":true}\n',fat/'MegaVGMPlayer/remote.sh':b'# preserved user remote\n',fat/'MegaVGMPlayer/music/user.vgm':b'user music'}
  for p,b in users.items():p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(b)
  before={p.relative_to(fat).as_posix():(sha(p),p.stat().st_mode&0o777)for p in fat.rglob('*')if p.is_file()}
  env=os.environ.copy();env.update(MEGAVGM_FAT_ROOT=str(fat),MEGAVGM_INSTALL_OFFLINE='1',MEGAVGM_INSTALL_SERVICE_TEST='0')
  logs=[]
  for script in ['upgrade.sh','install.sh']:
   x=subprocess.run(['sh',str(new/script)],env=env,capture_output=True,text=True);logs.append(x.stdout+x.stderr);assert x.returncode==0,logs[-1]
  backups=list((fat/'MegaVGMPlayer').glob('backups-v2.4.0-*'));assert len(backups)==1
  assert 'Already installed and verified' in logs[-1]
  for x in json.loads((new/'provenance/final_authorities.json').read_text())['payloads']:assert sha(fat/x['destination'])==x['sha256']
  x=subprocess.run(['sh',str(new/'rollback.sh')],env=env,capture_output=True,text=True);logs.append(x.stdout+x.stderr);assert x.returncode==0,logs[-1]
  for rel,(h,m)in before.items():assert sha(fat/rel)==h and (fat/rel).stat().st_mode&0o777==m,rel
  for p,b in users.items():assert p.read_bytes()==b
 return dict(result,changed_payloads=changes,installer_changes='VERSIONED_BACKUP_NAMESPACE_ONLY',SID_source_unchanged=True,negative_controls=rejected,isolated_upgrade_idempotence_rollback='PASS',user_files_preserved=True,service_ARM_execution=False,hardware_lifecycle_test=False)
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('ZIP',type=Path);p.add_argument('--base-v23',type=Path,required=True);a=p.parse_args();print(json.dumps(test(a.ZIP,a.base_v23),indent=2))
