#!/usr/bin/env python3
"""Verify delivered archive, not just the original staging directory."""
import hashlib
from pathlib import Path
import tempfile
import sys
import zipfile

archive=Path(sys.argv[1]).resolve()
digest=hashlib.sha256(archive.read_bytes()).hexdigest()
assert archive.with_suffix('.zip.sha256').read_text().split()[0]==digest
root=Path(tempfile.mkdtemp(prefix='megavgm-v22-zip-'))
with zipfile.ZipFile(archive) as z:
    names=z.namelist()
    assert len(names)==len(set(names))
    assert all(not Path(n).is_absolute() and '..' not in Path(n).parts for n in names)
    assert not any(n.endswith('/remote.sh') or n.endswith('/playlists.json') for n in names)
    z.extractall(root)
package=root/'MegaVGMPlayer-v2.2'
listed=[]
for line in (package/'SHA256SUMS').read_text().splitlines():
    expected,rel=line.split('  ',1)
    assert hashlib.sha256((package/rel).read_bytes()).hexdigest()==expected,rel
    listed.append(rel)
actual=[str(p.relative_to(package)) for p in package.rglob('*') if p.is_file() and p.name!='SHA256SUMS']
assert sorted(listed)==sorted(actual)
rbfs=sorted(str(p.relative_to(package/'media/fat')) for p in (package/'media/fat').rglob('*.rbf'))
assert rbfs==['_Custom Cores/Cores/MegaVGMDrive_A.rbf',
              '_Custom Cores/Cores/MegaVGMDrive_B.rbf',
              '_Custom Cores/Cores/MegaVGMDrive_C.rbf']
assert len([p for p in (package/'media/fat').rglob('*') if p.is_file()])==9
expected = {
    'MegaVGMDrive_A.rbf': '5755b74d9b1e10e1da1d6c101892bc95ca8960851a851cc9076d1861c9571f1e',
    'MegaVGMDrive_B.rbf': 'b435417f268a81a39af6bf2408f364945d151e391425775ab7d01ed4899bec95',
    'MegaVGMDrive_C.rbf': '0f205de6ab30e86477fdf1b0797e82158cc5b14fdfa37e7011f3c94cbb72c479',
}
for name, sha in expected.items():
    data=(package/'media/fat/_Custom Cores/Cores'/name).read_bytes()
    assert hashlib.sha256(data).hexdigest()==sha,name
print('ZIP/internal SHA256SUMS/payload exclusions/canonical paths PASS',digest)
print('EXTRACTED_PACKAGE',package)
