# FM/SSG ZERO semantic-attempt normalization V2

## Conclusion

Z3 is adopted.  The adapter now applies the same existing single-attempt
normalization used by START/STOP to FM/SSG ZERO.  A stale live `raw_attempt`
is diagnostic-only for those two families; the published semantic attempt is
zero.  Expanded families retain the frozen raw tuple classifier.

No production RTL, raw-attempt producer, existing A1, R3/T5, epoch
integration, P/R/H/H4, selector, S3/S4, B7/C2, or QSF/QIP source changed.

## Responsibility split

A1 classifies `(raw state, raw_attempt)` into a valid semantic
`(family, attempt)` or raises code 4 when no authority row matches.  It has no
expected-slot, order, program, or phase authority.  R3/T5 receives valid
semantic events and owns family/attempt/order/program/phase rejection.

The seven corrected negative cases are fixed in
`RESPONSIBILITY_SPLIT_V2.tsv`.  The executable two-layer result is fixed in
`NEGATIVE_MATRIX_V2.tsv`: three invalid raw tuples stop at A1, while four
valid-but-wrong tuples publish once and are rejected by R3.

## Exact candidate seam

Z0 is byte-identical to frozen A1.  Z1 normalizes FM ZERO only, Z2 SSG ZERO
only, and Z3 both.  Z3 adds no authority table: it reuses the existing
`family_attempt_count(family) == 1` cardinality and the existing
`normalize_attempt` helper already used by START/STOP.  All expanded families
continue through the original `expected_raw_attempt(..., K_ZERO)` comparison.

Static checks confirm no START/STOP, named-wire known-check, state matcher,
program/phase forwarding, failure-code, counter, reset, or sampling change.
There is no expected-slot input, failure suppression, force/release,
hierarchical drive, or absolute HDL path.

## Candidate matrix

- Z0: 64/64/62, A1 failures 2, downstream R3 code 13.
- Z1: 64/64/63, A1 failure 1; FM fixed, SSG remains.
- Z2: 64/64/63, A1 failure 1; SSG fixed, FM remains.
- Z3: 64/64/64, A1 failures 0, R3 failures 0, complete 1.

All four unit variants compile and pass.  Z1 and Z2 prove independent
responsibility.  Z3 preserves the adapter-invalid cases, and R3 preserves the
valid-but-wrong ownership cases plus wrong program, wrong phase, duplicate,
and order detection.

## Actual DUT evidence

The targeted Z3 run passed on the integrated DUT graph:

- loop1 FM ZERO, cycle 23,383,799: raw attempt 2, semantic attempt 0,
  A1 code 4 = 0, publish 1, R3 accept 1.
- following SSG START: R3 accept 1 and code 13 = 0.
- loop1 SSG ZERO, cycle 24,620,903: raw attempt 2, semantic attempt 0,
  A1 code 4 = 0, publish 1, R3 accept 1.
- P/R/S3/V3/H4/XZ errors: 0.

The bounded two-loop run passed at cycle 44,167,607:

- loop0 START/STOP/ZERO: 32/32/32.
- loop1 START/STOP/ZERO: 32/32/32.
- aggregate: 64/64/64.
- A1 failures: 0.
- R3 missing/duplicate/ownership/order/loop errors: 0/0/0/0/0.
- rearm: 1; third epoch: 0.
- timeline complete: 1; integration complete: 1.
- P/R/S3/V3/H4/XZ errors: 0.

## Failure reclassification

- adapter unknown qualifiers (11): RESOLVED by the frozen A1 named-wire fix.
- FM/SSG ZERO code 4 (2): RESOLVED by Z3.
- R3 code 13: RESOLVED as a derivative of the dropped FM ZERO.
- T5 code 15: RESOLVED by the frozen R-D rearm contract.
- #14 TIMELINE_EVENT_COUNT: RESOLVED.
- #18 through #34 timeline order: 17/17 RESOLVED.
- #17 FINAL_SILENCE_SHORT: still independent and unexamined here.
- L-P and L-B: still independent and unexamined here.
- new REAL failures: 0.
- UNKNOWN among the Gate-I semantic timeline failures: 0.

FAST_SIM complete, FAST_SIM=0, serial three-run, Stage C.1, Stage D,
Quartus, RBF generation, and hardware work were not run.
