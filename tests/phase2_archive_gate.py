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
assert len([p for p in (package/'media/fat').rglob('*') if p.is_file()])==10
preparer=package/'media/fat/MegaVGMPlayer/megavgm_sid_prepare'
assert hashlib.sha256(preparer.read_bytes()).hexdigest()=='d3213f73cdb9926759f728b06c29f98cf2d8231b7ed0ee838204fa8d523b8661'
source=package/'source/megavgm_sid_prepare'
assert hashlib.sha256((source/'libsidplayfp-3.1.1.tar.gz').read_bytes()).hexdigest()=='12b79190593bf480b2d11481b5c2de62bac07f344437a66cd8d887329875c626'
assert (source/'COPYING').is_file()
assert (source/'patches/libsidplayfp-3.1.1-write-observer.patch').is_file()
assert (source/'native/megavgm_sid_prepare.cpp').is_file()
assert (source/'native/test_packed_v2_capacity.cpp').is_file()
expected = {
    'MegaVGMDrive_A.rbf': '5755b74d9b1e10e1da1d6c101892bc95ca8960851a851cc9076d1861c9571f1e',
    'MegaVGMDrive_B.rbf': 'b435417f268a81a39af6bf2408f364945d151e391425775ab7d01ed4899bec95',
    'MegaVGMDrive_C.rbf': 'efb29a236cb5858d00d462bb049ad9d65d8dea55c7b7bb50afc3434a8967a633',
}
for name, sha in expected.items():
    data=(package/'media/fat/_Custom Cores/Cores'/name).read_bytes()
    assert hashlib.sha256(data).hexdigest()==sha,name
runtime_expected = {
    'megavgm_playlist-phase2a': '87713696860a1dc57514cf9d82a18a66eefee14356bd34ca4fac6f58086f9ceb',
    'megavgm_supervisor': '201119a748b039b2110f27a5293faf4a6c1684df2b8c1bb7da9a7eccb6097740',
    'megavgm_sid_prepare': 'd3213f73cdb9926759f728b06c29f98cf2d8231b7ed0ee838204fa8d523b8661',
}
for name, expected_sha in runtime_expected.items():
    data=(package/'media/fat/MegaVGMPlayer'/name).read_bytes()
    assert hashlib.sha256(data).hexdigest()==expected_sha,name
print('ZIP/internal SHA256SUMS/payload exclusions/canonical paths PASS',digest)
print('EXTRACTED_PACKAGE',package)
