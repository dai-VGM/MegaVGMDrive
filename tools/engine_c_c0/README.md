# Engine C Phase C0 — MVGMSID v1 host reference

This isolated development tool implements the prepared-stream proposal for
MegaVGMPlayer. It does not convert SID programs, register PROFILE_C, load an RBF,
or integrate with any production playback component. Python 3.10+ and the
standard library are sufficient. No packages or build steps are required.

Base: `0c9e441f45f3d94b9edfbef1710e8a96ece6e828` (v2.1 documentation lineage).
Development branch: `engine-c-phase-c0`.

## Run

From the repository root:

```sh
python3 -m unittest discover -s tools/engine_c_c0 -v
python3 tools/engine_c_c0/mvgmsid.py /path/to/track.mvgmsid
python3 tools/engine_c_c0/mvgmsid.py /path/to/track.mvgmsid --dump
```

The inspector first validates the complete file. It prints a JSON summary on
success; `--dump` appends the initial traversal's timestamped events. Exit status
is 0 on success and 2 for rejected input or an I/O error. Invalid input does not
produce a partial success summary. Durations are exact rational seconds, not
rounded floating point. Unknown musical duration and absent loop are JSON null.
The source SHA is reported, not authenticated against a separate source file.

`Header`, `Event`, and `Stream` provide checked encode/decode APIs. `schedule`
returns native-cycle timestamps and exact 44.1 kHz positions. `Clock` and
`FractionalCE` provide closed-form and incremental CE references. Import using
`tools/engine_c_c0` on Python's module search path.

## Wire specification: MVGMSID v1.0

All integers are unsigned little-endian. Header size is exactly 128 bytes; each
event is exactly 16 bytes. There are no extensions, alignment gaps, trailers,
compression or VGM opcodes. A complete file is exactly `128 + stream_bytes` bytes.

| Offset | Bytes | Field | Contract |
|---|---:|---|---|
| 0x00 | 8 | magic | `4d 56 47 4d 53 49 44 00` (`MVGMSID` + NUL) |
| 0x08 | 2 | version_major | 1 |
| 0x0a | 2 | version_minor | 0 |
| 0x0c | 2 | header_size | 128 |
| 0x0e | 2 | event_size | 16 |
| 0x10 | 4 | flags | Bits 0..4 defined below; all others zero |
| 0x14 | 4 | clock_num | Positive SID Hz numerator P |
| 0x18 | 4 | clock_den | Positive SID Hz denominator Q |
| 0x1c | 1 | sid_model | 1=6581, 2=8580 |
| 0x1d | 1 | timing_standard | 1=PAL, 2=NTSC |
| 0x1e | 1 | sid_count | 1 |
| 0x1f | 1 | reserved | Zero |
| 0x20 | 4 | subtune_id | Positive, 1-based |
| 0x24 | 4 | reserved | Zero |
| 0x28 | 8 | event_count | Positive, includes EOF |
| 0x30 | 8 | stream_bytes | event_count * 16, checked for overflow |
| 0x38 | 8 | stream_cycles | Sum of all WAIT operands |
| 0x40 | 8 | duration_cycles | Known musical duration, otherwise zero |
| 0x48 | 8 | loop_event_index | Zero-based target event |
| 0x50 | 8 | loop_start_cycle | Timestamp of target event |
| 0x58 | 8 | loop_end_cycle | EOF timestamp when LOOP_VALID |
| 0x60 | 32 | source_sha256 | Opaque hash bytes for the original SID file |

Flags: bit 0 `DURATION_KNOWN`, bit 1 `LOOP_VALID`, bit 2
`END_IS_CAPTURE_LIMIT`, bit 3 `MODEL_EXPLICIT_OVERRIDE`, bit 4
`CLOCK_EXPLICIT_OVERRIDE`. An unknown duration is zero with bit 0 clear; a known
duration is positive with bit 0 set. Capture limit, musical duration and physical
stream duration are distinct. A known musical duration need not equal the
finite capture length. Flags do not infer or alter clock, model or routing.

Events:

| Offset | Bytes | Field |
|---|---:|---|
| 0 | 1 | opcode |
| 1 | 1 | register address |
| 2 | 1 | register data |
| 3 | 5 | reserved, zero |
| 8 | 8 | operand |

- `0x00 WAIT`: operand >= 1 SID native cycles; address and data zero.
- `0x01 WRITE`: address 0x00..0x18, 8-bit data, operand zero.
- `0xff EOF`: address, data and operand zero; exactly once, final event.

WRITE does not advance time. WAIT advances time by its operand; its own timestamp
is the beginning of that interval. Two WRITEs at the same cycle are invalid,
including identical writes. Identical writes on different cycles are preserved.
No gate toggles, same-value writes or init operations are synthesized/removed.

The minimal valid artifact is an EOF-only stream at cycle 0, with duration unknown
and no loop. The independent 144-byte fixture in the tests checks its exact wire
layout, not merely codec round-trip agreement.

## Strict validation and loop semantics

Unknown versions (including minor), flags, enum values or opcodes are rejected.
All reserved bytes must be zero. Lengths, counts, WAIT sum and loop metadata must
agree. Truncation at any byte, trailing data, duplicate/early/missing EOF, zero
WAIT, invalid write payload, multi-SID headers and a zero clock/subtune are rejected.
Encoder arguments outside their integer width are rejected rather than masked.
File size, stream size, cycle accumulation and expanded loop timelines may not
overflow uint64.

With LOOP_VALID clear, all three loop fields must be zero. With it set:

- target index precedes EOF;
- target event timestamp equals loop_start_cycle;
- loop_start_cycle < loop_end_cycle == stream_cycles;
- replaying the target at EOF must not introduce two writes on the same cycle.

An event at the end of a WAIT can share that boundary timestamp, so the target
index is significant; a cycle alone cannot identify the first loop event. A WAIT
may itself be the target. A positive loop with no writes is structurally valid.
Structural validation does not establish musical loop correctness or matching
SID filter/oscillator state; that remains a converter/corpus responsibility.

`schedule(stream, loop_repeats=N)` schedules N **extra** loop traversals after the
initial intro+loop traversal. At a repeated boundary it consumes the EOF and jumps
to the target without emitting EOF; only the final traversal emits EOF. Absolute
native and transport time continue monotonically, without reset or duplicated
intro. This is a bounded reference utility, not a production loop/fade policy.

## Timing reference

SID Hz = P/Q. For system clock F, threshold D = F*Q. Starting accumulator a=0,
advance n system edges using:

```text
CE_count, new_a = divmod(a + n*P, D)
edge_of_CE(k) = ceil(k*D/P), k >= 1
transport_tick, remainder = divmod(native_cycles*44100*Q, P)
```

System edges and CE ordinals are 1-based for `ce_edge`; native cycle 0 is the
stream origin before any SID CE. An event's native timestamp specifies bus time;
this tool does not claim to simulate the eventual FPGA PHI2/write subphase.

For at most one CE per system edge, require P <= F*Q. FPGA pipeline spacing may
impose a stronger requirement; that is not a C0 hardware validation result.
CE lateness relative to the ideal rational edge is in [0,1) system periods.
Noninteger division creates bounded edge spacing variation, not accumulated
rounding drift. Physical oscillator tolerance is outside this arithmetic model.

44.1 kHz conversion always uses absolute cycles, equivalently retaining the
division remainder across WAITs. Splitting a WAIT or a system-edge interval cannot
change the final timestamp, CE count or remainder. No per-event rounding or
fixed 1 MHz clock is used.

PAL 985248/1, NTSC 1022727/1 and the previously audited PAL rational 15763977/16
are covered by tests. C0 validates positive rational Hz representation, not a
hardware frequency whitelist. The proposal did not assign a normative list of
allowed P/Q values; accepting a file here does not certify its frequency or
PAL/NTSC metadata for a future Engine C. No model/clock override is inferred.

Python arbitrary-precision integers deliberately keep intermediate products exact
(including products larger than uint64). Wire values and accumulated native-cycle
timelines remain width-checked. Reference transport ticks or CE edge results may
exceed uint64 without truncation; an eventual RTL port must choose/prove widths.

## Verification and scope

The 41 unittest cases cover independent wire bytes, every unknown opcode/flag bit,
each reserved byte and byte truncation, invalid lengths/payloads, integer overflow,
duration separation, loop jumps and write collisions, inspector subprocess output,
and timing math. Timing checks include 24 hours in closed form, 100,000 individual
system edges per clock, 10,000 randomly chunked advances per clock and exact
Fraction-based comparisons. These are host arithmetic/format tests, not FPGA
simulation or hardware PASS results.

The header offsets, flags, event opcodes/widths, native timing and ownership match
the MVGMSID v1 proposal. No binary ABI changes were made. Cross-loop same-cycle
write rejection applies the existing single-write-per-cycle rule to the implicit
jump. Zero-valued unused metadata and nonzero known duration make the proposal's
unknown-value convention strict.

No SID RTL, Golden Shell, Supervisor, controller, Main, Remote, classifier,
importer or production artifact is changed. No SID converter, CRC extension,
clock whitelist, audio qualification, fade or FPGA build is implemented here.
