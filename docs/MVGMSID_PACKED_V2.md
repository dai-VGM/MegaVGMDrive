# MVGMSID Packed v2.0 — host reference specification

This is a new, explicitly versioned storage format, not a change to frozen
MVGMSID v1/C0/C1 or a format currently accepted by the C4 FPGA parser.
All multi-byte header integers are unsigned little-endian. Cycles and byte
counts are unsigned 64-bit; arithmetic must reject overflow, never wrap.

## Exact 128-byte header

| Offset | Size | Field / constraint |
|---|---:|---|
| 00 | 8 | `MVGMSID\0` |
| 08 | 2 | major = 2 |
| 0a | 2 | minor = 0 |
| 0c | 2 | header_bytes = 128 |
| 0e | 2 | record_encoding = 1 (canonical ULEB128/write-centric) |
| 10 | 4 | flags: identical to C0 v1; other bits reject |
| 14 | 4 | clock_num, nonzero |
| 18 | 4 | clock_den, nonzero |
| 1c | 1 | model: 1=6581, 2=8580 |
| 1d | 1 | timing: 1=PAL, 2=NTSC |
| 1e | 1 | sid_count = 1 |
| 1f | 1 | reserved = 0 |
| 20 | 4 | subtune, 1-based |
| 24 | 4 | reserved = 0 |
| 28 | 8 | WRITE count (does NOT include EOF) |
| 30 | 8 | packed body bytes (includes EOF record) |
| 38 | 8 | stream_cycles = absolute EOF cycle |
| 40 | 8 | duration_cycles; C0 DURATION_KNOWN contract unchanged |
| 48 | 8 | loop_write_index (zero-based ordinal, see below) |
| 50 | 8 | loop_start_cycle |
| 58 | 8 | loop_end_cycle |
| 60 | 32 | source SID SHA-256, unchanged |

Compared with v1, 0e is an encoding identifier, NOT an event size; 28 is
WRITE count, NOT fixed event count; 30 is packed length; 48 is a WRITE ordinal,
NOT a v1 event index. All other field positions and semantics are unchanged.
Clock/model/timing metadata is preserved, not inferred or normalized.
128 + packed body bytes must fit u64 and equal actual file length exactly.

Flags are bit0 DURATION_KNOWN, bit1 LOOP_VALID, bit2 END_IS_CAPTURE_LIMIT,
bit3 MODEL_EXPLICIT_OVERRIDE, bit4 CLOCK_EXPLICIT_OVERRIDE; bits5..31 reject.
DURATION_KNOWN is set if and only if duration_cycles is nonzero, exactly as C0.
Capture limit is not promoted to known musical duration. Single SID is mandatory;
unknown model/timing, zero clock numerator/denominator and subtune zero reject.
No extra clock/model relationship is inferred beyond the frozen v1 contract.
For N WRITEs, the body is between 3*N+2 and 12*N+11 bytes inclusive; the decoder
also checks actual record count, EOF cycle, and canonical length independently.

## Records

WRITE: `ULEB128(delta) register data`, register 00..18, data 00..ff.
EOF: `ULEB128(delta) ff`, no data byte. Tags 19..fe reject.
Delta is from the previous WRITE cycle, or cycle zero before any WRITE.
First WRITE delta zero is legal; every subsequent WRITE delta must be positive.
EOF delta zero is legal. Exactly one final EOF is mandatory; no trailing bytes.
Repeated values and init writes are never removed. Consecutive v1 WAITs are
represented by their exact checked sum, including silence before EOF.

ULEB128 is standard unsigned base-128, low group first, bit7 continuation.
Only shortest encoding is accepted. At most 10 bytes; byte10 must be 01 for a
10-byte canonical u64. Truncation, overflow, continuation after byte10 and
redundant terminal zero groups reject. No timing quantization is performed.

## Loop semantics

No loop is inferred. Without LOOP_VALID all three loop fields are zero.
With LOOP_VALID, `0 <= start < end == EOF cycle` and
`0 <= loop_write_index <= WRITE count`.
The ordinal is the first WRITE at or after the original v1 loop target event;
WRITE count denotes a loop containing only waiting. This preserves targets on
WAITs, including WAITs after a WRITE at the same loop-start cycle.
The last excluded WRITE must be at or before start; the first included WRITE
must be at or after start. On replay, the next included WRITE occurs at
`previous EOF + (write_cycle - loop_start_cycle)`; later deltas are unchanged.
EOF-only waiting in the loop ends after `end-start` cycles.
Reject a last WRITE at EOF followed by an included WRITE at loop start (same
cycle across the loop boundary), as C0 does.

The original event index is a v1 storage coordinate, not audio metadata. Its
v2 replacement is the explicit ordinal plus unchanged start/end cycles.
Equivalence compares these canonical loop coordinates, every WRITE and EOF,
all flags, duration, model, timing, rational clock, subtune and source digest.
It does not claim byte-identical v1 reconstruction of redundant WAIT splits.

## Ownership / scope

Existing C1 -> golden v1 -> strict C0 validation -> pack -> strict v2 decode ->
full canonical trace equality. No direct C1 modifications, RTL, build or runtime
integration. Packed artifacts must not be loaded into the current v1-only RBF.

## Future RTL decoder proposal (not implemented)

Validate header/body length before session readiness. Prefetch variable records
into a FIFO of absolute u64 deadline/address/data entries, accumulating deltas
with carry checks. A maximum-ten-byte ULEB state machine validates canonical
termination before enqueueing. EOF is a deadline-bearing terminal entry.
Keep the existing native-cycle scheduler, CE and fade owner unchanged; no
clock stalling to cover starvation. Reject underflow. Loop metadata needs a
validated record offset/checkpoint for the ordinal and a rebased first delta;
do not seek to an arbitrary byte or reuse the original first delta on a loop.
Parsing throughput and FIFO depth require separate simulation before RTL work.
