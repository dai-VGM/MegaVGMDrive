# P3 clean terminal validation

Status: VALIDATED / ADOPTABLE

L-P is resolved 7/7 (LP-A 4/4, LP-C 3/3), TB-only; production REAL = 0 and semantic UNKNOWN = 0.

The adopted P3 candidate is byte-identical to the unit/offline candidate. The clean graph excludes the frozen HW0 aggregate fatal from acceptance ownership; it does not modify that source or production RTL.

## Actual-DUT evidence

- VVP SHA-256: `d64a0c6fd649e6aa0a312a153fb62f39014a970d343d68e3e0931e50407f3944`
- Compile manifest SHA-256: `3dbfb2670981c55d804daa2f48d81856a27032f4b0a2075521867fca6143cfe2`
- stdout: 41074 bytes, 399 lines, SHA-256 `62546c68d4f79a4159ede9cf7c4347e52c40b7be5fd1f406c32583ef527602c0`
- stderr: 0 bytes
- raw child return code: 0
- timeout: false; exception: null
- detached elapsed: `6410365765917 ns`

Exact acceptance marker:

`P3_PHASE_TARGETED_PASS phase_events=16 visit1=2 visit2=2 visit3=2 visit4=2 visit5=2 visit6=2 visit7=2 visit8=2 LP_A=0 LP_C=0 missing=0 duplicate=0 order=0 third_loop=0 terminal_checked=1 terminal_pass=1 A1=0 R3=0 B3=0 S3=0 V3=0 H4=0 FINAL_DWELL=0`

The target TB then emitted `$finish` at `442229042000` (1ps). No explicit FAIL or fatal preceded the finish. Legacy `HW0_FAIL` text is diagnostic only and is not a clean-graph acceptance owner.

## Authority and preservation

Semantic authority remains Z3/A1, R3/epoch, P3, committed B3, S3, V3/H4, and final-public-zero. The P3 token, terminal, phase-event, and visit-cardinality contracts are unchanged. Production RTL, A1/R3/Z3, B3, S3/S4, final dwell, P/R/H4/V3, B7/C2, QSF/QIP, and Sacred TB are unchanged.

