# MegaVGMPlayer v2.4.0 — Architecture Refresh

Local Release Candidate. No installation, production promotion, Git tag/push or GitHub publication has been performed.

Existing supported chips and Player features are retained as the compatibility target. A/B/D use refreshed shared VGM infrastructure; Engine C and all eight Main/Runtime/helper payloads retain v2.3 bytes. No new chip or combined A+D core is included.

| Engine | Supported scope |
|---|---|
| A | SN76489 PSG, YM2612 including DAC client, YM2151, YM2203, SegaPCM |
| B | YM2610/YM2610B FM/SSG/ADPCM-A/ADPCM-B |
| C | SID 6581/8580, unchanged prepared MVGMSID native-cycle path |
| D | C140 System2/System21, optional YM2151; ASIC219 unsupported |

Canonical engine paths remain `/media/fat/_Custom Cores/Cores/MegaVGMDrive_A.rbf` through `MegaVGMDrive_D.rbf`; CORENAME remains `MegaVGMDrive`. Runtime, music, Favorites/Playlists, automatic switching and SID preparation paths are unchanged. Root .sid handling uses the retained host preparer, not the Common VGM Parser.

Read RELEASE_NOTES.md, ARTIFACT_MANIFEST.md, TIMING.md, HARDWARE_ACCEPTANCE.md and KNOWN_LIMITATIONS.md before adoption. The package has the v2.3 distribution layout and exact retained source/licenses plus selected Engine Build Artifacts under source/engines. Build instructions are in BUILD.md.

After explicit deployment approval only: return Player to STOCK and close Player tabs, run `sh install.sh` (or `sh upgrade.sh`) and retain the printed backup path. `sh rollback.sh` restores that transaction's predecessor. v2.4 checkpoints use `backups-v2.4.0-*` / `.v240-last-backup`; startup markers and shared `.v22-install-lock` remain unchanged compatibility identifiers. Installation is journaled per-file rename, not one atomic multi-file transaction. User library/Favorites/Playlists and legacy rescue RBFs are not payloads.

Current hardware receipts are scoped user reports, not a new long-duration/all-track guarantee or a completed production admission matrix. C's exact original producing build is not recovered. No new compilation is needed to assemble these frozen accepted artifacts.
