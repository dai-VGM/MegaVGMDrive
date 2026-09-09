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
root=Path(tempfile.mkdtemp(prefix='megavgm-v21-zip-'))
with zipfile.ZipFile(archive) as z:
    names=z.namelist()
    assert len(names)==len(set(names))
    assert all(not Path(n).is_absolute() and '..' not in Path(n).parts for n in names)
    assert not any(n.endswith('/remote.sh') or n.endswith('/playlists.json') for n in names)
    z.extractall(root)
package=root/'MegaVGMPlayer-v2.1'
listed=[]
for line in (package/'SHA256SUMS').read_text().splitlines():
    expected,rel=line.split('  ',1)
    assert hashlib.sha256((package/rel).read_bytes()).hexdigest()==expected,rel
    listed.append(rel)
actual=[str(p.relative_to(package)) for p in package.rglob('*') if p.is_file() and p.name!='SHA256SUMS']
assert sorted(listed)==sorted(actual)
rbfs=sorted(str(p.relative_to(package/'media/fat')) for p in (package/'media/fat').rglob('*.rbf'))
assert rbfs==['_Custom Cores/Cores/MegaVGMPlayer_Transport13FadeOnly_A_MiSTer.rbf',
              '_Custom Cores/Cores/MegaVGMPlayer_Transport13FadeOnly_B_MiSTer.rbf']
assert len([p for p in (package/'media/fat').rglob('*') if p.is_file()])==8
print('ZIP/internal SHA256SUMS/payload exclusions/canonical paths PASS',digest)
print('EXTRACTED_PACKAGE',package)
