#!/usr/bin/env python3
"""Fresh-extract and verify the frozen v2.4 RC; no build/install/deploy."""
from pathlib import Path
import argparse,json,tempfile,zipfile
from build_v240 import verify,unzip,sha,ROOT

def check(archive):
 with tempfile.TemporaryDirectory(prefix='megavgm-v240-fresh-')as t:
  with zipfile.ZipFile(archive)as z:unzip(z,Path(t))
  root=Path(t)/'MegaVGMPlayer-v2.4.0';result=verify(root)
  adoption=json.loads((ROOT/'release/v2.4.0/adoption-manifest.json').read_text())
  for e,v in adoption['engines'].items():assert sha(root/'media/fat/_Custom Cores/Cores'/('MegaVGMDrive_'+e+'.rbf'))==v['RBF']['sha256']
  old=json.loads((ROOT/'release/v2.4.0/v23-final-authorities.json').read_text())
  retained=[x for x in old['payloads']if not x['destination'].endswith(('_A.rbf','_B.rbf','_D.rbf'))]
  for x in retained:assert sha(root/'media/fat'/x['destination'])==x['sha256']
  for e,v in adoption['engines'].items():
   source=v['source_artifact'].get('integrated_path')or v['legacy_source_snapshot']['path']
   assert sha(root/'source/engines'/e/Path(source).name)==sha(ROOT/source)
  return dict(result,gate='V240_FRESH_EXTRACT_PASS',retained_v23_payloads=len(retained),exact_source_archives=4,ZIP_SHA256=sha(archive))
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('ZIP',type=Path);a=p.parse_args();print(json.dumps(check(a.ZIP),indent=2))
