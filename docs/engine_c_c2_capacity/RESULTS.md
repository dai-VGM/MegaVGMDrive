# C2 capacity regression evidence

Environment: macOS; Verilator 5.050; Python 3; Tcl source-resolution audit.
**Simulation/host checks only. No Quartus or hardware result is asserted here.**

## Checks

| Suite | Result |
| --- | --- |
| Frozen C2 RTL regression | 47 cases successful, unchanged source |
| Capacity regression | 67 cases successful (59 streams, 2 DDR fault injections, 3 old/new boundary contrasts, 3 full-shell scenarios) |
| C0 strict format/reference tests | 41 successful |
| C1 converter tests, including native helper | 22 successful, none skipped |
| New QSF recursive source resolution | 63 unique HDL files; each selected engine/loader/SID module exactly once |
| `emu` open-source elaboration | Successful with HPS/PLL simulation stubs; not full-platform Quartus synthesis |
| Frozen-source audit | Every pre-existing tracked file unchanged relative to `e006014` |

Each accepted stream runs two consecutive sessions in the direct engine harness.
Every observed WRITE is checked against the original input's address, data,
ordering and native cycle. CE count is checked every SYS cycle against
`floor(elapsed_SYS * 985248 / 20000000)`. Reset is one SYS edge; every publication
in session two is compared both to session one and to a clean-reference SID.
Descriptor memory is poisoned initially and not cleared between sessions.

## Exact boundaries

| File bytes | Old C2 | Capacity C2 |
| ---: | --- | --- |
| 131,056 | — | Valid aligned stream accepted |
| 131,071 = 128 KiB − 1 | — | Reject 6: not a valid 16-byte-aligned v1 file |
| 131,072 = 128 KiB | — | Accepted |
| 131,073 = 128 KiB + 1 | — | Reject 6: not a valid 16-byte-aligned v1 file |
| 131,088 | — | Accepted |
| 131,200, WAIT-only | Accepted, 8,191 SID cycles | Accepted |
| 131,216, WAIT-only | Reject 1, first test SYS cycle 0 | Accepted |
| 131,200, 4,096 WRITEs | Reject 11 at SYS cycle 270,559 | All 4,096 WRITEs accepted |
| 4,194,288 = new max − 16 | — | Accepted |
| 4,194,303 = new max − 1 | — | Reject 6: misaligned |
| 4,194,304 = new max | — | Accepted, both WAIT-only and maximum WRITE density |
| 4,194,305 = new max + 1 | — | Reject 1, before any parser read |
| 4,194,320 = new max + 16 | — | Reject 1 |
| 4,194,304 with malformed final EOF | — | Reject 12; zero SID WRITEs/publications |

A v1 file always has length `128 + 16 * event_count`. The ±1 tests must therefore
reject; accepting them would break the frozen format rather than prove capacity.

Maximum-density four-MiB fixture:

```text
events = 262136
WRITE count = 131068
final native cycle = 131067
descriptors including EOF = 131069
```

## Real shell upload simulation

Uses the actual C2 ioctl interface, unchanged `vgm_ddram_backend`, new DDR arbiter,
descriptor store, parser, scheduler and SID. The model injects DDR busy cycles
and read latency, supports full bursts, and asserts physical address range,
byte enables and burst ownership. The post-upload SID WRITE address/data/order
and native cycle are checked against the original file, including during
index-2 activity; EOF must follow every expected WRITE.

- Small original tone uploaded/played twice, then a 144-byte EOF-only session.
- 4,194,304-byte dense fixture uploaded/played twice, then a 144-byte session
  **without clearing DDR**. Each large load writes 524,288 raw DDR words and
  262,138 descriptor words. There is no low-address alias at 128 KiB or 4 MiB.
- 4,194,305-byte oversize fixture rejected twice, followed by a successful
  144-byte session. No permanent error/mute carryover.
- Each scenario also injects an upload at byte address `0x800000`: sticky
  physical overflow, no load complete, no new parser start, silent output.
- Index-2 transfer does not re-arm/reset the engine. EOF/reject output stays zero.

## Failure behavior

- Stop DDR responses after playback starts: unchanged scheduler underflow
  `0x80` at native cycle 32, after 32 exact WRITEs. It does not reschedule or
  stretch CE. The frozen contract bench separately confirms continued CE after
  underflow.
- Corrupt descriptor upper padding: storage fatal `0x81`, output zero.
- Existing malformed/version/flags/sizes/model/clock/register/same-cycle/WAIT
  overflow/EOF rejection tests remain intact. No sound publication before
  whole-file validation.

## Audio equivalence

The original 3-second PAL/6581 tone has 21 events and 10 WRITEs, final cycle
2,955,744. Both old/new runs publish 2,955,743 samples and produce identical
44.1-kHz PCM (132,300 frames):

```text
PCM SHA256: 4d8428b1b01918f000bacd913b591ef499ec8e7f84ad76038c477e560c0e6c19
Original WAV SHA256: ae3e3527820aaea60bf45915c9bf6a7e18c38ad6dd582b36d29ae5c7e58e2b04
Synthetic stream SHA256: c8f183bba3711c8c55d74e648be0e93436bb567af49ed965675d8ee93975de2a
```

Original WAV: `/tmp/megavgm-c2-capacity-baseline/tone-pal-6581.wav`.
Capacity logs/fixtures: `/tmp/megavgm-c2-capacity/` (`results.json`,
`source-audit.json`, `resolved-sources.txt`, `emu-elaboration.log`).

The synthetic equivalence evidence is not a substitute for Windows fit/timing
or Commando real-hardware verification. No copyrighted SID file was added.
