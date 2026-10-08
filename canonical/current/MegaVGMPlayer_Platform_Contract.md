# MegaVGMPlayer Player Platform Contract

Updated: 2026-10-09. Normative shared Player contract, frozen for ordinary engine work. Subordinate to [governance](AGENTS.md); hardware/plugin requirements belong to the [Engine Contract](MegaVGMPlayer_Engine_Contract.md). Evidence labels follow AGENTS. Requirements below do not claim fresh hardware validation.

## 1. Ownership and scope

The Platform owns Player/PWA/Remote presentation and navigation, Controller command/queue ownership, Supervisor switching, user loop preferences and timing telemetry. Engines provide the plugin facts/interfaces in the Engine Contract. Future engines use the same selection, load, status and release path; no engine-name behavior branches in PWA, Remote, Supervisor, Controller or Main.

A separately approved classifier/profile ID, wire vocabulary, chip metadata or package-registry extension may be needed. Extend data/schema and tests without changing generic ownership/state-machine semantics. Unknown capability or missing hardware contract is not repaired with an engine-specific Platform fallback.

## 2. Public lifecycle and identity

**REQUIRED**

- `IDLE`: no owned track. Fresh successor admission requires FPGA `version=2/session=0/IDLE/error=00` before upload.
- `LOADING`: the selected owner is being prepared/switched/uploaded and is not playback-ready. Host LOADING may begin before FPGA upload.
- `PLAYING`: owned session is active and navigation-ready. Cleanup must not discard navigation received after public PLAYING.
- `ENDED`: normal completion of the current session; queue policy may select next.
- `FATAL`: correlated failure of the current session.

Supervisor `PARKED/READY/SWITCHING` and generation/domain/baseline are switch-transaction state, not invented FPGA playback states. Remote request ID owns latest UI intent; Supervisor generation owns replacement; FPGA session identifies accepted index-1 load. Controller publishes path, metadata, session and timing atomically. Old commands/responses/polls cannot restore a superseded owner.

Same-engine reload reuses the resident and advances its session; session zero is required for a fresh successor, not every track.

## 3. Selection and navigation

Browse, Favorites, Playlist and future Search/history invoke the same conceptual `selectTrack(target)` contract.

- Dispatch a new user intent immediately; an earlier in-flight request must not suppress it. Do not serialize Browse taps behind `queuedPlay`.
- Latest request owns Loading/presentation; reject stale HTTP responses/telemetry. Do not show Loading for a request that was never dispatched.
- Controller claims a generation when deferred owned-load navigation is actually selected; never overlap Main/index-1 transfers. Coalesce rapid pre-ready selections to the latest intent while preserving Stop/mode priority.
- From another tab, Browse restores its last path. Re-tapping active Browse invokes parent; root is a no-op without reload/error. Repeated re-taps can reach root.
- Browse path changes do not change playback identity/path/context/metadata. Manual navigation remains available in Repeat One.

## 4. Fixed Player presentation

**REQUIRED semantic layout**

```text
track title                         soundChips · n/N
playing-track parent-folder basename
elapsed                 progress                 planned total
Prev / Play-Pause / Next / Stop / Repeat / Shuffle
```

Browse/Playlists and the existing Favorites arrangement remain. CSS pixels are not frozen; semantic placement, usable touch controls and ownership are.

| Information | Authority |
|---|---|
| title / current path | current Controller/Remote status |
| parent row | basename of parent of authoritative `status.path` |
| chip label | classifier → validated Remote metadata → `status.soundChips` |
| `n/N` | Controller-owned directory/playlist context |
| elapsed / planned total | Controller timing publication |

Title/parent may ellipsize; missing parent is hidden, not invented. Chip/position remains nowrap and must not be inferred from profile. Do not substitute current Browse path or playlist name. Progress is display-only; seeking is outside this contract. At 320/393 px, no horizontal document/player overflow. No engine-specific layout.

Current validated chip vocabulary includes PSG, YM2612, YM2151, YM2203, SegaPCM, YM2610, YM2610B, SID 6581/8580 and C140. Unknown/duplicate labels are omitted under current validation, without changing transport validity. New vocabulary requires scoped metadata tests, not a new UI flow.

## 5. Timing presentation

Controller owns published Player elapsed/planned timing; frontend interpolation is display-only. Engine VGM sample-time authority is the [continuous logical timeline](MegaVGMPlayer_Engine_Contract.md#7-continuous-logical-time), not Controller wall-clock presentation. Do not use either UI interpolation or resource waits to retime engine events.

**REQUIRED existing formulas**

- `elapsed_ms` begins at first owned-session PLAYING; excludes PREPARING/LOADING, resets for new path/session and preparation/loading, freezes outside PLAYING including ENDED/FATAL, and is zero for STOPPED.
- Valid VGM counts convert with `ceil(samples × 1000 / 44100)`.
- Non-loop planned duration: header total +100 ms, for the established natural-EOF Transport fade.
- Finite internal-loop limit `N`: header total + `(N−1) × header loop duration`. TWO_LOOPS is first traversal plus one loop traversal; fade is inside loop two, so no extra EOF tail.
- Repeat One or native-loop policy with limit zero presents `INFINITE`. Invalid/missing timing metadata is `UNKNOWN`.
- MVGMSID timing uses validated header cycles and declared PAL/NTSC clock; capture-limited/invalid data remains UNKNOWN.
- Display finite total, `∞` or `--:--`. Interpolate only during PLAYING, at most 1.5 seconds beyond newest backend observation; resync on fresh data, reject older polls. New loading/retarget presents elapsed zero immediately.

These retained formulas are not evidence that arbitrary `N` is exposed by the current UI/control wire. Extending that preference is separate work.

## 6. Repeat, Shuffle and internal-loop preference

Repeat mode is queue policy; VGM internal loop count is engine Transport policy. Keep them separate.

- Repeat Off follows the immutable current queue and completes at its end; it is not the same as the internal Transport policy OFF command.
- Repeat One disables automatic internal-loop termination for looping tracks. A non-loop ENDED reloads the same queue index.
- Repeat All wraps after ENDED at the queue boundary. Playlist/Controller selects next, never Parser/Core.
- Shuffle uses the Controller permutation bag, avoids immediate current-track repetition in a multi-track cycle, and PREV follows actual history. Disable resumes ordered traversal from current index.
- Current default finite internal-loop policy is TWO_LOOPS; its pending/active/fade/session behavior is specified by [Engine loop ownership](MegaVGMPlayer_Engine_Contract.md#5-loop-policy-and-continuation).

Player/Controller owns user preference; Transport implements loop count, CONTINUE/HALT and fade. Future preference values 1/2/3/5/infinite must not require changing Parser grammar or continuation client. Existing `MV 02` control records are unchanged by this specification; arbitrary-count wire/UI support is **TBD**, not implicitly implemented. Parser lookahead does not count playback boundaries.

## 7. Generic engine switching and exit

```text
latest owned selection → SwitchOwner PARKED
 → resident FADE_ONLY → same-session ENDED/release
 → RBF replacement and successor Main/core verification
 → fresh pre-upload IDLE → CORE_VERIFY_SUCCESS → READY lease
 → accepted index-1 load → owned LOADING → PLAYING
```

Same-engine retarget uses the same generic ownership and may reuse the resident without replacement. No old-session completion may release a newer owner. Resident release precedes cross-engine replacement; unexpected Controller exit is not release. Verify successor process/artifact identity, CORENAME and fresh FPGA status before upload. Keep Main physical transfer witness, FPGA drain/fence, engine admission and public PLAYING as separate checkpoints.

## 8. Main/UI and observation boundary

Main remains generic. Transparent bottom Loading is the Engine Contract's [production UI ABI](MegaVGMPlayer_Engine_Contract.md#11-production-ui-abi); Main owns geometry, FPGA preserves it. Channel Activity is chip-derived Engine metadata rendered generically by the Golden OSD. Neither required UI is measurement-only or removable during production trim.

Observation/status bridges do not gate upload, Parser, playback or audio. A failed Loading hardware gate remains failed even if audio/Activity and host command replay pass. Do not add a Main engine-name branch to mask an FPGA contract failure.

## 9. Platform freeze and revisions

Ordinary engine bring-up preserves PWA/navigation, Remote playback semantics, Supervisor switching, Controller ownership and Main transport behavior. Contract-restoring fixes, accessibility/visual polish, observability and explicit policy revisions still require appropriate authorization/evidence. A proposal names the insufficient clause, why engine compliance cannot solve it, affected tests and hardware matrix. Required UI is not discretionary visual polish.

## 10. Platform regression and deployment acceptance

Run applicable host/ARM/QEMU, Remote API/Go, frontend unit/render/DOM and production bundle/browser checks for the touched layer. Retain selection/immediate second tap/rapid latest-wins, navigation/Stop/modes, same-/cross-engine retarget, Favorites/Playlist, Browse parent/root/preservation, finite/unknown/infinite timing, stale telemetry, metadata and 320/393 geometry. Engine/static admission and negative fixtures remain additional checks.

Hardware/deployment acceptance confirms exact Main/RBF/Controller/Remote identity, installed PWA readability/cache state, audio, touch behavior, real queue/transitions and lifecycle. Distinguish the Remote executable, served bundle and executing installed-PWA bundle; restart Remote alone need not update an already running client. Reopen the installed PWA when needed and record its bundle/hash.

Engine A/B/C/D/E build delivery follows the [Human-facing Build Artifact Contract](MegaVGMPlayer_Engine_Bringup_Runbook.md#human-facing-build-artifact-contract): extract ZIP, open the root canonical QPF in Windows Quartus GUI, run Full Compilation and inspect `output/`. `BUILD.bat` is optional, not a READY/PASS condition; helper failure is separate from canonical QPF compilation failure. This delivery rule changes no Platform/Engine runtime behavior.

## 11. Current authority and evidence limits

Existing v2.3 payload identity comes from [release final authorities](MegaVGMPlayer_vNext_4Engine_RC/release/final_authorities.json) and [BUILD_TARGETS](MegaVGMPlayer_CURRENT/BUILD_TARGETS.md), not an old Contract HEAD table. Runtime source HEAD, accepted Controller/Supervisor source HEADs and exact deployed bytes may differ intentionally. Do not replace accepted artifacts with a later source build by inference.

The v2.3 registry pins Controller source `ffd3336fb60472c82e4ece3133e407d15b671667`, Remote source `45a45d8013fbc6292008af5d0269811493d8860e` and their exact payload hashes. The [v2.4.0 RC](MegaVGMPlayer_vNext_Integrated_RC/README.md) preserves those Runtime/Main/Controller/Supervisor/Remote/PWA payload bytes, existing canonical A–D launch paths, CORENAME and switching semantics. Only A/B/D RBF identities change in the isolated RC; C remains byte-identical.

Current A A1+A2 / B seed3 / D source-build bindings and reported hardware scopes are centralized in the [adoption manifest](MegaVGMPlayer_vNext_Integrated_RC/release/v2.4.0/adoption-manifest.json). Earlier RBF-only A/B registration limitations remain historical for the older ledger hashes. No fresh long-duration/full-admission/each-transition certification is inferred from PWA/audio confirmation. This documentation update changes no Platform code or deployed environment.

**TBD:** arbitrary finite-loop preference wire/UI, future profile/schema integration, untested installed binaries and any transition path without exact evidence. This documentation revision changes no Runtime/PWA/Main behavior or release payload.

## 12. Historical evidence

The complete previous Platform snapshot and its exact hashes are preserved in the [documentation history](MegaVGMPlayer_Documentation_History/20261007-vnext-refresh/README.md). Use the release registry for legacy payload identity and the Engine/Runbook evidence pointers for current plugins. Historical source/hardware reports do not grant authority to rebuild, deploy or publish.
