# NATURAL semantic START validation — final report

## Result

`LB_NATURAL_TARGETED_PASS` was emitted by the actual-DUT target at
`440195681000 ps`, followed by the target testbench `$finish` one time unit
later.  The detached VVP exited normally with raw return code 0.

The accepted payload was:

```text
LB_NATURAL_TARGETED_PASS natural_starts=12 N1_attempts=6 N2_attempts=6 loop0=6 loop1=6 duplicate=0 missing=0 order=0 third_loop=0 LB_failures=0 P3_errors=0 A1=0 R3=0 S3=0 V3=0 H4=0 FINAL_DWELL=0
```

The marker does not carry a separately named `unique` field.  Its local
tuple proof is equivalent: 12 starts, two families × six, two loops × six,
and duplicate/missing equal zero establish all 12 required
`(loop, NATURAL family, attempt)` tuples exactly once.

## Root and adopted contract

The frozen monitor initialized `natural_run` to -1 and incremented it for
each raw phase-7 ADPCM-B start.  Its `natural_run > 3` predicate tolerated
starts 1–4 and misclassified authoritative starts 5–12 as eight
`NATURAL_EXTRA_START` failures.

The adopted B3 monitor consumes the Z3 validated semantic START token and
records the twelve legal tuples: loop 0/1, NATURAL1/NATURAL2, attempt 0/1/2.
It owns tuple duplicate, missing/cardinality, and NATURAL attempt-domain
checks.  Global order, rearm, phase order, and third-epoch ownership remain
with R3/T5, epoch/V3, and P3 respectively.

The completion correction is the post-blocking-assignment predicate
`starts == 12`.  The target-only observer additionally resets `reported` to
zero; without that reset its X value prevented both PASS and FAIL
serialization.  Neither change modifies production RTL or the frozen HW0
monitor.

## Classification

- L-B / `NATURAL_EXTRA_START`: 8/8 RESOLVED.
- Root: LB-A primary, LB-D secondary.
- Ownership: TB-only authority mismatch.
- Production REAL: 0.
- Semantic UNKNOWN: 0.

The previous 32 KiB observation was an intermediate read of a growing
regular stdout file, not the final process result.

## Evidence identity

- VVP SHA-256: `93460a3c6b7170e8655788b5773ff723f838821b70a4311768d1861e30941dd9`
- Compile-manifest SHA-256: `ec80ab6d472f5247ed887c6de5d7d693a19df2a3ac7173f4eb03e3ebf56d241f`
- stdout SHA-256: `7980febd1f749f7b193d8c93e014fcfa437a4ac94ff925f3dfd95413db658d6e`
- stdout: 39,784 bytes / 388 newlines.
- stderr: 0 bytes.
- raw return code: 0.
- elapsed: 6,360,244,082,708 ns.

P3/L-P remains a frozen semantic candidate pending its own terminal
serialization evidence; this adoption does not promote it.
