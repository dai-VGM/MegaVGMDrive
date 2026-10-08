# Current MegaVGMPlayer production build targets

Verified 2026-10-03 against current Engine Contract, RC `release/production_engines.json`, `release/final_authorities.json`, actual QPF files and accepted artifacts. This index is navigation; canonical contracts and release registry retain authority.

Build platform: Windows Quartus; macOS holds source authority. No Quartus build was run for this filesystem organization. Accepted artifacts retain the user-confirmed v2.3 hardware PASS; a new build requires its own validation.

BUILD THIS TARGET ONLY. Do not infer production targets from directory or QPF names. Do not build historical lab/debug/validation QPFs for production.

## ENGINE A

Status: CURRENT PRODUCTION — accepted v2.3 artifact; source HEAD verified.

Source worktree: `/Users/daizo/Projects/mister-vgm-fade-only-a`

Source HEAD: `16b1c6c2ec1404d3eb1223f6a495debc87cc2e65`

Production QPF: `/Users/daizo/Projects/mister-vgm-fade-only-a/MegaVGMPlayer_Transport13FadeOnly_A_MiSTer.qpf`

Production QSF: `/Users/daizo/Projects/mister-vgm-fade-only-a/MegaVGMPlayer_Transport13FadeOnly_A_MiSTer.qsf`

Production revision: `MegaVGMPlayer_Transport13FadeOnly_A_MiSTer`

Canonical deployed artifact: `MegaVGMDrive_A.rbf`

Accepted input artifact (preserve path): `/Users/daizo/Projects/MegaVGMPlayer_Transport13FadeOnly_A_MiSTer.rbf`

Accepted artifact size: 3336468 bytes

Accepted artifact SHA-256: `e481ca97fdec3c6724ddaecafd881bc63d50725775a9dedd3c85b93a8f31e683`

Build platform: Windows Quartus. BUILD THIS TARGET ONLY.

## ENGINE B

Status: CURRENT PRODUCTION — accepted v2.3 artifact; source HEAD verified.

Source worktree: `/Users/daizo/Projects/MegaVGMPlayer_EngineB_FM6_Activity`

Source HEAD: `a26c2ccc4cda65506152e8de05bc061d01e23c56`

Production QPF: `/Users/daizo/Projects/MegaVGMPlayer_EngineB_FM6_Activity/hw/transport_v1_3/MegaVGMPlayer_Transport13FadeOnly_B_MiSTer.qpf`

Production QSF: `/Users/daizo/Projects/MegaVGMPlayer_EngineB_FM6_Activity/hw/transport_v1_3/MegaVGMPlayer_Transport13FadeOnly_B_MiSTer.qsf`

Production revision: `MegaVGMPlayer_Transport13FadeOnly_B_MiSTer`

Canonical deployed artifact: `MegaVGMDrive_B.rbf`

Accepted input artifact (preserve path): `/Users/daizo/Projects/MegaVGMPlayer_Transport13FadeOnly_B_MiSTer.rbf`

Accepted artifact size: 3073680 bytes

Accepted artifact SHA-256: `2008a7e3eba48bf3d6babf5ee72e9c7fc44248228377ba929219f1ff480ba99e`

Build platform: Windows Quartus. BUILD THIS TARGET ONLY.

## ENGINE C

Status: CURRENT PRODUCTION — accepted v2.3 artifact; source HEAD verified.

Source worktree: `/Users/daizo/Projects/MegaVGMPlayer_EngineC_TransparentInfo`

Source HEAD: `82402ec2ecc12fd254eb2457d30473aae89854e4`

Production QPF: `/Users/daizo/Projects/MegaVGMPlayer_EngineC_TransparentInfo/hw/engine_c_packed_v2/MegaVGMPlayer_EngineC_C7_2_OSD_Visual_MiSTer.qpf`

Production QSF: `/Users/daizo/Projects/MegaVGMPlayer_EngineC_TransparentInfo/hw/engine_c_packed_v2/MegaVGMPlayer_EngineC_C7_2_OSD_Visual_MiSTer.qsf`

Production revision: `MegaVGMPlayer_EngineC_C7_2_OSD_Visual_MiSTer`

Canonical deployed artifact: `MegaVGMDrive_C.rbf`

Accepted input artifact (preserve path): `/Users/daizo/Projects/MegaVGMPlayer_EngineC_C7_2_OSD_Visual_MiSTer.rbf`

Accepted artifact size: 2700732 bytes

Accepted artifact SHA-256: `45f63808ca4d9871716af0bbc46f2335cd49d14fceafb537108ef2fa9f3e6110`

Build platform: Windows Quartus. BUILD THIS TARGET ONLY.

## ENGINE D

Status: CURRENT PRODUCTION — accepted v2.3 artifact; source HEAD verified.

Source worktree: `/Users/daizo/Projects/MegaVGMPlayer_EngineD_TransparentInfo`

Source HEAD: `239b371e7f3341726f62031cc31fa04be0752bde`

Production QPF: `/Users/daizo/Projects/MegaVGMPlayer_EngineD_TransparentInfo/MegaVGMDrive_D.qpf`

Production QSF: `/Users/daizo/Projects/MegaVGMPlayer_EngineD_TransparentInfo/MegaVGMDrive_D.qsf`

Production revision: `MegaVGMDrive_D`

Canonical deployed artifact: `MegaVGMDrive_D.rbf`

Accepted input artifact (preserve path): `/Users/daizo/Projects/MegaVGMDrive_D7.rbf`

Accepted artifact size: 2851200 bytes

Accepted artifact SHA-256: `fc0bf2bb09b87aff4d34bdf38619de469a04df0f9cab225d0bc5c2cc45cea300`

Build platform: Windows Quartus. BUILD THIS TARGET ONLY.

## Authority snapshots

Runtime source HEAD is f381918ad9c536433effea6158e9d1dc8aa831ae. Accepted supervisor, controller and remote artifacts intentionally have separate source HEADs in final_authorities.json. Earlier contract snapshots of those components must not replace the accepted final v2.3 artifact registry. Preserve all original inputs, including v2.2 SID/helper inputs and Runtime out/ and RC artifacts/.

## Future Engine E/F/G

Consult the canonical Engine Bring-up Runbook and Engine Contract first; select the correct base and scope independently. Prefer `/Users/daizo/Projects/MegaVGMPlayer_EngineE_<ChipName>` with `MegaVGMDrive_E.qpf`, `.qsf` and `.rbf` from initial bring-up, after checking the contract. E is not created by this organization. Existing A–D naming and revisions remain fixed.

## Hardware-accepted vNext candidates

Registered 2026-10-08. **Separate candidate authority; not a replacement for any v2.3 target above.** The original v2.3 sections and release registry remain unchanged. Hardware confirmation is scoped to the exact binaries in the [candidate ledger](VNEXT_HARDWARE_ACCEPTED.md); [machine-readable identities](hardware_accepted_vnext_candidates.json) are canonical candidate records.

### Engine A vNext candidate

- Status: **HARDWARE_ACCEPTED_CANDIDATE**, DAI confirmation 2026-10-08.
- Accepted RBF: `/Users/daizo/Projects/MegaVGMDrive_A_vNext_Production_MiSTer.rbf`.
- Bytes: 3380668; SHA256: `8c9ef2a084ff21732242b4d090b4e010b463c7f60fc7b461a58215983b5fb44d`.
- Candidate source worktree: `/Users/daizo/Projects/MegaVGMPlayer_ParserVNext`.
- Latest verified source Artifact commit: `da862eea0d08fbef8c239602df5cbe04a1ed8f6e` (**candidate only; producing RBF commit TBD**).
- Windows root QPF/revision: `MegaVGMDrive_A_vNext_Production_MiSTer.qpf` / `MegaVGMDrive_A_vNext_Production_MiSTer` in the Artifact.
- Candidate source ZIP: `/Users/daizo/Projects/MegaVGMPlayer_ParserVNext/out/production-ui/da862ee/MegaVGMDrive_A_vNext_Production_RC.zip`.
- ZIP SHA256: `9a9c270b2616e45467d1547e7eaed41748bf220ae67fbb30ee438b6bfa7f0c1a`.

### Engine B vNext candidate

- Status: **HARDWARE_ACCEPTED_CANDIDATE**, DAI confirmation 2026-10-08.
- Accepted RBF: `/Users/daizo/Projects/MegaVGMDrive_B_vNext_MiSTer.rbf`.
- Bytes: 3394284; SHA256: `9f62876ab573dbffde5abb1b6dc90e92f8afcb0875029d64357a6e51a8c55e7c`.
- Candidate source worktree: `/Users/daizo/Projects/MegaVGMPlayer_EngineB_vNext`.
- Latest verified source Artifact commit: `076ce2740c028d5e85fa957a496a313f58cc9f4b` (**candidate only; producing RBF commit TBD**).
- Windows root QPF/revision: `MegaVGMDrive_B_vNext_MiSTer.qpf` / `MegaVGMDrive_B_vNext_MiSTer` in the Artifact.
- Candidate source ZIP: `/Users/daizo/Projects/MegaVGMPlayer_EngineB_vNext/out/production-ui/076ce27/MegaVGMDrive_B_vNext_RC.zip`.
- ZIP SHA256: `637a6cd5f3249a350dd39dd8b3470c5460baef1941aed09d76150f2cf333d651`.

Both exact RBFs have DAI-confirmed audio, all-channel Activity, transparent bottom Loading, PWA automatic switching/playback and existing Controller/Supervisor compatibility. Long-duration tests and full production admission are NOT_RUN/not claimed. Only generated RBFs were copied from Windows; matching latest build reports/input identity remain unavailable, so filenames and current HEAD do not establish producing source commits. The saved older B report/output does not match the accepted B hash.

Use the root-QPF Windows GUI Build Artifact workflow for an explicitly authorized future candidate build. A new build does not inherit these exact-RBF hardware results. No release, deployment, package, Runtime/PWA or existing RBF changes are made by this registration.
