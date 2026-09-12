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
ITEMS = [
 ('_Custom Cores/Cores/MegaVGMDrive_A.rbf', V2 / '_Custom Cores/Cores/MegaVGMPlayer_Transport13FadeOnly_A_MiSTer.rbf', '5755b74d9b1e10e1da1d6c101892bc95ca8960851a851cc9076d1861c9571f1e', 'byte-identical v2.1 Engine A; QSF 67d7fa2922114852d315536daac79f83a0c40f1b; functional 4488ac0a518f3713cc5b38364aa226e5eded0e27'),
 ('_Custom Cores/Cores/MegaVGMDrive_B.rbf', V2 / '_Custom Cores/Cores/MegaVGMPlayer_Transport13FadeOnly_B_MiSTer.rbf', 'b435417f268a81a39af6bf2408f364945d151e391425775ab7d01ed4899bec95', 'byte-identical v2.1 Engine B; c59009f320f2e1d8db9e3582ee04a61ed18d47a3'),
 ('_Custom Cores/Cores/MegaVGMDrive_C.rbf', PROJECTS / 'MegaVGMPlayer_EngineC_PackedV2_Validation_MiSTer.rbf', '0f205de6ab30e86477fdf1b0797e82158cc5b14fdfa37e7011f3c94cbb72c479', 'exact Packed v2 hardware-validation RBF; RTL 53291cd59a64dee7c3c4edb5a2f0f0a8e69c99db; QPF hw/engine_c_packed_v2/MegaVGMPlayer_EngineC_PackedV2_Validation_MiSTer.qpf; CORENAME MegaVGMDrive'),
 ('MegaVGMPlayer/MiSTer.megavgm', V2 / 'MegaVGMPlayer/MiSTer.megavgm', 'a0e7b7d3557457a80ecd62a6bb4643585c33b78fbe515a7a7a5783b05b5addb5', 'a409745a00ca428999e909edb69646f1a5fc62d4; existing v2.0 Main, dynamically linked by design'),
 ('MegaVGMPlayer/megavgm_supervisor', HOST / 'megavgm-c5-supervisor-arm/megavgm_supervisor', '8e4c22b97215451accce369f4c81353e467674a8e23c04ff5fb68fa8900b4d75', 'aa3e2bab7606084063845275797f8380e45dc259; static ARM; production-default PROFILE_A/B/C exact paths'),
 ('MegaVGMPlayer/megavgm_playlist-phase2a', HOST / 'megavgm-c5-controller-arm/megavgm_playlist', '76f8ac60faae7d0bbdf79fa8dc5c4899ed33c3e6ef02aa82902907c865171df1', '823881ab69d6074ffa991bfc98e9662d9ebf2b88; static ARM; strict MVGMSID v1/v2 PROFILE_C classifier'),
 ('Scripts/vgm_md_import.sh', V2 / 'Scripts/vgm_md_import.sh', '700542daaeac0f59998d23a868073e6c6c165a4c350fc1119de28456f5f59103', 'e01c872d6854edce77c1fbc7a8f68239f8ecf045; unchanged importer'),
 ('MegaVGMPlayer/megavgm_remote', HOST / 'megavgm_remote-c5', '8e23be45da2069e8b1c29bbad8ce14d004d3653970cbc13eebe21d4647ebd02d', '8af356aa58eda6d78953d64e614f66288d4570c1; static ARM; prepared SID browse/status support; embedded assets/megavgm-203c7846.js'),
 ('Scripts/megavgm_ctl', P1 / 'megavgm_ctl.production', '378905c80c22f0b072e248d6fdb67238f2727a38287f4407b2596c8c2a9ae45b', '9e2dd45fbd986378bbdaba326d8e722df2b89c27; exact five compile inputs, official GCC 10.2 static stripped + GNU OSABI'),
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
    manifest = ['# MegaVGMPlayer v2.2 — Engine C C5 production candidate', '',
      'Packed MVGMSID v2 Engine C is integrated into the existing production A/B/C switching contract. SID RTL/audio, transport, OSD, and A/B classifier decisions are unchanged.',
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
      'Legacy v2.1 RBF names and files are never deleted. Rollback restores the prior Supervisor/controller and retains introduced files recoverably.',
      'Embedded entry: assets/megavgm-203c7846.js; SHA-256 c2161ae3187307cd1024e3034227cf94365913517dea92f49b4f985355e12bff.',
      'Frozen Phase 1 and C5 integration provenance is retained under provenance/.', '']
    (out/'ARTIFACT_MANIFEST.md').write_text('\n'.join(manifest))
    for name in ('install.sh','upgrade.sh','rollback.sh','common.sh','startup.block','README.md','README.ja.md','RELEASE_NOTES.md','HARDWARE_CHECKLIST.md','VALIDATION.md'):
        shutil.copy2(ROOT/'release'/name, out/name)
        if name.endswith('.sh'): (out/name).chmod(0o755)
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
