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
package=root/'MegaVGMPlayer-v2.2-SwitchLatency-Hardware-Candidate'
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
assert len([p for p in (package/'media/fat').rglob('*') if p.is_file()])==12
preparer=package/'media/fat/MegaVGMPlayer/megavgm_sid_prepare'
assert hashlib.sha256(preparer.read_bytes()).hexdigest()=='4c640b2c5946e4b541cfdae11d298ec9d3e5a01c9fa840dae9dab5afe4da3f0f'
assert b'247d0f198d52ca7789a845a878679c87b2f7e7dc' in preparer.read_bytes()
assert b'81fa235b7f6ef180b6c6392a042502952e72252e' not in preparer.read_bytes()
source=package/'source/megavgm_sid_prepare'
assert hashlib.sha256((source/'libsidplayfp-3.1.1.tar.gz').read_bytes()).hexdigest()=='12b79190593bf480b2d11481b5c2de62bac07f344437a66cd8d887329875c626'
assert (source/'COPYING').is_file()
assert (source/'patches/libsidplayfp-3.1.1-write-observer.patch').is_file()
assert (source/'native/megavgm_sid_prepare.cpp').is_file()
assert (source/'native/test_packed_v2_capacity.cpp').is_file()
assert (source/'generate_hardware_fixture.py').is_file()
assert (source/'production_build_arm.sh').is_file()
expected = {
    'MegaVGMDrive_A.rbf': '5755b74d9b1e10e1da1d6c101892bc95ca8960851a851cc9076d1861c9571f1e',
    'MegaVGMDrive_B.rbf': 'b435417f268a81a39af6bf2408f364945d151e391425775ab7d01ed4899bec95',
    'MegaVGMDrive_C.rbf': 'd6d7bb22beed1366be41b34ab12699cbc3174c46f00705c8f36cd16fd1510dc5',
}
for name, sha in expected.items():
    data=(package/'media/fat/_Custom Cores/Cores'/name).read_bytes()
    assert hashlib.sha256(data).hexdigest()==sha,name
runtime_expected = {
    'megavgm_playlist-phase2a': '6e1b11f1b84cac228459ace91fb69f27469024d74062f28007e1edb6af9c221c',
    'megavgm_supervisor': 'c83caf59e9685e4bbb777c2f225c90c2bf591a627f1431dffd00e7ef01aadc0e',
    'megavgm_sid_prepare': '4c640b2c5946e4b541cfdae11d298ec9d3e5a01c9fa840dae9dab5afe4da3f0f',
}
for name, expected_sha in runtime_expected.items():
    data=(package/'media/fat/MegaVGMPlayer'/name).read_bytes()
    assert hashlib.sha256(data).hexdigest()==expected_sha,name
assert hashlib.sha256((package/'media/fat/MegaVGMPlayer/MiSTer.megavgm').read_bytes()).hexdigest()=='b691d783a26a9ab94a338433e4f43cf69237cc3a1f7e19bdd3f753f906dc0742'
fixture=package/'media/fat/MegaVGMDrive/C7_2_Hardware_Test/C7_2_Manual_Loop_PAL_6581.sid'
sidecar=fixture.with_name(fixture.name+'.loop.json')
assert hashlib.sha256(fixture.read_bytes()).hexdigest()=='424c07eb9c5aa6878958c431595d0c87a37ea68ece365ea5c5955097550e3f4f'
assert hashlib.sha256(sidecar.read_bytes()).hexdigest()=='eb71bea2428c01ffd94480674a58ae6edb622b424f893d5c4b3b64895ee093c7'
prepared=package/'validation/manual-loop-fixture/C7_2_Manual_Loop_PAL_6581.mvgmsid'
prepared_json=package/'validation/manual-loop-fixture/C7_2_Manual_Loop_PAL_6581.provenance.json'
assert hashlib.sha256(prepared.read_bytes()).hexdigest()=='f348221bfdafe1fa4ec73e5bf3e299a1d977a6e6c9493fc5cf18cb1dfcc9ec19'
assert hashlib.sha256(prepared_json.read_bytes()).hexdigest()=='2140697043aa156318062f379fb58cabbc072956da5d35b89fc2150898dc7b81'
print('ZIP/internal SHA256SUMS/payload exclusions/canonical paths PASS',digest)
print('EXTRACTED_PACKAGE',package)
