# MegaVGMPlayer vNext Engine Bring-up Runbook

Updated: 2026-10-09. Procedure subordinate to [AGENTS](AGENTS.md), [Platform Contract](MegaVGMPlayer_Platform_Contract.md) and [Engine Contract](MegaVGMPlayer_Engine_Contract.md). If reached directly, read documents 1–3 **in full and in order**, then this Runbook in full, before source work. Missing/unreadable authority or unresolved conflict stops work. [START_HERE](MegaVGMPlayer_START_HERE.md) is the human index.

This procedure uses actual source/evidence rather than prior chat or DAI's memory. It does not authorize protected source changes, Windows compilation, deployment or publication. REQUIRED describes a gate; PROVEN must name static/simulation/Windows/hardware scope; TBD/NOT_RUN/FAIL_REOPENED must stay explicit.

## New Engine Plugin workflow

For C/D/E/F/G/NES/PCE, use this sequence and the Engine Contract's ownership boundaries. SID/MVGMSID uses its separate prepared-format path; do not force it through Common VGM grammar.

1. **Bootstrap/authority.** Read the four documents; inspect BUILD_TARGETS, actual worktree/branch/HEAD/status and protected boundaries. Select an explicitly authorized isolated candidate. Existing production targets are not inferred from names; copying an old entire chip project is not architecture reuse.
2. **Chip specification.** Establish actual command/header/chip semantics, software references and hardware evidence. Record specific disagreements and accepted decisions with fixture/hash/first divergence. Missing chip facts stay TBD; do not invent them.
3. **Plugin scope.** Reuse Golden shell/upload/backend/status/Transport and vNext Parser/Reader/Scheduler. Define thin Adapter/Core/Storage/Output responsibilities, ABI, reset/epoch and supported variants. Freeze unchanged semantics/source hashes.
4. **Grammar coverage.** Walk admitted production assets with correct grammar lengths/spans and current source. Distinguish cases present in source from opcodes used in assets. Mark required implemented/explicit reject/TBD. Generic grammar extension requires review; never infer positive support from opcode existence. Future unknown opcodes may need a new approved extension.
5. **Preflight decision.** If compatibility/descriptors/resources/variant are needed before sound, run Common Parser PASS1 and validate all preparation before PASS2. Reject emits zero audible writes. Required prewarm/reset readiness precedes logical playback start.
6. **Minimal implementation.** Thin chip adapter translates generic WRITE and ready/busy only. Core implements chip semantics; Storage owns logical mapping/cursor/cache/read ownership; Output declares arithmetic and common boundary. Preserve existing accepted chip cores where reused. No Parser policy/state leakage.
7. **Activity/UI/status.** Implement channel identity/order/active/reset/valid metadata and generic OSD attachment. Retain required Activity, transparent Main-directed Loading, status exporter/readback, CORENAME and ioctl ownership. Observation must not affect audio/control timing.
8. **Tiered verification.** Establish smoke, production checkpoints, historical deep/full and lifecycle/fault/negative controls. Verify due/sequence, native effects, sample/address/audio, loop/reload and explicit fault behavior. Investigate new differences before allowlisting.
9. **Resource audit.** Measure occupancy/descriptors/bursts/stalls/deadlines and sustained demand. Choose smallest proven capacity plus reasoned margin; inspect RAM inference/mux/duplication and profile observability. Do not import simulation stress sizing into production.
10. **Compatibility/graph.** Run the complete Quartus Compatibility Gate below on exact macros/types/settings/graph; Icarus/Verilator alone is insufficient.
11. **Build Artifact.** Commit validated inputs, exact-copy canonical configuration, generate deterministic ZIP and independently validate fresh extraction. A source-only directory export is not READY.
12. **Windows build.** Only after explicit authorization, extract exact ZIP, open its root canonical QPF in the named Windows Quartus GUI and run Full Compilation. Record synthesis/map/fit/timing/warnings and generated RBF/hash. No Windows patch.
13. **Hardware completion.** On exact Main/RBF: audio, every supported Activity channel, transparent bottom Loading, menu/info, cold/repeated/different-track/loop reload, loops/EOF/fault/status/session. Pending UI is not covered by audio PASS.
14. **Production admission.** Run Engine Contract admission and generic Player transitions, then separately authorized registry/package/install/upgrade/rollback/promotion. No engine-name Platform branch or automatic release.

At each stage, stop on a new unexplained semantic difference or concrete failing required gate. Continue independent work where its inputs are established; do not spend Fitter time on a reproducible source/test failure.

## Current implementation and evidence map

Paths below resolve under `/Users/daizo/Projects`. They locate implementations; they do not make a later HEAD an accepted RBF source. Current hashes/status are recorded once in [Engine current evidence](MegaVGMPlayer_Engine_Contract.md#13-current-evidence-and-authorities).

| Concern | Actual implementation / evidence |
|---|---|
| Common grammar/facts | `MegaVGMPlayer_ParserVNext/rtl/vgm_parser_vnext/`; `docs/evidence/parser_vnext/phase1` through `phase6`, Core completion evidence; `tb/vgm_parser_vnext/compare/` |
| Strict byte ownership | same root `rtl/vgm_reader_vnext/{reader_pkg,golden_observer,strict_adapter}.sv`; `docs/evidence/parser_vnext/phase5/README.md`; `tb/vgm_reader_vnext/run.py` |
| Continuous timeline | same root `rtl/vgm_scheduler_vnext/`; `docs/evidence/parser_vnext/phase6/README.md`; `tb/vgm_scheduler_vnext/run.py` |
| Loop resume / DAC client | same root `rtl/engine_a_vnext_integration/loop_continuation_client.sv`, `ym2612_dac_client.sv`; `docs/evidence/engine_a_vnext/phase10a/` |
| A control/supply | same root `rtl/engine_a_vnext_integration/`; `docs/evidence/engine_a_vnext/phase9b/`, `phase9d/`, `phase10b/`, `phase10c/` |
| SegaPCM Core/resource/output | same root `rtl/segapcm_vnext/`; `docs/evidence/segapcm_vnext/README.md`, `phase8/` |
| A measured capacity / profile limits | same root `docs/evidence/engine_a_vnext/capacity_rightsize/`, `production_trim/`; measurement QPF vs derived production profile must be distinguished |
| B PASS1/PASS2 / lifecycle | `MegaVGMPlayer_EngineB_vNext/rtl/engine_b_vnext/`; `tools/engine_b_vnext/run_phase1.py`, `run_reload_lifecycle.py`; `docs/evidence/engine_b_vnext/phase1/`, `phase2/` |
| B raw prefix and arbitration | same root `tools/engine_b_vnext/prefix_arbitration/`; `docs/evidence/engine_b_vnext/phase2/loop-prefix-proof/`, `prefix-arbitration-low-water/` |
| B reset and accepted tier | same root `docs/evidence/engine_b_vnext/phase2/reload-reset/`, `reload-lifecycle/`, `final-playback-scoped-b42/` |
| A A1+A2 measured closure | `MegaVGMPlayer_EngineA_Opt_A2/docs/evidence/engine_a_vnext/optimization_a2/`; `output/EngineA_vNext_Optimization_A2_b4e1b9c_20261009/`; exact selection in v2.4 manifest |
| B prepared tag/Timing optimization | `MegaVGMPlayer_EngineB_vNext/docs/evidence/engine_b_vnext/prepared-store-tag-sharing/timing-seed3/`; seed3 config and two-build evidence |
| D vNext | `MegaVGMPlayer_EngineD_vNext/`; `MegaVGMPlayer_vNext_Integrated_RC/audit/D-timing-review.json`; exact Build Artifact in v2.4 manifest |
| B prepared RAM | same root `rtl/engine_b_vnext/prepared_word_store.sv`; `tools/engine_b_vnext/prepared_ram/run.py`; `docs/evidence/engine_b_vnext/prepared-store-sync-ram/` |
| Activity/Loading replay | same root `tb/engine_b_osd/`; `docs/evidence/engine_b_vnext/osd-loading-contract/`, `root-handoff/` (historical reopened gate); exact current hardware acceptance is in the candidate ledger |
| Formal Build Artifact | same root `build_artifact/engine_b/`; `tools/engine_b_vnext/assembly/{build_artifact,test_build_artifact}.py`; `docs/evidence/engine_b_vnext/build-artifact/` |
| Clean active closure | same root `docs/evidence/engine_b_vnext/worktree-cleanup/`; local quarantine manifest linked there |
| Main/status path | `Main_MiSTer-megavgm-bottom-loading/{menu.cpp,osd.cpp,user_io.cpp,megavgm_status.cpp,fpga_io.cpp}` |
| Player/switch path | `MegaVGMPlayer_vNext_4Engine_Runtime/tools/megavgm_{profile,playlist,supervisor,autoplay2}/` |
| Registry/release checks | `MegaVGMPlayer_vNext_4Engine_RC/release/{production_engines,final_authorities}.json`, `tests/production_engine_admission_gate.py`, `tests/test_production_engine_admission_gate.py` |

Inspect runner options/manifests at the actual selected HEAD before reuse. Baseline hash guards and external fixture requirements may make old scripts snapshot-specific; do not weaken those checks to get a PASS. B retains production scanner/JT10/cache historical oracles at stable paths. A historical production-minimal profile removing Activity is not a valid all-UI completion template.

## Golden integration checkpoints

Use existing common path, without reimplementing it:

```text
owned Controller request → SwitchOwner PARKED → resident FADE_ONLY/ENDED
 → successor Main/RBF verification → pre-upload status → READY lease
 → generated index-1 upload → Golden DDR fence → prepared/reset-ready engine → PLAYING
```

`PARKED` precedes fade; public host LOADING may precede physical upload. Main transfer success, FPGA load fence, grammar/admission PASS and audio readiness are different observations. Session zero applies to fresh RBF admission; same-engine reload uses current baseline+1.

- Main `mister_cmd_load_file` / `user_io_file_tx` and `hps_io` retain index/session/backpressure. Selected engine edges filter index1; shared Transport owns index2. Verify control transfer during playback cannot reset upload/Core.
- Golden backend flushes partial packing/FIFO and pending writes before load-ready. Never start from last host chunk alone or add a competing physical DDR writer.
- Reader binding observes logical issue, held Avalon command/ACCEPT, response and reset/load/epoch; owner retains physical debt through cancellation. Prove response timeout starts after ACCEPT and no stale alias.
- PASS1 prepares engine resources/descriptors/raw prefix where needed. PASS2 replays data start through the same Parser; no audible write before validation/resource/reset readiness.
- At playback boundary, Transport decides CONTINUE/HALT; continuation resumes validated loop PC without track/resource reset. Prove no third resume on TWO_LOOPS HALT and no loop policy inside Parser/client.
- Status exporter must be instantiated/readable independently of upload before CORE_VERIFY_SUCCESS; preserve current-session DONE/FATAL and late-observer behavior.

Generic Runtime mapping/schema extension audit, when separately authorized: stable Profile/wire IDs and guards, classifier/CLI, RBF/name maps, switch supported-profile lists, Controller resident mapping, Remote receipt/TS/chip vocabularies, registry, package target inventory and lifecycle fixtures. Preserve generic algorithms. Current finite A–D lists do not imply that an unknown engine is already supported. Install/upgrade/rollback consume one authority inventory; do not invent a second packaging/switch algorithm.

## Regression tiers and difference management

| Tier | Use and required scope |
|---|---|
| Tier 1 — smoke | syntax/elaboration, basic event/bus/audio, unit/reset/fault checks on each relevant edit |
| Tier 2 — representative/checkpoint | current production corpus through pinned windows/hashes/checkpoints, loop/reload/epoch, due/order/resource readiness; normal recurring regression |
| Tier 3 — deep/full | historical bug/heavy tracks, full traversal or documented deep window, newly divergent tracks; retain accepted expensive evidence |

Do not require millions of samples for every asset on every edit. New differences promote the affected track to Tier3; prior matching tracks need not all become full reruns. Preserve exact coverage counts, omitted spans and acceleration/clock-skipping limits. Source changes invalidate affected evidence even if a fixture name is unchanged.

B's accepted example is **40 completed full +55 scoped** among95 assets, not 95 full traversals. Scoped loop fixtures prove raw-prefix/control supply with unchanged ROM and terminal setup; they do not reconstruct original whole-track waveform state. Historical deep gates include Stage6/DariusII/GF09; Aquarius, Daddy Mulk, Metal Slug and reload cases retain their specifically named windows. These scopes are evidence, not a universal sample-count quota.

Compare at minimum PC/opcode/raw operands, WRITE identity/payload/order, logical due/sequence, actual bus acceptance/native effects, ADPCM/sample consumption and audio, resource/cache ownership, loop/terminal and reload epochs. Report physical lateness separately from semantic/audio lateness. All valid shared grammar is EXACT_MATCH; unexpected semantic/audio differences are blockers. `PHYSICAL_LATENESS_WITHOUT_SEMANTIC_LATENESS` requires positive effect/consumption/audio evidence, not just identical WRITE bytes.

Keep approved malformed truncation/arithmetic/extent/diagnostic-attribution and specific production/reference/timebase differences fixture/hash/reason-bound. Do not manufacture out-of-range reads/synthetic66 to emulate legacy faults, silently extend allowlists or use hash agreement alone to explain an unknown divergence. Store first differing cycle/native index/state plus exact source/fixture identity.

For every relevant suite retain deterministic rerun and comparator/mutation negatives; explicit missing/range/timeout/cancel/deadline faults, reject audible-write zero, reload/cold equivalence and no stale response. Preserve Golden8 WRITE / WAIT92,610 and existing grammar coverage. Common2,005 comprises PSG132/FM240/DATA258/DAC255/Core282/completed-profile132/Reader370/Scheduler336; it is a named accepted baseline, not a requirement that future suites never grow.

## Resource and latency audit

Measure before optimizing:

- Per-target/total occupancy, initialization and same-time burst, backpressure/stall backlog, bytes/requests per frame, resource/live descriptors and overlap priority.
- Acceptance stall, accepted-read→response latency and total logical service latency separately; native-frame cycles/minimum deadline margin; semantic key-on/control lateness.
- Worst sustained traffic including all voices, unrelated/adjacent regions, high/low delta, loop/bank boundary and parser contention. Derive bandwidth feasibility before cache/runway sizing.

A's measured integration used Scheduler DEPTH8 with backpressure, not a promise of an empty queue slot. Its resource map retains32 regions because16 live spans needs safety margin. B chooses its own measured capacities. Do not shrink until ordering/deadline/overflow proofs pass.

Inspect inference: asynchronous array reads, multi-read ports, all-entry compares/CAMs, reset/clear and read-during-write often dominate physical resources. Wide structs alone are not the diagnosis. Prefer a single explicit synchronous RAM port and validity/epoch invalidation when semantics allow; compare external read latency before/after and prove prefix/resource consumers unchanged. B's256-word prepared-store repair isolated the inferred RAM process without changing external response timing; its cache and Scheduler were not rewritten.

Windows `.map/.flow/.fit/.sta` reports determine actual hierarchy ALUT/register/Block Memory/DSP, ALM/LAB and timing. No claim that estimated bit savings guarantee Fitter or that total resources are one-third before synthesis. Review duplicates and debug fanout before changing Core semantics/Golden backend. Recompile on Windows only with explicit build authority.

For A, no-cache L24/frame587/margin13 and L25 explicit fault are historical synthetic conditions; later binding/prefetch evidence has its own envelope. Do not call either measured hardware DDR latency. Arbitrary600-cycle sustained high-delta sixteen-voice service was bandwidth-infeasible; cache decision remains `DEFER_UNTIL_HARDWARE_DDR_MEASUREMENT` absent new evidence. Observation-only telemetry may record acceptance/response maxima/histogram, requests/frame, resource hits, frame cycles/margin, C0/sample deadline faults; it cannot feed scheduling decisions. Use existing bounded OSD/debug path, not a second renderer. Required Activity/Loading is never telemetry to trim.

## FPGA Resource Efficiency — measured lessons

These are scoped successful implementation cases, not guaranteed savings for a future engine:

- A1 preserved descriptor priority/response semantics while balancing resource-map selection: the reported sample-address path fell from 127 to 27 logic levels. This fixed the core violation but did not by itself close remaining HDMI Timing.
- A2 retained A1 and omitted only proven inactive smoke FIFO-head observations in the production-minimal profile. Asynchronous diagnostic address/BE reads had blocked inference despite dead final consumers. Restoring 25,856 bits / 3 M10K reduced total resources by 12,077 ALM and 485 LAB versus A1. The global smoke define also controls functional configuration, so deleting the whole define was not a safe equivalent fix.
- B used synchronous prepared data/indexed metadata RAM and shared the proven nonconcurrent preparation tag query/fill comparator bank. Capacity 256, raw-prefix replay, class/epoch/priority and playback cycles were retained. Its remaining live cache is functional, not automatically redundant with prepared storage.
- B seed3 closed constrained Timing and independently reproduced resource/Timing/RBF twice. A A2 is one measured full build. Do not generalize one successful seed or inference pattern into a guaranteed fit.

Audit effective defines and every consumer/read port before blaming RAM reset/width. Confirm real inferred RAM in map/fit, not a ramstyle annotation. Evaluate large mux/parallel searches against actual concurrency/deadlines; serialize preparation-only work only when its ownership/latency permits. Avoid unnecessary parallel CAM and duplicated metadata, but preserve required tag searches and priority. Compare ALM,LAB,registers,M10K,DSP,packing/routing,Fitter time and Timing separately. Parent/child inclusive hierarchy figures must not be summed. Lower ALM alone does not prove lower LAB or better Timing. New optimizations remain diagnostic candidates until measured and validated.

## Quartus Compatibility Gate

Run on exact selected source/macros/includes/settings before presenting a Build Artifact as READY. Icarus/Verilator/simulation PASS alone is insufficient. Static screening is a risk review, not a replacement for the Windows compiler.

### HDL review

- Procedural statements belong inside procedural/function/task blocks, not module scope. Use explicitly declared `genvar` and `generate/for/endgenerate`; do not rely on ambiguous implicit generation/inline constructs.
- Check begin/end, function/task/generate closures and active ifdef nesting.
- Register package/typedef definitions before consumers; declare named typed signals before use, including instance connections. Verify actual struct-prefix type/import/width/layout.
- Audit member-select on function returns, casts, nested structures and array elements. Use a named explicitly typed temporary where Quartus resolution is fragile; never change ABI to fix syntax.
- Separate inherited/vendor warnings from new findings. Review every unresolved pattern with exact source hashes. Regex screens have false positives and omissions; no auto-fix or inferred synthesis PASS.

Historical lessons: A `functional_engine.sv` implicit-generate failure required explicit syntax; `.kind/.block_type` failures were forward-declared named struct prefixes, not proof of an invalid event ABI. Preserve semantic traces on compatibility repairs.

### Settings and graph review

- Check actual Quartus edition/version. Validate global **and instance** settings; no `OUTPUT_BASE_FILE` assignment. Project/revision and supported output settings determine candidate identity.
- Preserve top, family/device, revision, output directory/RBF setting, clocks/pins/options, defines and package/source order. Distinguish legitimate additive assignments from conflicting singleton/duplicate source settings.
- Traverse QPF→QSF→QIP/Tcl→RTL/includes/ROM/MIF/HEX/IP/pre-flow assets. Inspect active implementations and macros, no stale lab or duplicate execution path. Source registration alone does not prove live hierarchy.
- Classify editor-only templates and pre-flow-generated inputs explicitly; missing required synthesis input blocks READY. Deterministic generation path is required for generated build assets.
- Resolve paths inside the Artifact; no absolute source path, parent dependency or external repository. Tool installation paths are not source inputs.

### Ordered READY checks

1. Record worktree/branch/HEAD/dirty state, protected hashes, scope and target identity; run `git diff --check`.
2. Icarus syntax and relevant elaboration, Verilator lint, actual functional hierarchy elaboration/simulation with active graph. Name simulator/IP limitations and reviewed alternate evidence; an empty top is not full elaboration.
3. Current-tier engine/Common/interface/UI/lifecycle/loop/reload/fault regressions; deterministic and negative controls; valid equivalence/no unexpected difference.
4. Measured sizing/resource/inference review and static Quartus compatibility, with findings resolved/reviewed rather than hidden.
5. Complete graph/settings/order/hash checks; commit validated build inputs.
6. Generate the exact-copy deterministic Build Artifact; independently fresh-extract and verify the contract below.

Failed required checks, unreviewed risks, dirty build inputs or mismatched hashes block READY. Earlier evidence must apply to current exact source; do not rerun unchanged expensive suites without cause. READY does not authorize Quartus or imply fit/timing/hardware/production PASS.

## Human-facing Build Artifact Contract

**Required for A/B/C/D/E and all future F/G/NES/PCE engines.** This replaces the source-handoff operating model. Historical exports remain evidence only.

Principles: **artifact root is the human interface**; internal topology is hidden under `source/`; root-visible canonical QPF/QSF; no directory archaeology or hand editing.

```text
MegaVGMDrive_B_vNext_RC.zip       # no enclosing directory inside
├─ MegaVGMDrive_B_vNext_MiSTer.qpf # sole human-facing QPF
├─ MegaVGMDrive_B_vNext_MiSTer.qsf
├─ HANDOFF.txt
├─ SHA256SUMS.txt
├─ ARTIFACT_MANIFEST.json
├─ BUILD_INFO.txt
├─ source/                       # exact selected RTL/includes/IP/build assets
└─ output/                       # empty initially; RBF/reports after Windows build
```

Canonical Windows workflow: **Extract ZIP → open the sole root canonical QPF in Quartus GUI → Full Compilation → inspect output/**. No internal revision hunting. Minimum root contents are canonical QPF/QSF, HANDOFF.txt, SHA256SUMS.txt, `source/` and `output/`; manifest/build-identity files remain required by the current generator. Adapt project/engine names for other candidates, retaining distinct candidate vs deployed production identity.

Canonical root-ready QPF/QSF/QIP/configuration Tcl are committed Mac source files. Generator copies exact bytes, never rewrites commands/paths, quotes option tokens, synthesizes settings or reserializes interpreted Tcl. Read-only traversal/evaluation is required for validation, not configuration emission. Configuration changes are reviewed source changes with validation/commit before export.

Every required reference resolves by relative path inside build root. Include only exact graph inputs and build-required pinned/vendor data, not corpus/testdata/evidence/logs/Git/old RBF/previous output or alternate QPFs. Document deterministic pre-flow-generated inputs/tool version/seed/date. Stable ZIP order/timestamp/mode and repeat-generation checks establish source-archive reproducibility; they do not prove bit-identical RBF across tool/OS versions.

`BUILD.bat` and any bundled runner are optional helpers. They may remain in existing/new artifacts, but presence, execution and success are not READY/PASS requirements. A helper failure must be reported separately and does not constitute canonical QPF compilation failure; use Quartus GUI. Helpers must not require source edits. B currently targets Quartus17.0 Lite; future artifacts name their actual supported version.

HANDOFF begins:

```text
1. Extract ZIP
2. Open the root canonical .qpf in Quartus GUI
3. Run Full Compilation
4. Check output/ for RBF and reports
```

Then project/revision, expected RBF, source commit, external ZIP checksum location and Windows-only/no Mac Quartus/no Windows patch instructions. Do not lead with repository internals.

SHA256SUMS covers every regular member **except itself**. External `<artifact>.zip.sha256` covers the whole final ZIP including checksum/directory entries. Do not embed a fictitious self-referential final ZIP hash; HANDOFF points to its companion. Manifest maps packaged input to original path/hash and exact source/config/tool identity.

### Fresh-extract validation

Extract the final ZIP to an empty temporary directory, not just inspect staging. Automatically prove:

- Root QPF/QSF/HANDOFF/SHA presence (BUILD.bat is optional), sole QPF, no wrapper directory and output directory.
- Revision/top/device/defines/package/source order/settings/pins match canonical authority, configuration bytes exact.
- Complete QPF/QSF/QIP/Tcl/source/include/asset closure: missing=0, duplicate=0, absolute source paths=0, parent/external dependencies=0, stale lab input=0.
- Every member checksum and external ZIP checksum, no unexpected source/evidence/build output. Final committed input hashes match manifest; deterministic repeat ZIP agrees.

A candidate requiring “QPFどれ？” / “フォルダどこ？” or manual source edits is FAIL. Existing A historical exports must migrate to this root contract at their next assembly; do not claim they already conform merely because B does.

### Windows build and result evidence

After separate authorization, use a fresh extraction. Windows Quartus 17.0.0 Build 595 may also be driven over SSH: Mac source freeze → immutable Artifact transfer/hash verification → isolated Windows build → map/fit/STA/RBF/report recovery → Mac hash verification → separately authorized hardware acceptance. Windows remains build-only; never patch its RTL/QSF/QIP or overwrite an accepted RBF. Record executable/tool, build root, project/revision, all input hashes, Fitter seed and output identity. An independent rebuild is performed when required; otherwise label NOT_RUN, not reproducible-by-assumption. Open the root canonical QPF in Quartus GUI and run Full Compilation; early Analysis/Elaboration/Synthesis may be used to return cheap failures before Fitter. Record source/Artifact SHA, project/revision/tool edition/version, analysis/map/fit/timing, warnings/errors and output bytes/full hashes. Preserve reports under output, at least RBF, fit summary, flow report and timing report when generated.

Correction flow:

```text
Windows log + exact input identity → Mac fix → validation → commit
 → fresh validated Build Artifact → Windows build
```

An optional BUILD.bat/helper failure is not evidence that the canonical QPF build failed. No Windows-only patch or adoption of its RBF. Failed/no-output build must not attribute an old RBF to itself. An optional preserved `<candidate>_RC_Result/` contains RBF, BUILD_INFO, SHA256SUMS and reports; it is a result, not source authority or automatic promotion. Mac Quartus is prohibited.

## Quartus all-corner Timing gate

Flow/Fitter Successful is not Timing PASS. Save setup,hold,recovery,removal and pulse-width results for all four named timing corners, worst slack,TNS and violating endpoints. Review clock definitions/relationships, SDC application/unmatched filters and unconstrained I/O; disclose inherited limits rather than declaring complete external-I/O signoff. Record seed and packing/routing effects; no false-path/constraint relaxation to conceal a real failure. Keep resource reduction and Timing acceptance as separate gates. Independent same-input/same-seed reconstruction is evidence only when actually performed.

## Hardware and production acceptance

Follow [Engine admission](MegaVGMPlayer_Engine_Contract.md#6-production-engine-admission), not an audio-only smoke. Record exact Main/RBF hash, source/Artifact/build binding, representative/historical audio, every supported Activity channel, transparent Main-directed bottom Loading, normal info/menu, loop/fade/EOF/Stop/FATAL, cold/repeated/different/loop reload and status/session. Apply generic PWA/Controller same-/cross-engine matrix and separately authorized release lifecycle gates.

Earlier exact A/B RBF receipts remain in the [historical candidate ledger](MegaVGMPlayer_CURRENT/VNEXT_HARDWARE_ACCEPTED.md). Current A A1+A2 / B seed3 / unchanged C / D vNext selection, Windows evidence and scoped hardware acceptance are in the [v2.4 manifest](MegaVGMPlayer_vNext_Integrated_RC/release/v2.4.0/adoption-manifest.json). Preparation-time NOT_RUN labels inside immutable older Artifacts are historical, not rewritten; later exact-RBF receipts are separate evidence. PWA startup/switching, audio and the explicitly reported UI checks do not imply long-run/all-track/full-admission completion. The RC retains C's legacy project/source snapshot without claiming a newly migrated root-QPF Build Artifact. New or reassembled builds still follow the standard root contract.

## Troubleshooting at the boundary

| Symptom | First evidence / boundary |
|---|---|
| CORE_VERIFY failure | successor identity/argv, CORENAME, exporter hierarchy/readback/reset, repeated pre-upload IDLE; no verification bypass |
| upload/read timeout | Main witness vs backend fence, index filters, held Avalon request/ACCEPT, response provenance/drain; no second uploader or synthetic EOF |
| horizon/key-on native slip | source bytes/due/sequence, parser supply, resource/prewarm readiness, queue visibility, RF/snapshot ordering; do not classify a new supply fault as legacy migration |
| loop-only divergence | validated target/raw prefix continuity, prepared-store arbitration/ownership, due boundary and CONTINUE/HALT; no prepared-event bypass/tick compensation |
| reload-only audio | cold/reload enabled reset, retained divider/scan, envelope/feedback/mix pipeline and lifecycle rearm before first write; no mute/fixed delay concealment |
| Fitter exceeds capacity | hierarchy map/fit resource, duplicate execution, RAM inference, actual queue/descriptors/debug consumers; do not guess Core is culprit |
| Loading center/opaque | established Main stream → actual built osd hash → info/transparent/geometry retention/clear/render; audio PASS does not close UI |
| new engine not selected | scoped classifier/profile/schema/registry vocabulary and static admission; no generic switch algorithm or PWA branch |

For a shared regression, provide exact accepted/candidate provenance and reproducer, then obtain applicable protected-layer scope. Evidence is not authority for an independent infrastructure fork.

## Worktree hygiene and recovery

Apply [AGENTS classification](AGENTS.md#worktree-hygiene). Start from exact Artifact origin graph, then current executable test/tool/source manifests/includes/imports, fixtures, canonical authority and vendor/license dependencies. Distinguish immutable historical hash inventories from live consumers; neither names nor text hits alone prove safe removal.

Before removal, create local external quarantine, per-item source/destination/size/SHA/tracked/reason/recovery and full classification. Preserve dirty/untracked user diagnostics and unknown ownership. Verify archive hashes and tracked recovery against baseline Git. Do not delete submodule/worktree Git metadata or blanket clean/reset/prune.

After cleanup: current-tier Common/Preflight/playback/historical loop/reload/UI, compatibility/elaboration, exact build-input/hash/graph comparison, fresh Artifact/extraction, determinism/negative controls and diff checks. Commit only scoped dead-material/docs/tool changes. Report counts/bytes/top-level before/after and archive manifest. No semantic/capacity changes. Generated test outputs stay in fresh scratch; formal artifacts follow policy. B cleanup is an example, not permission to discard another engine's accepted oracle.

## Historical appendix and open gates

The complete former five documents, original hashes and before/after audit are retained in [20261007 documentation history](MegaVGMPlayer_Documentation_History/20261007-vnext-refresh/README.md). This preserves older D6/D7 acceptance, four-engine mapping audit and release snapshots without making them the vNext implementation template. Existing [BUILD_TARGETS](MegaVGMPlayer_CURRENT/BUILD_TARGETS.md), release registry and final_authorities retain v2.3 identity; no release assets are changed here.

Resolved documentation conflicts: old chip-native parser authority vs Common facts; legacy stall timing vs continuous time; indefinite-local-loop wording vs shared Transport policy; stale Platform artifact snapshots vs release registry; Activity-as-debug vs mandatory UI; simulation Loading PASS vs reopened hardware gate; repository-depth exports vs root Build Artifact; all-assets-full regression vs explicit tiering. Individually authorized local exceptions do not suppress unrelated conflicts.

Current integration status and remaining limitations are centralized in the [v2.4 RC](MegaVGMPlayer_vNext_Integrated_RC/README.md). The original A Timing blocker is resolved by replacement with measured A1+A2, not by editing old evidence. Remaining TBD includes actual hardware DDR latency/cache decisions, long-duration/full admission paths, C original producing-build recovery, future chip/opcode/resource policy and arbitrary-count preference encoding/UI. These are not silently converted to PASS. Documentation/integration changes no RTL/Runtime/PWA/RBF bytes and performs no new compilation or hardware test.
