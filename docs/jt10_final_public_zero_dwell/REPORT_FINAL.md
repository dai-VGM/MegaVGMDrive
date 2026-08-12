# Final public-zero dwell validation

Status: **#17 FINAL_SILENCE_SHORT RESOLVED**.

Authority:

- arm: existing `semantic_post_samples` boundary
- event domain: authoritative public audio sample event
- zero: public L/R both equal zero
- dwell: consecutive zero samples; nonzero breaks/reset the dwell
- threshold: 512 samples; completion is exactly once at sample 512

Unit and detached actual-DUT targeted validation both passed. The detached
run VVP SHA-256 was `b684e801b6bff745101a5c4ec220e6311815b96ae14150ef2568884f7cc00cb0`,
size `1435043`. stdout was 41215 bytes / 403 lines and stderr was 0 bytes.

Terminal evidence:

```text
V3_EPOCH_BOUNDED_PASS global=64/64 qualified=18 ... XZ=0 busy=0/0
FINAL_DWELL_TARGETED_PASS count=512 A1=0 P=0 R=0 S3=0 V3=0 H4=0
tb_targeted_actual.sv:10: $finish called at 442414791000 (1ps)
```

The raw process returncode was not preserved by the detached launcher. This is
a process-bookkeeping limitation only; explicit targeted PASS, count=512,
named regression counters zero, target `$finish`, and absence of fatal output
are the semantic acceptance evidence.

Historical root: F17-E PRIMARY, F17-G SECONDARY. Ownership: TB-only authority
mismatch. Production REAL: 0. The frozen S4 state-65 counter remains legacy
diagnostic authority and was not changed.

`HW0_FAIL` lines are legacy nonfatal diagnostic reporting from the frozen
HW0/S4-style monitor. They occur during traversal, are not emitted by the new
final-public-zero checker, and are not part of the targeted acceptance
predicate. They do not change the PASS marker or indicate a new checker
failure.

Remaining independent items: L-P 7, L-B 8. Semantic timeline UNKNOWN: 0.
