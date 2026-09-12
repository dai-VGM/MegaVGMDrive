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
HOST = PROJECTS / 'MegaVGMPlayer_v22_RBF_Naming_Host_Artifacts'
ITEMS = [
 ('_Custom Cores/Cores/MegaVGMDrive_A.rbf', V2 / '_Custom Cores/Cores/MegaVGMPlayer_Transport13FadeOnly_A_MiSTer.rbf', '5755b74d9b1e10e1da1d6c101892bc95ca8960851a851cc9076d1861c9571f1e', 'byte-identical v2.1 Engine A; QSF 67d7fa2922114852d315536daac79f83a0c40f1b; functional 4488ac0a518f3713cc5b38364aa226e5eded0e27'),
 ('_Custom Cores/Cores/MegaVGMDrive_B.rbf', V2 / '_Custom Cores/Cores/MegaVGMPlayer_Transport13FadeOnly_B_MiSTer.rbf', 'b435417f268a81a39af6bf2408f364945d151e391425775ab7d01ed4899bec95', 'byte-identical v2.1 Engine B; c59009f320f2e1d8db9e3582ee04a61ed18d47a3'),
 ('_Custom Cores/Cores/MegaVGMDrive_C.rbf', PROJECTS / 'MegaVGMPlayer_EngineC_C4_Transport_Validation_MiSTer.rbf', '117adcd8d9360388826f60f4207c5b547daee58f5f0ba2e456f10e7bf41abed8', 'Engine C C4 validation artifact; source 5d0c9b73f70dd3912e112b172d36329d3e3d9cfe; exact artifact user-confirmed hardware PASS; Stage 1 staging only'),
 ('MegaVGMPlayer/MiSTer.megavgm', V2 / 'MegaVGMPlayer/MiSTer.megavgm', 'a0e7b7d3557457a80ecd62a6bb4643585c33b78fbe515a7a7a5783b05b5addb5', 'a409745a00ca428999e909edb69646f1a5fc62d4; existing v2.0 Main, dynamically linked by design'),
 ('MegaVGMPlayer/megavgm_supervisor', HOST / 'supervisor/megavgm-v22-supervisor-arm/megavgm_supervisor', '3c3e9d0141efa8966cdb2dfdd53d2e7edb7a35e55f23495879b8ac4a2ccfc5bf', '45d04cd993d9c7b5d85afb88ec563b811cf67e2c; static ARM; exact v2.2 A/B paths'),
 ('MegaVGMPlayer/megavgm_playlist-phase2a', HOST / 'controller/megavgm-v22-controller-arm/megavgm_playlist', '8e25bb51e849a0b7ca8b0f037656b8a297637881985fc2f0e3c7a0b66f4f56d3', 'ad450e076291e6cdf58fdb17f1ab5c88b114a797; static ARM; classifier semantics unchanged'),
 ('Scripts/vgm_md_import.sh', V2 / 'Scripts/vgm_md_import.sh', '700542daaeac0f59998d23a868073e6c6c165a4c350fc1119de28456f5f59103', 'e01c872d6854edce77c1fbc7a8f68239f8ecf045; unchanged importer'),
 ('MegaVGMPlayer/megavgm_remote', P1 / 'megavgm_remote-viewport-91e1a2e.phase1', '9cb59cb4032843a7e9b8368941540904da5d995df7d0b443b9e317f5a642cd7e', '91e1a2e57ebc7b0227e8b16afb8ac7a23f1bbfda; byte-identical v2.1 hardware-PASS ARM artifact; no rebuild'),
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
    manifest = ['# MegaVGMPlayer v2.2 — Stage 1 RBF naming candidate', '',
      'RBF distribution names and exact host paths are migrated. OSD, RTL, audio, transport, classifier decisions, and Player UI are unchanged.',
      'Packaging source commit: `'+subprocess.check_output(['git','-C',str(ROOT),'rev-parse','HEAD'],text=True).strip()+'`.',
      'Engine A/B are byte-identical copies of the v2.1 hardware-PASS RBFs. Engine C is the exact user-confirmed C4 hardware-validation RBF, staged under the final name but not production-routed in Stage 1.', '',
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
      'Embedded entry: assets/megavgm-36f68731.js; SHA-256 55b6b07c1c4684cfe60a3d86128630ac88f61885957a0c9ada5c2e45c32cf649.',
      'Full Phase 1 PROVENANCE is retained under provenance/.', '']
    (out/'ARTIFACT_MANIFEST.md').write_text('\n'.join(manifest))
    for name in ('install.sh','upgrade.sh','rollback.sh','common.sh','startup.block','README.md','README.ja.md','RELEASE_NOTES.md','HARDWARE_CHECKLIST.md','VALIDATION.md'):
        shutil.copy2(ROOT/'release'/name, out/name)
        if name.endswith('.sh'): (out/name).chmod(0o755)
    (out/'provenance').mkdir()
    shutil.copy2(ROOT/'PROVENANCE.md', out/'provenance/PHASE1_PROVENANCE.md')
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
