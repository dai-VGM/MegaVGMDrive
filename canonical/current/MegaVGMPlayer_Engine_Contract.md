# MegaVGMPlayer vNext Engine Contract

Updated: 2026-10-09. Normative hardware/plugin specification for current and future engines. [AGENTS](AGENTS.md) governs authority/protected work; the [Platform Contract](MegaVGMPlayer_Platform_Contract.md) owns Player policy. REQUIRED / PROVEN with evidence type / TBD have the meanings in AGENTS. A required interface is not automatically implemented or hardware-PASS.

## 1. vNext Engine Plugin architecture

```text
Byte/Resource Source → Strict Reader → Common Parser
 → Scheduler / Logical Timebase → Engine Adapter → Sound Core → Output Adapter
                                                        ↕ optional
                                                Storage / Sample Client
                                                        ↕
                                             strict resource/backend binding
```

This defines responsibility, not mandatory physical duplication. Sample reads form a side path to the Core; they are not Parser events containing physical DDR data. Reuse Golden upload/backend/shell and established audio/status boundaries.

| Owner | Owns | Must not own |
|---|---|---|
| Byte/Resource Source | immutable file extent, source/resource lifecycle, backend binding | VGM playback policy |
| Strict Reader | byte/fault result, transaction/epoch, physical debt/drain ownership | grammar, synthetic EOF, chip execution |
| Common Parser | command identity, raw operands, grammar metadata, checked file span, facts/order, validated loop target | loop count, chip behavior, storage/cache, physical DDR, busy/fade/Player/session policy |
| Scheduler | WAIT-derived due-time, global sequence, independent playback timeline, target queues, playback boundary | resource byte resolution, legacy overhead compensation, loop-count policy |
| Engine Adapter | target/instance/port/address/data translation, ready/busy acceptance | VGM grammar, WAIT interpretation, loop/fade/session policy, sample semantics |
| Sound Core | chip registers/state, native update/sample semantics, logical sample requests and channel activity | file offsets, physical DDR, Player policy |
| Storage / Sample Client | resource spans/mapping, cursor if needed, prewarm/prefetch/cache, ownership/faults | retiming WAIT or modifying chip semantics |
| Output Adapter | declared gain/domain conversion, rounding/saturation, common audio boundary | VGM decode, hidden timing compensation |

Optional admission transaction:

```text
upload/fence → Common Parser PASS1 → engine Preflight/admission/descriptor preparation
 → validation PASS + required resource readiness + reset complete
 → replay Common Parser PASS2 from data start → Scheduler/playback
```

Rejecting PASS1 must emit **zero audible writes**. PASS1 elapsed cycles are not playback time. Variant/capability/resource validation belongs to Preflight/Adapter, not generic grammar. B's preparation/store technique is a proven implementation example; it is not a mandatory buffer design for every engine.

Common VGM grammar is frozen at accepted semantics. Audit actual opcode coverage before new chip work; explicitly review a missing generic extension. Current supported families include PSG `4F/50`, FM `52–55/58–59`, waits `61/62/63/70–7F`, END `66`, DATA_BLOCK `67`, DATA_SEEK `E0`, DAC facts `80–8F`, generic writes `C0/D4` and loop metadata/facts. This is coverage, not admission for every chip/instance. Reserved/unsupported commands, dual aliases, `68/90–95` remain explicit rejection unless separately approved. SID/MVGMSID is outside Common VGM Parser and uses its separate prepared-format client.

WRITE is one generic fact with target/chip, instance, access kind, grammar port, address (currently 16-bit), byte data and source/raw-operand evidence. No per-engine WRITE event type. DATA describes file spans/encoded metadata, not storage destinations. DAC is an unresolved grammar fact; its client resolves one byte/cursor and expands YM2612 port0/register2A. The Scheduler owns the encoded implicit wait. Do not manufacture normalized events around Parser or move bank state into it.

## 2. ioctl ownership

**REQUIRED**

- Index `1`: accepted VGM upload; every engine consumer filters download/write/edge/reset/rekey/cancel by its designated index. Other indices cannot reset playback or start a session.
- Index `2`: existing shared Transport records `4D 56 02 <command>`; `00` policy OFF, `01` TWO_LOOPS, `02` FADE_ONLY. Partial/oversized/unknown records do not execute. These records are unchanged; arbitrary finite-count encoding is not added here.
- Raw shell ioctl may feed separate designated owners, each filtered. Golden physical upload packing, wait/backpressure and DDR drain/fence remain shared. Download falling edge or Main transfer-success alone does not prove storage completion, valid grammar or playback readiness.

## 3. Runtime Status ABI

**REQUIRED**

- After fresh RBF reset and before upload, repeatedly readable version-2 `session=0/IDLE/error=00`, including a late-attaching Main. Exporter readiness must not depend on upload completion.
- Accepted index-1 load advances session; publish LOADING → PLAYING → current-session ENDED or FATAL. Do not attribute stale DONE/FATAL/error to a new session. Reload does not require session zero.
- Expose established loop-valid/count/boundary telemetry. Observation is not policy/counting authority.
- Exact selected graph must compile, instantiate and wire `megavgm_playlist_status_export.sv` through actual status readback. New engines enable `MEGAVGMDRIVE_PLAYLIST_STATUS_PHASE1B` and `MEGAVGMDRIVE_PLAYLIST_LOOP_PHASE1E`; registered legacy A/B/C integration remains its pinned exception. CORENAME is `MegaVGMDrive`.
- Status bridges are observation-only; they cannot gate upload, reader, playback clock or audio. Preserve `/tmp/MegaVGMPlayer.status` Main publication and generic Runtime verification. Missing status during manual OSD-only playback requires boundary diagnosis, not an engine-name verification bypass.

## 4. Transport and resident exit

Live PLAYING accepts FADE_ONLY for the owned session, uses the shared Transport fade owner, then publishes same-session ENDED after fade completion. Resident status/control remains live through release. PARKED transition proceeds to target RBF replacement only after resident release; Controller exit is not a substitute.

Manual exit must preserve ordinary EOF/native loop/FATAL/Stop/reload semantics. Use the same fade owner for natural EOF, manual fade and finite-loop termination. Playlist next-track selection remains outside the engine.

## 5. Loop policy and continuation

| Layer | Responsibility |
|---|---|
| Parser | validated loop metadata/target and grammar boundary facts |
| Scheduler | boundary reaches playback logical time; prior events drain in contract order |
| Transport | pending/active preference, count, fade, CONTINUE/HALT decision |
| Loop continuation client | only on CONTINUE, resume the same Parser at validated target PC |
| Player/Controller | user preference and queue Repeat/navigation |

**REQUIRED**

- Pending TWO_LOOPS survives the following index-1 load/reset and becomes active for that session. Track-local measurement/fade state may rearm; pending policy is not discarded.
- Parser read-ahead END/loop facts do not increment Transport count. Boundary is playback-time, not decode-time.
- TWO_LOOPS permits first continuation, completes the second traversal and HALTs before third redirect. HALT emits no resume request. Shared owner fade ends the same session.
- Policy OFF permits native VGM continuation. Repeat One disables automatic finite-loop termination; it is distinct from an internal loop count and from queue Repeat Off.
- Resume uses validated entry/resume-PC control; it is not new-track reset. Do not reset chip/sample/bank/cursor/cache/resource state merely on VGM loop. Explicit commands within the stream can change that state normally. Chip-native sample loops are independent.
- Continuation/barrier clients do not own a count or TWO_LOOPS. Future 1/2/3/5/infinite preferences change Transport/Player policy and, if needed, its explicitly reviewed control encoding; Parser grammar/client remains unchanged.

Prepared raw command-prefix replay may ensure timely loop supply, but feeds the **same Parser**. No prepared-event bypass or key-on-specific compensation. Bounds/epoch/ordering and seamless prefix-to-reader PC continuity must be proven. B reuses prepared store with a small starvation-free prefix runway; other engines choose measured mechanisms.

## 6. Production Engine Admission

Standalone audio Hardware PASS is not production Engine PASS. Require exact source/build/RBF identity, applicable static and tiered regressions, Windows fit/timing, and real-runtime acceptance:

1. Successor Main/core identity, CORENAME, pre-upload IDLE and CORE_VERIFY_SUCCESS on cold entry.
2. Same-engine retarget and deterministic cold/same-track/repeated/different-track/loop→reload behavior.
3. Generic cross-engine A→new, new→A, new→B, B→new (deduplicate if new is A/B), including resident fade/release, PARKED → RBF_LOAD_BEGIN → verification → LOADING → PLAYING.
4. TWO_LOOPS/third-traversal HALT, OFF/native continuation, Repeat One/All handoff, non-loop EOF, manual FADE_ONLY, Stop, FATAL and current-session loop/status telemetry.
5. Audio plus **all supported channel Activity**, **transparent bottom Loading**, normal menu/info, reload/loop and status/session on exact canonical Main/RBF.

Static source-graph admission and its negative fixtures remain required but do not prove this entire hardware matrix. Keep per-path pending results explicit. Release registry/payload changes, package lifecycle/install/upgrade/rollback and publication need separate scope; this document does not promote any candidate.

## 7. Continuous logical time

**Playback time is never a resource-management mechanism.**

VGM WAIT advances a continuous 44.1k logical timeline. Parser byte fetch, DDR latency, internal decode cycles, bus busy, cache miss, prewarm and scanner/Preflight preparation do not add WAIT, stop the playback clock or rebase due-time. Start logical playback only after required startup readiness; once started, resource waits cannot stretch tempo.

Frozen Scheduler assigns 64-bit due-time and sequence from accepted ordered facts. WRITE/DAC preserve their source due-time; WAIT and DAC's encoded implicit wait advance the next due-time with checked arithmetic. Source ordering and per-target physical FIFO order remain exact. Independent targets may physically accept in a different order under stalls; do not claim a physical total order that the Scheduler does not implement. DATA/END/loop barriers preserve their defined retirement/drain order.

If a bus is busy at due-time, preserve timeline/order and commit when ready; expose actual lateness. Distinguish Scheduler retirement, adapter acceptance, register-file write, native voice snapshot and sample/mix completion in traces.

- `PHYSICAL_LATENESS_WITHOUT_SEMANTIC_LATENESS`: physical acceptance late but chip-visible effect, ADPCM consumption and audio exact in the named comparison. Keep measured lateness; not automatically a blocker.
- Semantic control lateness, missed key-on/off, changed sample consumption/audio or resource race is a blocker. Supply shortage in vNext is not excused as legacy timebase migration.
- Accepted legacy internal stall elongation may be classified `INTENTIONAL_TIMEBASE_MIGRATION / LEGACY_STALL_ELONGATION` only with fixed evidence proving payload/order/logical timing exact and excluding other semantic causes.

For A's accepted SegaPCM control window: native boundary logical identity, due-time and source sequence remain fixed; apply known due controls before snapshot. If decode horizon cannot yet prove all controls due at/before boundary are known, hold physical snapshot within the existing **600-cycle control/frame deadline**. Resolve horizon generically for startup/resume/recovery/stall, without extra wait when already sufficient. Snapshot-complete frame is never aborted/rewound; post-snapshot writes affect next snapshot. Deadline overrun is explicit CONTROL_DEADLINE_FAULT/resource fault, never silent frame slip. This is an A contract, not a mandated 600-cycle budget for every chip.

## 8. Strict Reader and physical ownership

Request owns logical byte address, immutable extent, transaction and epoch; response echoes identity with `READ_OK(byte)`, `READ_RANGE_ERROR`, `READ_TIMEOUT` or `READ_CANCELLED`. Current reusable ABI is 128-bit request / 74-bit response. Numeric layout is owned by actual package/source, not redefined here.

- Check full logical address/extent before narrowing backend address. Out-of-range request is not issued physically.
- Genuine byte66 is READ_OK and may decode END; synthetic backend66 is never an EOF/fault substitute. Observer must have complete, exclusive physical provenance; fail closed if the binding cannot distinguish it.
- Track capture → command pending → physical ACCEPT → response → logical completion separately. Avalon read/address/control remain held through waitrequest; exactly one ACCEPT occurs on `read && !waitrequest` edge.
- Acceptance wait is distinct from accepted-read response timeout. Start response age after ACCEPT; a legitimate deadline-edge response wins over timeout. Any separate acceptance timeout is explicitly named.
- Cancel/reset/reload completes a logical transaction once as CANCELLED. Untagged accepted physical debt survives logical cancellation until response drain/quiescence; epoch tags alone cannot identify an old physical response.
- Never allow an old response to alias a new read. Candidate binding proves safe cancellation before ACCEPT against its real interface; after ACCEPT, drain is mandatory. Missing late response may require indefinite isolation rather than unsafe reuse. Existing ledger requires two quiet cycles; do not weaken it implicitly.

Sequential command prefetch/FIFO belongs before Parser, preserving exact bytes/PC/order, extent and strict faults. Loop refills at validated target; new epoch invalidates stale bytes. Avoid meaningless DATA_BLOCK payload prefetch. A command FIFO and a chip sample cache solve different problems.

## 9. Resource readiness and sample boundary

Preflight/Storage owns descriptors, logical resource spans, mapping, availability, cursor/seek/consume, prewarm/cache generation/protected slots and backend request ownership. Parser describes DATA_BLOCK/SEEK; Core sees logical sample addresses, not VGM file/DDR offsets.

Finish required preparation before PLAY or prefetch dynamic resources before their deadline. A due resource-dependent control cannot silently slip a native sample. No fixed delay, WAIT addition/tick gating, synthetic fallback sample or output mute may conceal missing/range/timeout/cancel. Faults are explicit and session-correlated.

Register resource ordering, later-overlap priority where required, repeated block/loop revisit, capacity, epoch/reload/stale/absent behavior and policy. Capacity exhaustion is explicit reject/fault, never truncated storage. B's prepared resource/raw-prefix shared-store ownership and ADPCM cache/protected-slot/prewarm remain engine-specific implementation evidence.

Accepted SegaPCM mapping uses logical bank offset **ADD** voice address; sparse address within declared ROM but outside every block is `DECLARED_ROM_GAP → 0x80` neutral silence, nonfatal and distinguishable. Outside declared ROM is range error; absent resource, timeout and cancel remain faults. Do not generalize this sample-format-specific gap byte to other engines. Accepted raw product/sum and output `sat16(raw19 × 2)` belong to SegaPCM Core/output contracts; no legacy per-voice clip is reintroduced. Software-reference decisions are not hardware proof of every edge case.

DAC client owns type00 span/cursor/seek/consume and resolved register2A writes. Loop continuation preserves cursor unless VGM commands reset/seek it; new track switches epoch and state. Current A one-span implementation is allowed only for its audited corpus; newly admitted multi-span use requires explicit compatibility work, not silent aliasing.

## 10. Deterministic reload and reset

**Known register state alone is insufficient.** Before first new-track write, return audible internal state to known cold-equivalent state: register/key-on, envelope/history, feedback, phase, divider/scan relationship, accumulators and output pipeline as required by the actual chip.

```text
accepted load → invalidate old epoch → reset/flush
 → reset closure + Preflight/resource readiness → arm new session → PLAY → first WRITE
```

Reset/preparation may overlap where safe; every readiness condition must complete before PLAY. Count actual chip-enable/phase closure, not only wall-clock reset cycles. Retained divider/scan state may require deterministic phase release. One-shot/armed/done state rearms per accepted epoch. Cancel/drain physical debt without importing stale samples into the new track.

Test cold, same-track reload, repeated reload (including x2/x5), different-track, stop→reload and loop→reload across accepted latency profiles. Compare initial and relevant ongoing audio/ADPCM/native state. No startup mute/output-zero/fixed compensation may conceal residual state. B's 160-enable flush plus retained-phase closure is evidence for JT10 binding; it is not a universal chip reset count and does not modify JT10 semantics.

## 11. Production UI ABI

### Channel Activity OSD

All-channel Activity is **REQUIRED_FOR_STATUS_ABI / production UI**, never DEBUG_ONLY or MEASUREMENT_ONLY. Each Core/Adapter provides stable channel identity/order, active state and reset/valid semantics for every supported channel. Activity is chip-derived; OSD renders generic representation without key-on/envelope/sample-policy knowledge. Verify inactive reset, new-session validity, all-channel mapping and simultaneous display with Loading/menu. Engine completion requires exact-artifact **hardware PASS** for all supported channels.

### Transparent bottom Loading

Main command **0x47** selects transparent INFO/Loading: receiver sets `info=1`, `info_transparent=1` and retains Main's x/y/w/h. Main geometry is authority; FPGA does not select a hardcoded bottom position. The existing wire ABI uses x/y coordinates and 8-pixel-cell w/h; captured `(8,230,28,1)` renders `(8,230,224,8)`. Respect actual rotation/scaling conventions, not an invented new geometry ABI.

Progress bitmap/ordinary padding commands must not overwrite geometry/transparency accidentally. Explicit normal menu/info commands may intentionally select their established mode. Loading end clears/disables cleanly, including transparent state, while normal menu/info and Activity continue correctly.

Static/26-command replay/pixel PASS is not real-device completion. B's prior Loading FAIL_REOPENED findings and identical Main command streams remain historical evidence. DAI confirmed transparent bottom Loading for the two exact A/B RBF hashes in the [hardware-accepted candidate ledger](MegaVGMPlayer_CURRENT/VNEXT_HARDWARE_ACCEPTED.md) on 2026-10-08. This closes the observed Loading hardware failure for those artifacts only; it does not grant every earlier/later source profile the same result or complete full production admission. Later selected RC receipts are centralized in §13 and retain their explicitly reported scope.

## 12. FPGA implementation and profile discipline

**Behavioral correctness alone is insufficient for FPGA implementation.**

Measure target/total queue occupancy, same-time bursts, stalls and deadline/backpressure before choosing capacity. Simulation stress capacity is not a production default. A/B depth8 is measured implementation evidence, not a mandatory capacity for every engine.

Prefer inference-compatible synchronous RAM/store when semantics permit. Audit reset/read-during-write, registered port latency and consumer adaptation; confirm actual M10K/BRAM inference in Windows reports. Large parallel mux/CAM requires measured need. B prepared store retains 256 words; logical modularity must not accidentally create duplicate storage/execution paths. Do not optimize the Golden backend or chip semantics to repair an unrelated inference issue.

Review hierarchy ALUT/register/RAM/DSP, total ALM/LAB, fit and timing on exact toolchain. Structural estimates cannot be summed into guaranteed ALMs or hardware fit. Size latency absorbers from measured demand/service; arbitrary600-cycle sustained sixteen-voice support is not presumed feasible. A sample-cache decision remains hardware-DDR-measurement dependent unless exact telemetry proves a new bound.

Production profiles may exclude proven measurement/differential observers, not functional ordering/epochs/ledger/deadlines, fault/status or required Activity/Loading. PC/sequence/transaction fields may be functional; inspect consumers rather than stripping by name. Preserve frozen ABI unless explicitly reviewed. Profile equivalence excludes only permitted observations and still requires all production UI.

For A/B/C/D/E and future engines, Pre-Quartus READY requires the Runbook's [Human-facing Build Artifact Contract](MegaVGMPlayer_Engine_Bringup_Runbook.md#human-facing-build-artifact-contract): extract ZIP → open the root canonical QPF in Windows Quartus GUI → Full Compilation → inspect `output/`. `BUILD.bat` is optional and excluded from READY/PASS; helper failure is separate from canonical QPF build failure. This changes no engine semantics or source graph.

## 13. Current evidence and authorities

The [v2.4.0 Architecture Refresh RC](MegaVGMPlayer_vNext_Integrated_RC/README.md) and [adoption manifest](MegaVGMPlayer_vNext_Integrated_RC/release/v2.4.0/adoption-manifest.json) centralize current selection. They preserve independent Engine builds; no combined A+D core or new sound chip is introduced. Exact RBFs were explicitly accepted by DAI in the reported scope. No new hardware test is performed by documentation/integration work.

| Engine | Selected implementation/config | Windows evidence | User-reported hardware scope |
|---|---|---|---|
| A | A1+A2 `b4e1b9c`; evidence `a1fc3cb`; seed1 | 23,503 ALM / 3,705 LAB / 85 M10K; constrained all4corner PASS, setup +0.088ns, TNS0 | Audio, PWA startup, transparent bottom Loading, Activity, track switching |
| B | `99d4928`; seed3 `2241e0f`; evidence `b7a001d` | 31,787 ALM / 3,995 LAB / 84 M10K; constrained all4corner PASS, setup +0.467ns, TNS0; two independent matching Full Compilations | Audio, PWA startup, track switching |
| C | Stable `82402ec`, unchanged accepted RBF/native-cycle SID | Original producing build not recovered; no new all-corner/build-reproducibility claim | Retained stable audio/PWA acceptance |
| D | `26d5078` | 22,074 ALM / 3,700 LAB / 79 M10K; constrained all4corner PASS, setup +0.495ns, TNS0 | YM2151/C140 playback, PWA startup, transparent bottom Loading |

Full SHA256/size, immutable Build Artifact references, producing source commits, warning/constraint limits and receipts belong to the manifest rather than duplicated hash tables. A/B/D Common Parser/Reader/Scheduler inputs are byte-identical for the compared ten graph files. Engine-specific binding/parameters differ. D's pinned Transport owner variant is retained; reuse does not imply all integration files are identical. C remains outside the Common VGM Parser/Scheduler path.

The former A `da862ee` timing failure is not waived: its RBF/reports and original BLOCKED audit remain in `MegaVGMPlayer_vNext_Integrated_RC/history/96edaa2`; selected A1+A2 supplies new passing evidence. The [older A/B hardware ledger](MegaVGMPlayer_CURRENT/VNEXT_HARDWARE_ACCEPTED.md) retains its exact artifact history. Existing v2.3 [BUILD_TARGETS](MegaVGMPlayer_CURRENT/BUILD_TARGETS.md) and [release authority](MegaVGMPlayer_vNext_4Engine_RC/release/final_authorities.json) are unchanged.

Long-duration/full-asset/full admission are **NOT_RUN / not claimed**. A/D independent bit-identical rebuilds are NOT_RUN; C has legacy provenance limits. Inherited external-I/O constraints/warnings are disclosed; constrained all-corner PASS is not complete external-I/O signoff. Required Activity/Loading/Transport/status semantics remain mandatory even when a newer receipt lists only a narrower tested scope. RC selection changes no RTL, Runtime/PWA/Main, installed RBF or public release.

## 14. Historical release evidence

Legacy A/B/C/D v2.3 audio/UI/switch acceptance and older D6/D7 details remain exact-artifact history, not new vNext measurements. Full previous Contract/Runbook snapshots are preserved in [documentation history](MegaVGMPlayer_Documentation_History/20261007-vnext-refresh/README.md); release manifests retain payload identity. Old B local FPGA-indefinite loop wording and old C local naming were individually resolved by DAI; local files remain untouched and unrelated conflicts still stop work. A/B vNext software-reference differences remain scoped in their evidence, never generalized to unrelated audio differences.
