# MegaVGMDrive YM2610 HW-0 — Windows build and hardware check

This is a dedicated lab RBF. It contains only the MiSTer shell, standard
YM2610 (FM/SSG/ADPCM-A/ADPCM-B), deterministic test ROMs, BUSY-aware fixed
sequencer, direct audio, and a solid-color video generator. It has no VGM
parser, DDR/file loading, title UI, repeat mode, or YM2610B path.

## MiSTer PLL IP assignments

The HW-0 QSF inherits the three MiSTer shell PLL IPs omitted by the initial
project adapter, using the same `QIP_FILE` authorities as production Quartus
17 builds:

```tcl
set_global_assignment -name QIP_FILE ../../sys/pll_hdmi.qip
set_global_assignment -name QIP_FILE ../../sys/pll_audio.qip
set_global_assignment -name QIP_FILE ../../sys/pll_cfg.qip
```

The existing `sys_ym2610_hw0.qip` continues to register `../../rtl/pll.qip`
for `clk_sys`. Each outer QIP owns its generated synthesis files and nested
PLL constraint QIP; do not add those generated files individually to the QSF.

## Build on Windows

1. Copy the complete Mac repository to Windows. Do not copy only this folder.
2. Do not edit the QSF on Windows.
3. Close Quartus, then delete these generated directories under
   `hw/ym2610_hw0/`: `db`, `incremental_db`, and `output_files`.
4. Re-sync the complete repository after deleting those directories.
5. Open
   `hw/ym2610_hw0/MegaVGMDrive_YM2610_HW0.qpf` in Quartus.
6. Confirm that the current revision is `MegaVGMDrive_YM2610_HW0`.
7. Run a full compile. Expected output:
   `hw/ym2610_hw0/output_files/MegaVGMDrive_YM2610_HW0.rbf`.
8. Record from the compile reports:
   - Error count and full Critical Warning list;
   - ALM and register usage;
   - block-memory bits and M10K count;
   - DSP and PLL count;
   - worst setup slack and worst hold slack;
   - unconstrained-path count;
   - exact output RBF path.
9. If compilation fails, return the full error text, first failing file/line,
   resource report, timing report, and generated report filenames to the Mac
   side.
10. If a source/QSF change is needed, make it in the Mac repository, then copy
   the complete repository again. Never patch the Windows QSF directly.
11. On success, copy `MegaVGMDrive_YM2610_HW0.rbf` to MiSTer and launch it.

Quartus is intentionally not run on macOS for HW-0.

## Timing, colors, and expected sound

The production PLL converts 50 MHz to `clk_sys=20 MHz`. The native video uses
a 10 MHz pixel enable, totals 638×262, active 529×240, active-low HSync at
544–589 and VSync at 245–247. This is the repository's known-safe native
timing rather than a new display mode.

The production fractional CEN increment `6434443/2^24` gives a nominal JT10
chip rate of 7.6704538 MHz. One public sample occurs every 144 chip enables,
about 53.2670 kHz. The public-valid level is six CENs wide (15 or 16
`clk_sys` cycles with the fractional CEN), but HW-0 derives one
`sample_tick` only from its 0-to-1 transition. Every human-facing duration is
counted by that one-cycle tick, never by the six-CEN-wide level.

| Segment | Screen | Hardware samples | Approx. time |
|---|---|---:|---:|
| reset/ready boot hold | navy, muted | 159801 | 3.000 s |
| source announcement | source color, muted | 53267 | 1.000 s |
| FM/SSG/A0/A6/ADPCM-B stereo | source color, audible | 213068 | 4.000 s |
| ordinary source gap | navy, muted | 79901 | 1.500 s |
| ADPCM-B left or right | cyan, audible | 159801 | 3.000 s |
| left-to-right gap | navy, muted | 53267 | 1.000 s |
| first short play to restart | white, muted after verified zero | 79901 | 1.500 s |
| loop-end gap | navy, muted | 159801 | 3.000 s |
| error | red, muted | halted | until reset |

The fixed order is blue FM, green SSG, yellow ADPCM-A voice 0, orange
ADPCM-A six voice, magenta ADPCM-B stereo, cyan left-only, navy, cyan
right-only, and white short natural-end/restart. Each source color appears
for one full second before its START write. FM/SSG/A0/A6/stereo then retain
that color for four seconds from START; the hash window remains at its old
alignment and finishes before the extra colored hold. The first white short
sample ends naturally, HW-0 verifies internal zero and no remaining request,
holds white silence for 1.5 seconds, then starts the identical sample again.
After the second natural end it shows navy silence for three seconds and
announces blue for the next loop.

Shell reset and PLL unlock asynchronously request reset; release is
synchronized into `clk_sys`. PLL unlock resets video timing, but a soft reset
does not restart the pixel counters or interrupt H/V sync. A reset during any
self-test phase immediately mutes the final HW-0 output, returns the display
phase and sequencer to navy, clears partial microcode state, waits for JT10
ready/BUSY-clear/known zero, and repeats the complete 159801-sample boot hold.
Thus RBF load and soft reset have the same audio/test startup sequence.

The audible holds exceed the shorter hash windows. ADPCM-B's published Phase
4A anchor has 4096 samples after START returns plus its already-observed active
boundary sample (4097 active samples total); HW-0 preserves that exact
first-logical/first-nonzero alignment.

## Audio mapping

JT10 publishes signed 16-bit two's-complement left/right samples. HW-0 maps
them bit-for-bit to MiSTer `AUDIO_L/R`, asserts `AUDIO_S=1`, and applies no
shift, gain, saturation, clipping, normalization, filtering, DC blocking,
fade, limiting, pan change, or channel swap. Consequently there is no HW-0
conversion clip condition.

## MiSTer checklist

- Cold boot/navy: about three seconds with no write and no buzz, pop, hum, or
  DC tone; silence is truly silent.
- Every source color: about one second of color-only silence before sound.
- Blue/FM: one tone, equal in left and right.
- Green/SSG: audible square wave, clearly distinct from FM.
- Yellow/ADPCM-A voice 0: sample plays, then becomes silent.
- Orange/ADPCM-A six voice: multiple voices mix without noise or dropouts.
- Magenta/ADPCM-B stereo: sample plays; RESET leaves no DC.
- Cyan/pan: left-only then right-only, without swap or leak.
- White/natural end: short sample, silence, identical restart; no stale prefix,
  buzz, or old sample at the second start.
- Loop: returns to navy for about three seconds, second loop sounds identical,
  and long operation does not degrade.
- Soft reset from blue, orange, or magenta: immediate silence/navy, then the
  same three-second boot hold and a restart from blue FM.
- Red at any time is a failed BUSY, sample-cadence, phase, internal-zero, or
  ADPCM-B lifecycle contract; stop and report it.
