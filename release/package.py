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
HOST = PROJECTS / 'MegaVGMPlayer_V22_EngineC_C6_Host/artifacts'
TOOLING = PROJECTS / 'MegaVGMPlayer_EngineC_PhaseC6/tools/engine_c_c6'
TOOLING_C7 = PROJECTS / 'MegaVGMPlayer_EngineC_PhaseC6/tools/engine_c_c7_2'
CANDIDATE = PROJECTS / 'MegaVGMPlayer_EngineC_C7_2_Hardware_Candidate'
OPTIMIZED = PROJECTS / 'MegaVGMPlayer_v2.2_SwitchLatency_Hardware_Candidate_Build/artifacts'
TOOLING_COMMIT = '247d0f198d52ca7789a845a878679c87b2f7e7dc'
MISSTAMPED_TOOLING_COMMIT = '81fa235b7f6ef180b6c6392a042502952e72252e'
ITEMS = [
 ('_Custom Cores/Cores/MegaVGMDrive_A.rbf', V2 / '_Custom Cores/Cores/MegaVGMPlayer_Transport13FadeOnly_A_MiSTer.rbf', '5755b74d9b1e10e1da1d6c101892bc95ca8960851a851cc9076d1861c9571f1e', 'byte-identical v2.1 Engine A; QSF 67d7fa2922114852d315536daac79f83a0c40f1b; functional 4488ac0a518f3713cc5b38364aa226e5eded0e27'),
 ('_Custom Cores/Cores/MegaVGMDrive_B.rbf', V2 / '_Custom Cores/Cores/MegaVGMPlayer_Transport13FadeOnly_B_MiSTer.rbf', 'b435417f268a81a39af6bf2408f364945d151e391425775ab7d01ed4899bec95', 'byte-identical v2.1 Engine B; c59009f320f2e1d8db9e3582ee04a61ed18d47a3'),
 ('_Custom Cores/Cores/MegaVGMDrive_C.rbf', PROJECTS / 'MegaVGMPlayer_EngineC_C7_2_Validation_MiSTer.rbf', 'd6d7bb22beed1366be41b34ab12699cbc3174c46f00705c8f36cd16fd1510dc5', 'C7.2 Windows Quartus Full Compilation from RTL 8e5f1111f8b0afdd6b75ae0011ba891ef344a87d; manual Packed-v2 loop replay; hardware validation pending'),
 ('MegaVGMPlayer/MiSTer.megavgm', OPTIMIZED / 'MiSTer.megavgm', 'b691d783a26a9ab94a338433e4f43cf69237cc3a1f7e19bdd3f753f906dc0742', '144ae51a2b289fc86f2e09131e3173be9f0e45e2; upload ProgressMessage publication throttled to a 100 ms monotonic interval; transfer/CRC/SPI semantics unchanged; dynamically linked by design'),
 ('MegaVGMPlayer/megavgm_supervisor', OPTIMIZED / 'megavgm_supervisor', 'c83caf59e9685e4bbb777c2f225c90c2bf591a627f1431dffd00e7ef01aadc0e', '1ba36ce10cdd41d48ca0194de26d08ce2eb89c5d integration of Phase 1 authority 70d2aefd121f975210be6b59886a8211bd7ec150 with the candidate Main SHA; 200 ms service cadence retained; rejected db7b0f084edc33fd0471fcfdd7ad84bb057a6573 absent'),
 ('MegaVGMPlayer/megavgm_playlist-phase2a', CANDIDATE / 'build-artifacts/megavgm_playlist-phase2a', '6e1b11f1b84cac228459ace91fb69f27469024d74062f28007e1edb6af9c221c', '1cffacda1feed2cb26e54f0d557565ca2f68203b; static ARM; existing playlist and transition contract unchanged'),
 ('MegaVGMPlayer/megavgm_sid_prepare', CANDIDATE / 'build-artifacts/megavgm_sid_prepare', '4c640b2c5946e4b541cfdae11d298ec9d3e5a01c9fa840dae9dab5afe4da3f0f', '247d0f198d52ca7789a845a878679c87b2f7e7dc; static ARM; strict manual-loop sidecar snap/canonicalization and 8 MiB policy'),
 ('Scripts/vgm_md_import.sh', V2 / 'Scripts/vgm_md_import.sh', '700542daaeac0f59998d23a868073e6c6c165a4c350fc1119de28456f5f59103', 'e01c872d6854edce77c1fbc7a8f68239f8ecf045; unchanged importer'),
 ('MegaVGMPlayer/megavgm_remote', HOST / 'megavgm_remote-c6-loading-reconcile-9f13f04', '4f8a6762441291ccc6bc0c8ce395937197b5a27a7aca06698de15e967f2a05bb', '9f13f04d0117036809fa06c756540e92df8bfd50; static ARM; exact PLAYING/STOPPED playlist warm admission plus authoritative switch-generation Loading reconciliation; embedded assets/megavgm-f6c226d2.js'),
 ('Scripts/megavgm_ctl', P1 / 'megavgm_ctl.production', '378905c80c22f0b072e248d6fdb67238f2727a38287f4407b2596c8c2a9ae45b', '9e2dd45fbd986378bbdaba326d8e722df2b89c27; exact five compile inputs, official GCC 10.2 static stripped + GNU OSABI'),
 ('MegaVGMDrive/C7_2_Hardware_Test/C7_2_Manual_Loop_PAL_6581.sid', CANDIDATE / 'fixtures/C7_2_Manual_Loop_PAL_6581.sid', '424c07eb9c5aa6878958c431595d0c87a37ea68ece365ea5c5955097550e3f4f', 'original PAL/6581 synthetic SID; one-second intro plus two-second manual loop'),
 ('MegaVGMDrive/C7_2_Hardware_Test/C7_2_Manual_Loop_PAL_6581.sid.loop.json', CANDIDATE / 'fixtures/C7_2_Manual_Loop_PAL_6581.sid.loop.json', 'eb71bea2428c01ffd94480674a58ae6edb622b424f893d5c4b3b64895ee093c7', 'strict MegaVGMPlayer-SID-loop-v1 sidecar bound to the synthetic source SHA/subtune'),
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
 ('native/test_packed_v2_capacity.cpp', TOOLING / 'native/test_packed_v2_capacity.cpp'),
 ('native/sha256.cpp', TOOLING / 'native/sha256.cpp'),
 ('native/sha256.h', TOOLING / 'native/sha256.h'),
 ('generate_hardware_fixture.py', TOOLING_C7 / 'generate_hardware_fixture.py'),
 ('production_build_arm.sh', ROOT / 'release/build_sid_preparer_arm.sh'),
]
VALIDATION_ITEMS = [
 ('C7_2_Manual_Loop_PAL_6581.mvgmsid', CANDIDATE / 'prepared-cache-final/05c08152edf3b1bd5e24a3d25d3e079d4acdc66480c51490991200c4a9a365fc.mvgmsid', 'f348221bfdafe1fa4ec73e5bf3e299a1d977a6e6c9493fc5cf18cb1dfcc9ec19'),
 ('C7_2_Manual_Loop_PAL_6581.provenance.json', CANDIDATE / 'prepared-cache-final/05c08152edf3b1bd5e24a3d25d3e079d4acdc66480c51490991200c4a9a365fc.json', '2140697043aa156318062f379fb58cabbc072956da5d35b89fc2150898dc7b81'),
]
def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    out = Path(sys.argv[1]).resolve()
    if out.exists():
        raise SystemExit('Refusing to overwrite existing staging: '+str(out))
    actual_tooling_commit = subprocess.check_output(
        ['git', '-C', str(TOOLING), 'rev-parse', '--verify', 'HEAD^{commit}'],
        text=True,
    ).strip()
    assert actual_tooling_commit == TOOLING_COMMIT, (
        actual_tooling_commit, 'tooling source commit mismatch')
    tooling_status = subprocess.check_output(
        ['git', '-C', str(TOOLING), 'status', '--porcelain=v1',
         '--untracked-files=normal'], text=True)
    assert not tooling_status, ('tooling source checkout is dirty', tooling_status)
    sources = ITEMS
    for rel, source, expected, _ in sources:
        assert sha(source) == expected, (source, 'frozen SHA mismatch')
    preparer_bytes = (CANDIDATE / 'build-artifacts/megavgm_sid_prepare').read_bytes()
    assert TOOLING_COMMIT.encode() in preparer_bytes, 'preparer source commit missing'
    assert MISSTAMPED_TOOLING_COMMIT.encode() not in preparer_bytes, (
        'preparer contains superseded source commit')
    out.mkdir(parents=True)
    manifest = ['# MegaVGMPlayer v2.2 — Switch-latency hardware validation candidate', '',
      '**LAB/HARDWARE CANDIDATE — NOT A PUBLIC OR FINAL v2.2 RC.**', '',
      'This unpublished candidate combines only Supervisor Phase 1 condition-based successor-Main verification and the Main 100 ms ProgressMessage publication throttle. The included C7.2 SID fixture continues to exercise the validated manual-loop lineage.',
      'Packaging source commit: `'+subprocess.check_output(['git','-C',str(ROOT),'rev-parse','HEAD'],text=True).strip()+'`.',
      'Engine A/B/C RBFs, Controller, SID preparer, Remote, Frontend, importer, and helper are unchanged. Engine C is the supplied C7.2 Windows Quartus Full Compilation. The combined Main/Supervisor candidate remains hardware-unverified.',
      'The rejected Supervisor Phase 2 commit `db7b0f084edc33fd0471fcfdd7ad84bb057a6573` is not an ancestor of this build; the production Supervisor service cadence remains 200 ms and stable-zero remains 1500 ms.', '',
      '| Runtime relative to /media/fat | Bytes | SHA-256 | Source / provenance |',
      '|---|---:|---|---|']
    for rel, source, expected, provenance in sources:
        dst = out/'media/fat'/rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, dst)
        dst.chmod(0o644 if rel.endswith(('.rbf', '.sid', '.json')) else 0o755)
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
      'C7.2 source authority, resolved fixture loop metadata, and hardware scope are retained under provenance/.', '']
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
    validation_root = out/'validation/manual-loop-fixture'
    validation_root.mkdir(parents=True)
    for rel, source, expected in VALIDATION_ITEMS:
        assert sha(source) == expected, (source, 'validation artifact SHA mismatch')
        shutil.copy2(source, validation_root/rel)
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
