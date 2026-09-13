#!/usr/bin/env python3
"""Package frozen artifacts only. No builds, downloads, or hardware writes."""
import hashlib
from pathlib import Path
import shutil
import sys
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]
PROJECTS = ROOT.parent
V2 = PROJECTS / 'MegaVGMPlayer_v2_Release_Final_Staging/MegaVGMPlayer-v2.0/media/fat'
P1 = PROJECTS / 'MegaVGMPlayer_Standalone_Phase1/artifacts'
HOST = ROOT / 'artifacts'
TOOLING = PROJECTS / 'MegaVGMPlayer_EngineC_PhaseC6/tools/engine_c_c6'
ITEMS = [
 ('_Custom Cores/Cores/MegaVGMDrive_A.rbf', V2 / '_Custom Cores/Cores/MegaVGMPlayer_Transport13FadeOnly_A_MiSTer.rbf', '5755b74d9b1e10e1da1d6c101892bc95ca8960851a851cc9076d1861c9571f1e', 'byte-identical v2.1 Engine A; QSF 67d7fa2922114852d315536daac79f83a0c40f1b; functional 4488ac0a518f3713cc5b38364aa226e5eded0e27'),
 ('_Custom Cores/Cores/MegaVGMDrive_B.rbf', V2 / '_Custom Cores/Cores/MegaVGMPlayer_Transport13FadeOnly_B_MiSTer.rbf', 'b435417f268a81a39af6bf2408f364945d151e391425775ab7d01ed4899bec95', 'byte-identical v2.1 Engine B; c59009f320f2e1d8db9e3582ee04a61ed18d47a3'),
 ('_Custom Cores/Cores/MegaVGMDrive_C.rbf', PROJECTS / 'MegaVGMPlayer_EngineC_PackedV2_Validation_MiSTer.rbf', '0f205de6ab30e86477fdf1b0797e82158cc5b14fdfa37e7011f3c94cbb72c479', 'exact Packed v2 hardware-validation RBF; RTL 53291cd59a64dee7c3c4edb5a2f0f0a8e69c99db; QPF hw/engine_c_packed_v2/MegaVGMPlayer_EngineC_PackedV2_Validation_MiSTer.qpf; CORENAME MegaVGMDrive'),
 ('MegaVGMPlayer/MiSTer.megavgm', V2 / 'MegaVGMPlayer/MiSTer.megavgm', 'a0e7b7d3557457a80ecd62a6bb4643585c33b78fbe515a7a7a5783b05b5addb5', 'a409745a00ca428999e909edb69646f1a5fc62d4; existing v2.0 Main, dynamically linked by design'),
 ('MegaVGMPlayer/megavgm_supervisor', HOST / 'megavgm-c6-sid-member-arm-48f61a2-exact/megavgm_supervisor', '0e6ecabf5403ba7029129c8b3f9837223a9b30f60a28954fb2e3fad5d50692ac', '48f61a29bfb2c12eb63920914ee815bb3978f697; static ARM; C6 production default plus exact .vgm/.mvgmsid/.sid direct-member prerequisite admission'),
 ('MegaVGMPlayer/megavgm_playlist-phase2a', HOST / 'megavgm-c6-watchdog-ae16cc3-arm/megavgm_playlist', '2744748c79e0469360569df5835c1494f26bc508e15d324482b31dfac85c7613', 'ae16cc33cb69eace9b875bb33dff9d673801bf2c; 120-second cold SID prepare watchdog; generation invalidation plus bounded cancel/reap and exact child-PID cache-temp cleanup'),
 ('MegaVGMPlayer/megavgm_sid_prepare', HOST / 'megavgm_sid_prepare', '4dbb5cd5d918c14fab9f25783f7e2d0c7acbbcf84086cc9abc04e017cde5f87b', 'ff6904fbaf22ea2d4db2a487e14c7e9cf5a7a914; static ARM; atomic Packed MVGMSID v2 pair publication with parent-directory fsync'),
 ('Scripts/vgm_md_import.sh', V2 / 'Scripts/vgm_md_import.sh', '700542daaeac0f59998d23a868073e6c6c165a4c350fc1119de28456f5f59103', 'e01c872d6854edce77c1fbc7a8f68239f8ecf045; unchanged importer'),
 ('MegaVGMPlayer/megavgm_remote', HOST / 'megavgm_remote-c6-loading-reconcile-9f13f04', '4f8a6762441291ccc6bc0c8ce395937197b5a27a7aca06698de15e967f2a05bb', '9f13f04d0117036809fa06c756540e92df8bfd50; static ARM; exact PLAYING/STOPPED playlist warm admission plus authoritative switch-generation Loading reconciliation; embedded assets/megavgm-f6c226d2.js'),
 ('Scripts/megavgm_ctl', P1 / 'megavgm_ctl.production', '378905c80c22f0b072e248d6fdb67238f2727a38287f4407b2596c8c2a9ae45b', '9e2dd45fbd986378bbdaba326d8e722df2b89c27; exact five compile inputs, official GCC 10.2 static stripped + GNU OSABI'),
]
SOURCE_ITEMS = [
 ('README.md', TOOLING / 'README.md'),
 ('COPYING', HOST / 'COPYING.libsidplayfp'),
 ('libsidplayfp-3.1.1.tar.gz', HOST / 'libsidplayfp-3.1.1.tar.gz'),
 ('dependencies.lock.json', TOOLING / 'dependencies.lock.json'),
 ('build_arm.sh', TOOLING / 'build_arm.sh'),
 ('build_native.sh', TOOLING / 'build_native.sh'),
 ('test_prepare.py', TOOLING / 'test_prepare.py'),
 ('patches/libsidplayfp-3.1.1-write-observer.patch', TOOLING / 'patches/libsidplayfp-3.1.1-write-observer.patch'),
 ('native/megavgm_sid_prepare.cpp', TOOLING / 'native/megavgm_sid_prepare.cpp'),
 ('native/packed_v2.cpp', TOOLING / 'native/packed_v2.cpp'),
 ('native/packed_v2.h', TOOLING / 'native/packed_v2.h'),
 ('native/sha256.cpp', TOOLING / 'native/sha256.cpp'),
 ('native/sha256.h', TOOLING / 'native/sha256.h'),
]
def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    out = Path(sys.argv[1]).resolve()
    if out.exists():
        raise SystemExit('Refusing to overwrite existing staging: '+str(out))
    sources = ITEMS
    for rel, source, expected, _ in sources:
        assert sha(source) == expected, (source, 'frozen SHA mismatch')
    out.mkdir(parents=True)
    manifest = ['# MegaVGMPlayer v2.2 — Engine C C6 production candidate', '',
      'Raw single-SID files are prepared on demand into Packed MVGMSID v2 before entering the unchanged production A/B/C switching contract. SID RTL/audio, transport, OSD, and A/B classifier decisions are unchanged.',
      'Packaging source commit: `'+subprocess.check_output(['git','-C',str(ROOT),'rev-parse','HEAD'],text=True).strip()+'`.',
      'Engine A/B are byte-identical copies of the v2.1 hardware-PASS RBFs. Engine C is the exact user-confirmed Packed v2 hardware-validation RBF and is production-routed as PROFILE_C.', '',
      '| Runtime relative to /media/fat | Bytes | SHA-256 | Source / provenance |',
      '|---|---:|---|---|']
    for rel, source, expected, provenance in sources:
        dst = out/'media/fat'/rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, dst)
        dst.chmod(0o644 if rel.endswith('.rbf') else 0o755)
        assert sha(dst) == expected
        manifest.append(f'| `{rel}` | {dst.stat().st_size} | `{expected}` | {provenance} |')
    manifest += ['', '## Exact original local sources', '']
    manifest += [f'- `{source}`' for _, source, _, _ in sources]
    manifest += ['', '## Exclusions', '',
      '`Scripts/remote.sh`, playlist JSON, the VGM library, and user-startup.sh are not payloads.',
      'The installer appends only startup.block; it does not deploy a replacement startup file.',
      'Install COMPLETE is published only after every deployed payload SHA matches the package and the restarted /tmp/megavgm_remote process matches the packaged Remote SHA and exact executable path.',
      'Legacy v2.1 RBF names and files are never deleted. Rollback restores the prior Supervisor/controller and retains introduced files recoverably.',
      'Embedded entry: assets/megavgm-f6c226d2.js; SHA-256 6f7aed749a58c8ae87e7f231e6d12bff11d86f6581b20b637d89c3b42b93bba1.',
      'The GPL-linked SID preparer corresponding source is included under source/megavgm_sid_prepare/.',
      'Frozen Phase 1/C5 provenance plus C6 provenance is retained under provenance/.', '']
    (out/'ARTIFACT_MANIFEST.md').write_text('\n'.join(manifest))
    for name in ('install.sh','upgrade.sh','rollback.sh','common.sh','startup.block','README.md','README.ja.md','RELEASE_NOTES.md','HARDWARE_CHECKLIST.md','VALIDATION.md'):
        shutil.copy2(ROOT/'release'/name, out/name)
        if name.endswith('.sh'): (out/name).chmod(0o755)
    source_root = out/'source/megavgm_sid_prepare'
    for rel, source in SOURCE_ITEMS:
        dst = source_root/rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, dst)
        if rel.endswith('.sh'): dst.chmod(0o755)
    (out/'provenance').mkdir()
    shutil.copy2(ROOT/'PROVENANCE.md', out/'provenance/PROVENANCE.md')
    shutil.copy2(ROOT/'LICENSE.backend', out/'provenance/LICENSE.backend')
    files = sorted(p for p in out.rglob('*') if p.is_file())
    (out/'SHA256SUMS').write_text(''.join(f'{sha(p)}  {p.relative_to(out)}\n' for p in files))
    archive = out.parent/(out.name+'.zip')
    assert not archive.exists(), archive
    with zipfile.ZipFile(archive, 'x', zipfile.ZIP_DEFLATED) as z:
        for p in sorted(out.rglob('*')):
            if p.is_file(): z.write(p, str(p.relative_to(out.parent)))
    archive.with_suffix('.zip.sha256').write_text(f'{sha(archive)}  {archive.name}\n')
    print(archive, archive.stat().st_size, sha(archive))

if __name__ == '__main__': main()
