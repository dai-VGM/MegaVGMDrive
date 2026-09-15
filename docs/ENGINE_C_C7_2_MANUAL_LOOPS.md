# Engine C C7.2 manual loop contract

C7.2 consumes authoritative manual metadata; it does not infer a loop. The
host emits existing Packed MVGMSID v2 fields (`LOOP_VALID`,
`loop_write_index`, `loop_start_cycle`, and `loop_end_cycle`) without a format
version change. Packed v1 loops remain outside the Engine C contract.

The strict ordinal partitions the WRITE sequence: the last excluded WRITE is
at or before `loop_start_cycle`, and the first included WRITE is at or after
it. This preserves a loop target inside a WAIT. The terminal EOF must be at
`loop_end_cycle == stream_cycles`. A last WRITE at the end combined with a
first included WRITE at the start is rejected because replay would create two
SID bus WRITEs on one native cycle.

During preflight the decoder records the byte offset and native target of the
first included record (or the EOF record for a wait-only loop). Replay emits a
boundary marker, rewinds only packed-decoder state, and rebases subsequent
deadlines by `loop_end_cycle - loop_start_cycle`. SID oscillator, envelope,
filter, noise, digi, audio pipeline, model/timing latch, and transport session
are never reset at the boundary.

The scheduler preconsumes the internal boundary marker during system-clock
slots before the corresponding SID edge. At that exact edge it publishes the
boundary/count and can execute a loop-start WRITE without shifting it. The
existing transport owner may instead assert `halt_loop` at a finite-policy
boundary; that suppresses only the next traversal and preserves the existing
fade/ENDED owner.

Transport position is produced by a persistent rational accumulator per SID
cycle: add `44100 * clock_den`, subtract `clock_num` on each overflow, and
increment the 44.1 kHz counter. PAL and NTSC therefore have no event-local
rounding drift.

## Validation project

Open on Windows from `hw/engine_c_packed_v2`:

`MegaVGMPlayer_EngineC_C7_2_Validation_MiSTer.qpf`

Expected RBF:

`output_files_c7_2/MegaVGMPlayer_EngineC_C7_2_Validation_MiSTer.rbf`

Mac validation is simulation/elaboration only; Quartus is not run on macOS.
