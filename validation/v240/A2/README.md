# Engine A Optimization A2 — RAM inference recovered

Result: **ENGINE_A_VNEXT_OPT_A2_PASS**. Hardware: **NOT_HARDWARE_VALIDATED**.
Implementation `b4e1b9c4a8ed0719b099389e9c54426fb8418495`; A1 base `505c0c3` / tree implementation `965398a` retained byte-for-byte.
Windows Quartus17.0.0 Build595 Lite, 5CSEBA6U23I7, seed1. SDC/QSF/defines/settings unchanged. Mac Quartus was not run.

## Cause and minimum change

Original A/B/D Golden source SHA256 and effective parameters match. A alone enables `MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST`, adding asynchronous FIFO-head address/BE reads and registered raw-head diagnostic consumers. Same source and parameters therefore do not imply the same read-port topology.

Controlled Windows synthesis: smoke-off gives 25,856 RAM bits; smoke-on gives0; removing only registered head diagnostics recovers data RAM16,384bits; removing the inactive asynchronous observers as well recovers all3RAMs. The real A2 graph confirms this. Final dead-fanout absence did not prove inference compatibility. This is consistent with recognition before final dead-consumer pruning; no direct internal compiler-phase trace is claimed. It is not an array-reset, FIFO-capacity, clock-enable, seed, or double-counted hierarchy issue.

Only15 preprocessor/comment lines were added to candidate `rtl/vgm_ddram_backend.sv`, using the existing production-minimal profile to omit those inactive observations. No functional FIFO port, memory read/write statement, pointer/count, reset/enable, arbitration, data, timeout, or response cycle was changed. FIFO depth256 remains. The global smoke define was retained because removing it also changes functional copy configuration/address offset.

Scope proof: selected A hook ties capture/copy/read smoke requests to0; 23-bit upload byte addresses produce word offsets below the separate ROM base. Removed capture/pop counters cannot fire for this binding. Activity, bottom Loading, status and audio logic remain exact. Default/measurement preprocessed HDL is unchanged. Future live smoke capture in this production profile requires separate review.

## Measured resources, without parent/child double counting

| Metric | da862ee | A1 | A1 + A2 |
| --- | ---: | ---: | ---: |
| Total ALM |35,665|35,580|23,503 (56%)|
| Used LAB |4,147|4,190|3,705 (88%)|
| Registers |59,537|59,334|34,963|
| M10K |82|82|85|
| DSP |40|40|40|
| Backend own ALM |11,575.1|11,356.8|253.4|
| Backend own registers |25,103|25,103|425|
| Backend own M10K |0|0|3|
| Fitter elapsed |28:16|44:18|12:53|

A2 incremental reduction:12,077ALM,485LAB,24,371registers. LAB headroom486. A1 incremental effects stay separate:−85ALM/+43LAB, and the original −88.815ns core path was fixed by the tree, not by this RAM change. Other fitted hierarchy differences are packing/physical-optimization effects of this one build-input change.

Map backend422registers differs from final fitted425registers; these are distinct stages. Declared FIFO RAM25,856bits is29+64+8 bits ×256. The old retained24,832FF bits reflect constant reduction of address bits. Actual inferred read address is clocked, mixed-port OLD_DATA, no memory clear; Quartus pass-through logic preserves read-during-write behavior. No interface cycle was added.

## Timing

All20checks (4corners ×setup/hold/recovery/removal/pulse width) PASS; endpoint TNS0 and violating endpoints0.

| Corner | Setup ns | Hold ns | Recovery ns | Removal ns | Pulse width ns |
| --- | ---: | ---: | ---: | ---: | ---: |
| Slow100°C |0.088|0.206|3.814|0.621|1.122|
| Slow−40°C |0.139|0.073|3.959|0.498|1.122|
| Fast100°C |2.986|0.132|4.992|0.285|1.122|
| Fast−40°C |3.466|0.103|5.277|0.204|1.122|

Minimum core setup+7.761ns. Worst overall HDMI path is `ascal|o_vacc_next[11] → o_state.sDISP`,+0.088ns. A1 remaining HDMI failure is absent in this fitted candidate. HDMI RTL was not modified; placement/routing changed after RAM recovery. Margin is small. This is one measured full build, not an independently reproduced build or hardware proof. No seed search or constraint relaxation was performed.

## Functional evidence

- Every-cycle backend equivalence:4 profile/repeat simulations,31,845cycles per run,1,566writes/7reads; full256 occupancy, wrap, partial packs, stalls, read range/timeout, reset/reload. Same-slot fullFIFO simultaneous push/pop explicitly covered; old data wins. Two mutants rejected.
- Actual Golden functional top:34 new A2 simulations against33 completed A1 reference traces. All matching-latency clock-ordered functional/audio hashes and cycle counts exact. L0/L12 logical voice/mix exact; UNEXPECTED_DIFFERENCE0.
- Bounded real windows:Out Run, Splash Wave, Last Wave/seashore, Galaxy Force, Clear, Maximum Power. Maximum Power408C0/309FM,#111frame15 retained. Loop/TWO_LOOPS/reload/reset/pending stale-response lifecycle PASS. These are bounded integration windows, not a new full-track Golden traversal claim.
- Fresh frozen Common2,005 regressions PASS; Parser/grammar inputs unchanged. Actual A2 Reader370/Scheduler336 also PASS through a fixed-hash plus default-preprocessing identity guard; original frozen runners remain unchanged. Phase0.5 legacy reproduction uses the original bytes explicitly.
- SegaPCM55fixtures/348simulations PASS; boundary90/horizon70/Avalon40 PASS; existing negative controls/deterministic reruns PASS. Golden8WRITE/WAIT92,610 and216asset coverage(required missing0) preserved.
- Existing A1 full Out Run53,678C0 component evidence is reused only for unchanged core/storage; no claim that it was newly rerun through the A2 Golden top.
- Icarus/Verilator elaboration/lint and artifact compatibility gate PASS. New map warnings:3 RAM read-during-write pass-through notices plus4 unused diagnostic wires. Existing PLL/I/O/unmatched `arc/arx/ary` SDC warnings remain; no SDC was changed.

## Artifacts and provenance

Permanent evidence/build output:
`/Users/daizo/Projects/output/EngineA_vNext_Optimization_A2_b4e1b9c_20261009`

Build Artifact: `artifact/MegaVGMDrive_A_vNext_Production_RC.zip`,514,297bytes, SHA256 `5d211e9eeacf09cefae4427f3fab4fa7a2e00ebd26c062f9c36a24b228d5a99b`.
This is the exact b4e1b9c artifact compiled on Windows; later evidence commits do not change its source provenance. Root-visible QPF/QSF,195 build inputs,199files; fresh-extract graph/member hashes/compatibility PASS. All194 other inputs and QSF/SDC/settings/order match A1. BUILD.bat is optional.

Candidate RBF: `hardware-test/MegaVGMDrive_A_vNext_Production_MiSTer.rbf`,3,067,028bytes, SHA256 `57b005ae66c586189e153cfe09b4b680e781deaec29bac1f19654e42f5b9b6c3`.
SOF/RBF and78 reports are recovered from the same Windows Map/Fit/STA/Assembler build; all recovered member hashes verified. Full report ZIP SHA256 `85407c7cfb778c8f078562b2330ea22c5021438919109b8d583b3d59090963b0`.

Protected before/after audit exact: accepted A/B/C/D RBFs, original production worktrees, canonical documents, Runtime/Main/PWA authorities unchanged. No deployment/promotion. Next hardware validation must verify audio, Activity, transparent bottom Loading, PWA switching, Stop/Next/Reload/loop; long-run/admission are not claimed PASS.

See `cause-audit.txt`, `windows-results.json`, `golden-equivalence.json`, `regression-summary.json`, `result.json` and the permanent archive for raw evidence and measured critical paths. The completed regression archive contains4,331 files with member SHA256; binaries/corpus and an intentionally stopped redundant baseline rerun are excluded.
