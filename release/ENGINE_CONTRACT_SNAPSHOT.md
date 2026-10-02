# MegaVGMPlayer Production Engine Contract

Status: human-readable production contract. This document does not replace the [canonical governance](AGENTS.md), the [Golden Player Platform Contract](MegaVGMPlayer_Platform_Contract.md), the release registry, or executable admission tests. Evidence snapshot: 2026-10-02; source and artifact authorities are listed in §8.

## 1. Scope / terminology

This contract applies to every engine admitted to the MegaVGMPlayer multi-engine runtime, not merely to an RBF that plays through MiSTer's manual OSD. The **resident engine** is the loaded RBF currently owning playback; the **target engine** is the RBF requested by a transition. A **session** identifies one accepted index-1 track load. The **Transport owner** owns policy, fade, and resident release; a chip-native parser owns its own command and loop semantics. **Playback-time boundary** means the loop boundary has reached the audio/playback timeline, not just a frontend read-ahead decode.

This document specifies what each Engine must provide to the common Platform. The Platform Contract specifies the frozen PWA/UI, Remote, Supervisor, Controller, Main, navigation, timing-presentation, and generic switching behavior. Engine admission must satisfy that generic Platform contract; a standalone RBF result is insufficient and must not be repaired with an engine-specific Player branch.

Evidence labels used below:

- **Required** — admission contract for current and future production engines.
- **Proven** — observed in the cited production source, regression, or stated hardware result; the evidence type is named. This does not imply a newer RBF passed hardware.
- **TBD** — not established by the inspected evidence; do not infer a PASS.

## 2. ioctl ownership

**Required**

- Index `1` is VGM upload. The engine-specific upload/profile path must act on `ioctl_download` and `ioctl_wr` only for its assigned VGM index. Its download edges, reset, load-busy, session start, parser/frontend rekey, and read cancellation must not respond to a different index.
- Index `2` is Transport/control. The complete four-byte `MV 02 <command>` record is interpreted by the Transport owner; currently `00` means policy OFF, `01` means TWO_LOOPS, and `02` means FADE_ONLY. A non-VGM/control transfer must not change engine playback, reset, or load state. Partial, oversized, or unknown control records must not become a valid command.
- The shell/Main-facing raw ioctl bus may feed both designated owners, but semantic ownership must be filtered at each consumer. Index `2` must not be reinterpreted as an index-1 upload.

**Proven — source and D6 hardware:** the shared Transport owner decodes index `2`; Engine D's production profile owns index-1 VGM upload only. An index-2 Transport/control transfer does not reset, reload, or disturb active C140 playback. D6's index-2 FADE_ONLY reached same-session ENDED. Rationale: a successful host file transfer alone does not prove that the resident engine accepted the intended control command.

## 3. Runtime Status ABI

**Required**

- After fresh reset, *before* any upload, publish a readable version-2 record with `session=0`, `state=IDLE`, and `error=00`. A late-attaching Main must still be able to observe it; do not rely solely on a one-cycle/one-shot boot notification.
- For an accepted index-1 download, advance the session and expose `IDLE → LOADING → PLAYING → ENDED` or `FATAL`, as appropriate. DONE/FATAL and error information must correlate to the **current** session, not an earlier load.
- Expose loop-valid and loop-count/boundary telemetry through the established status ABI. Telemetry reports state; it does not itself make the loop-control decision.
- The production source graph must contain exactly the applicable `megavgm_playlist_status_export.sv`, elaborate its instance, and connect its output through the production top's status readback path. New engines use `MEGAVGMDRIVE_PLAYLIST_STATUS_PHASE1B` and `MEGAVGMDRIVE_PLAYLIST_LOOP_PHASE1E`; frozen A/B/C authorities may retain their registry-declared integration. Keep the `MegaVGMDrive` CORENAME contract.
- A profile status bridge is observation-only. It must not gate upload, parser, playback clock, or audio. Exporter reset/readiness must not depend on upload completion: Supervisor verifies the new RBF **before** uploading its VGM.

**Proven — runtime source and A/D6 hardware:** `LinuxRuntime::verify_megavgm_core()` requires successor Main/RBF identity, matching CORENAME, and a fresh status read. In Phase 2A, freshness means `version=2/session=0/IDLE/error=00`. The status file is `/tmp/MegaVGMPlayer.status`, published by modified Main from FPGA readback; its absence during manual OSD-only playback is not, by itself, an FPGA diagnosis. A and D6 exposed pre-upload status in hardware; D6 reached `CORE_VERIFY_SUCCESS` and passed A→D. Merely registering or instantiating an exporter is insufficient without hardware-facing readback.

## 4. Transport / resident exit contract

**Required**

- A resident engine in live `PLAYING` must accept index-2 FADE_ONLY for that session, let the established Transport fade owner complete its fade, then publish `ENDED` for the **same** session. Do not fabricate ENDED before fade completion.
- The resident remains responsible for status and control through its exit. The playlist/controller may park the transition (`PARKED`); only after resident release may SwitchOwner start the target `RBF_LOAD_BEGIN`. Unexpected controller exit is not a substitute for release.
- Manual FADE_ONLY must preserve ordinary EOF, native loop, FATAL, manual Stop, and reload behavior.

**Proven — D6 hardware:** from live `PLAYING`, index-2 FADE_ONLY used the Transport fade owner and produced same-session ENDED; resident release advanced `PARKED → target RBF_LOAD_BEGIN → target playback`. A→D, D→A, and D→B passed. The contract is about the resident's exit as well as the target's admission.

## 5. Loop policy contract

**Required**

- Retain an index-2 TWO_LOOPS **pending** policy across the following index-1 upload/reset boundary; make it **active** for the new session. Track-local fade/loop measurement state may reset on load, but the pending command must not disappear.
- Keep loop telemetry and loop control separate. Parser/frontend lookahead of `0x66` is not a playback-time boundary and must not increment the Transport owner's loop count. Feed the owner loop-entry/boundary events at actual playback time.
- With TWO_LOOPS active, an engine with native looping may wait to commit its `0x66` redirect until the corresponding playback boundary and owner halt decision. At the second traversal's boundary, owner halt prevents entry into a third traversal; without halt, native redirect proceeds.
- With policy OFF, preserve the engine's existing native loop semantics. Repeat One disables automatic loop-limit termination and likewise preserves native looping. Do not change sample-fetch/address/cache behavior as a side effect of loop control.
- Use the **same Transport fade owner** for manual FADE_ONLY and loop-limit termination. Its measured loop duration governs the fade; after fade/end pulse, publish same-session ENDED. Repeat All's next-track choice belongs to the playlist layer **after** ENDED, not to the engine.

**Proven — source, simulation, and D6 hardware:** A/B/C Transport owner source measures actual loop entry/boundary and owns fade/halt. D6 retains pending TWO_LOOPS across index-1 upload and activates it for the new session. Under that policy, frontend `0x66` lookahead is not counted as a loop boundary: the owner receives playback-time events, fade runs through the Transport owner, and halt at the second-traversal boundary prevents a third native redirect. D6 then publishes same-session ENDED and next-track progression passes. Manual FADE_ONLY uses the same fade owner and remains hardware-PASS. With policy OFF, native C140 loop semantics remain intact. With Repeat One, loop-limit policy is disabled and native C140 looping continues: Submerged City remained in the same `PLAYING` session for at least 16 minutes 25 seconds, well beyond normal TWO_LOOPS termination, without automatic ENDED. The corresponding policy-OFF cycle-equivalence, read-ahead/variable-latency, and two-loop simulations also passed at the D source HEAD in §8.

## 6. Production Engine Admission

**Required**

A standalone RBF **Hardware PASS is not a MegaVGMPlayer production Engine PASS**. Promotion requires the exact source HEAD and RBF SHA-256, successful static/simulation checks, Quartus fit/timing, compatibility with the frozen [Golden Player Platform Contract](MegaVGMPlayer_Platform_Contract.md), and the following real-runtime acceptance on the candidate artifact:

1. PWA cold-start: successor Main, CORENAME, and pre-upload `session=0/IDLE/error=00` readback satisfy `CORE_VERIFY_SUCCESS`.
2. Same-engine transition and reload/reset preserve the session/status contract.
3. Cross-engine `A→new`, `new→A`, `new→B`, and `B→new` exercise both resident exit and successor admission. At minimum, confirm `PARKED → target RBF_LOAD_BEGIN → CORE_VERIFY_SUCCESS → target LOADING → PLAYING`; do not count a display change alone as admission.
4. Normal loop-limit termination, Repeat One, Repeat All handoff, manual FADE_ONLY, loop status ABI, non-loop EOF, FATAL, and Stop behave as specified above.

**Proven — existing governance/registry:** the current static admission registry requires PWA cold-start, same-engine, `A→new→A`, loop status, and reload/reset. The additional `new→B` and `B→new` paths above are **required by this specification**, not claims that the present static Gate already enforces them.

**Proven — D6 hardware subset:** pre-upload `session=0/IDLE/error=0`, `CORE_VERIFY_SUCCESS`, A→D, D→A, D→B, resident FADE_ONLY release, normal TWO_LOOPS termination with next-track progression, and Repeat One native continuation. This does **not** by itself establish every §6 acceptance item for D6; unreported paths remain TBD.

## 7. Non-negotiable invariants

**Required**

- Reuse the hardware-PASS Golden Shell: video/OSD, physical DDR upload, `hps_io`, reset/Main-HPS handoff, and shared transport are not engine-local replacements.
- Status observation and control-plane policy must not unnecessarily gate upload, parser, PCM fetch, audio, or playback timing. A narrowly scoped, policy-active loop-commit synchronization is permitted when required by §5; policy OFF remains native-equivalent.
- Do not add per-engine fallbacks or exceptions to Supervisor to mask a missing FPGA contract.
- Never confuse frontend/parser lookahead with playback-time events. Keep engine-specific chip behavior separate from shared production infrastructure.

## 8. Known implementation authorities

The release [engine registry](MegaVGMPlayer_vNext_4Engine_RC/release/production_engines.json) identifies each production QPF/QSF/source graph. The artifact source HEAD is the provenance paired with the staged hardware-PASS RBF; a later worktree HEAD is listed separately and inherits no artifact claim.

| Engine | Artifact source HEAD / RBF authority | Production QPF / revision | Current worktree snapshot |
| --- | --- | --- | --- |
| A | `16b1c6c2ec1404d3eb1223f6a495debc87cc2e65`; 3,336,468 bytes; SHA-256 `e481ca97fdec3c6724ddaecafd881bc63d50725775a9dedd3c85b93a8f31e683` | `MegaVGMPlayer_Transport13FadeOnly_A_MiSTer.qpf` / `MegaVGMPlayer_Transport13FadeOnly_A_MiSTer` | `mister-vgm-fade-only-a` at the same HEAD |
| B | `a26c2ccc4cda65506152e8de05bc061d01e23c56`; 3,073,680 bytes; SHA-256 `2008a7e3eba48bf3d6babf5ee72e9c7fc44248228377ba929219f1ff480ba99e` | `hw/transport_v1_3/MegaVGMPlayer_Transport13FadeOnly_B_MiSTer.qpf` / `MegaVGMPlayer_Transport13FadeOnly_B_MiSTer` | `MegaVGMPlayer_EngineB_FM6_Activity` at the same HEAD |
| C | `82402ec2ecc12fd254eb2457d30473aae89854e4`; 2,700,732 bytes; SHA-256 `45f63808ca4d9871716af0bbc46f2335cd49d14fceafb537108ef2fa9f3e6110` | `hw/engine_c_packed_v2/MegaVGMPlayer_EngineC_C7_2_OSD_Visual_MiSTer.qpf` / `MegaVGMPlayer_EngineC_C7_2_OSD_Visual_MiSTer` | `MegaVGMPlayer_EngineC_TransparentInfo` at the same HEAD |
| D | `239b371e7f3341726f62031cc31fa04be0752bde`; input `MegaVGMDrive_D7.rbf`, 2,851,200 bytes; SHA-256 `fc0bf2bb09b87aff4d34bdf38619de469a04df0f9cab225d0bc5c2cc45cea300` | `MegaVGMDrive_D.qpf` / `MegaVGMDrive_D` | `MegaVGMPlayer_EngineD_TransparentInfo` at the same HEAD |

Relevant engine implementation authorities remain A `rtl/mister_vgm_md_top.sv`, B `rtl/golden_player_shell_v1_2_compat/transport.sv`, C `rtl/engine_c_c4/transport.sv`, D `rtl/c140_stage3_profile_body.svh` plus `rtl/megavgm_engine_d_transport_adapter.sv`; all use the established Transport/status contract declared by the registry.

Runtime source authority: `MegaVGMPlayer_vNext_4Engine_Runtime` at `f381918ad9c536433effea6158e9d1dc8aa831ae`. The accepted Controller remains the same-track-restart artifact from `ffd3336fb60472c82e4ece3133e407d15b671667`; the accepted Supervisor remains the transparent-Main-authority artifact from `8c1b57019a318ec7b96a0ec14674b3cab3cd518d`. Both are ancestors of the Runtime authority. Admission mapping authority: `MegaVGMPlayer_vNext_4Engine_RC/tests/production_engine_admission_gate.py` and `release/production_engines.json`; final artifact identities are pinned in `release/final_authorities.json`. C admission uses OSD_Visual; D uses the D7 transparent INFO source graph. Parameterized-exporter hierarchy support entered at `6f538a6b93572750d602bb324fca7cabfe1d3243`.

**Proven — prior D6 hardware:** the detailed results in §§2–6 belong to source `5cf9faea2f2a07ead9c3e54653b27fbff8a0b654` and RBF SHA-256 `155a87c1b3421397be62d51b1020bb96edfbad045759b8e5f7e71daa26860865`. Those historical results are not fresh measurements on D7. **Proven — user-confirmed final hardware:** A/B/C/D transparent LOAD/normal playback, B Stage 6 first-loop and next-track behavior, C SID activity gauge, transparent Main loading, same-track restart, and the three normalized Rolling Thunder 2 tracks plus Jc-Kal/YM2612-only smoke, A/B/C/D switching, Exit→STOCK, and Remote/PWA reconnect passed on the final accepted artifact set. Final payload sizes/full hashes are verified from exact local artifacts; no RBF is regenerated during promotion.

**TBD:** any §6 path not explicitly reported remains TBD; do not transfer a detailed PASS claim between source HEADs or artifacts. Publication remains subject to the final package lifecycle/hash/inventory/cleanliness gate and separate user approval.

## 9. Admission Gate mapping

The existing Gate is a **static source-graph check**, not a replacement for simulation or hardware. “Required validation” below maps this contract to evidence; it does not claim every test already exists or change the Gate.

| Contract | Existing static Gate | Required simulation / host check | Required hardware check |
| --- | --- | --- | --- |
| Golden Shell, CORENAME, canonical RBF name, QPF/QSF graph | Registry/source-graph audit | Production elaboration and no duplicate status driver | Core identity after RBF load |
| Exporter, macros, status wiring, pre-upload readiness | Exporter/source/instance/macro and lifecycle checks | Reset `session=0/IDLE/error=00`, late observer, full status lifecycle | Pre-upload status and `CORE_VERIFY_SUCCESS` |
| Index-1 vs index-2 ownership | Not fully covered | Non-VGM ioctl cannot reset/reload active playback; upload still works | Control transfer during live playback, then successful exit |
| Current-session DONE/FATAL and loop telemetry | Textual lifecycle evidence | Session correlation, loop-valid/count, reset/reload | Published `/tmp/MegaVGMPlayer.status` lifecycle |
| FADE_ONLY resident release | Not fully covered | Live PLAYING → fade → same-session ENDED → release | `PARKED → target RBF_LOAD_BEGIN` |
| Pending TWO_LOOPS, playback-time events, halt, policy OFF/Repeat | Not fully covered | Policy survives load; lookahead stress; two boundaries/one native redirect; OFF equivalence | Normal loop-limit, Repeat One, Repeat All handoff |
| Cold/same/cross-engine admission | Registry lists cold, same, `A→new→A` | Host/QEMU profile transitions | §6 full matrix, target LOADING→PLAYING |

**Proven — current Gate result:** the current Gate recognizes unparameterized and parameterized SystemVerilog instances and gives elaboration/hierarchy evidence precedence over text matching. It passes A/B/C/D and its negative fixtures continue to reject a missing exporter, missing required macro, unelaborated source, upload-gated readiness, and incomplete session/DONE/FATAL/loop contracts. This remains static/source evidence, not hardware admission.

Final promotion regression marker: `PRODUCTION_ENGINE_ADMISSION_REGRESSION_PASS current=A/B/C/D old_d_missing=FAIL old_d_upload_gated=FAIL unelaborated_exporter=FAIL`. The negative FAIL results are required rejection outcomes.
