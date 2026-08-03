# MegaVGMDrive YM2610 HW-0 — Windows build and hardware check

This is a dedicated lab RBF. It contains only the MiSTer shell, standard
YM2610 (FM/SSG/ADPCM-A/ADPCM-B), deterministic test ROMs, BUSY-aware fixed
sequencer, direct audio, and a photo-readable PCM diagnostic video overlay. It has no VGM
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
| FM or SSG reference | source color, audible | 159801 | 3.000 s |
| FM/SSG reference gap | navy, muted | 53267 | 1.000 s |
| each PCM attempt | phase color, audible window | 53267 | 1.000 s |
| PCM attempt gap | same phase color, muted | 26634 | 0.500 s |
| PCM phase result hold | same phase color | 159801 | 3.000 s |
| first short play to restart | white, muted after verified zero | 79901 | 1.500 s |
| final summary | dark navy, 5×7 result matrix | 532670 | 10.000 s |
| fatal error | red plus four-bit code | halted | until reset |

The fixed order is blue FM, green SSG, yellow ADPCM-A voice 0, orange
ADPCM-A six voice, magenta ADPCM-B stereo, cyan pan, white short
natural-end/restart, then the dark-navy summary. FM and SSG run once. A0, A6,
and stereo B run six times each. Pan runs left-only three times and right-only
three times. White performs natural-end plus unchanged-register restart three
times. The sample is never stretched: each short burst is separated by a
half-second muted interval so it can be heard as a distinct attempt. Every
published hash window retains its established alignment and finishes inside
the one-second attempt hold.

Shell reset and PLL unlock asynchronously request reset; release is
synchronized into `clk_sys`. PLL unlock resets video timing, but a soft reset
does not restart the pixel counters or interrupt H/V sync. A reset during any
self-test phase immediately mutes the final HW-0 output, returns the display
phase and sequencer to navy, clears partial microcode state, waits for JT10
ready/BUSY-clear/known zero, and repeats the complete 159801-sample boot hold.
Thus RBF load and soft reset have the same audio/test startup sequence.

The attempt holds exceed the shorter hash windows. ADPCM-B's published Phase
4A anchor has 4096 samples after START returns plus its already-observed active
boundary sample (4097 active samples total); HW-0 preserves that exact
first-logical/first-nonzero alignment.

## Audio mapping

JT10 publishes signed 16-bit two's-complement left/right samples. HW-0 maps
them bit-for-bit to MiSTer `AUDIO_L/R`, asserts `AUDIO_S=1`, and applies no
shift, gain, saturation, clipping, normalization, filtering, DC blocking,
fade, limiting, pan change, or channel swap. Consequently there is no HW-0
conversion clip condition.

## Reading the PCM diagnostic screen

A permanent white/magenta 2×2 checker at the upper right identifies this PCM
diagnostic build. During yellow, orange, magenta, cyan, and white phases, the
seven large boxes across the top are, from left to right:

1. raw ROM request;
2. qualified ROM capture;
3. address progression plus changing ROM data;
4. ADPCM source lane non-zero;
5. JT10 final L/R non-zero before the HW-0 mute;
6. final `AUDIO_L/R` non-zero after the mute;
7. stop/zero, pan isolation, or natural-end/restart contract.

Green means observed/PASS, red means the completed attempt failed, and dark
gray means not observed yet. Six boxes along the bottom identify attempts:
white is complete, green is current, and dark gray is pending. Natural/restart
uses only the first three.

The final ten-second summary has five rows: yellow A0, orange A6, magenta B,
cyan pan, and white restart. Its seven columns use the same order. Green is
PASS, red is FAIL, and dark gray is unavailable. Report a photographed result
in this fixed format:

```text
黄: G G G G G G G
橙: G G G G G G G
紫: G G G G G G G
シアン: G G G G G G G
白: G G G G G G G
error code: 0
```

PCM evidence failures do not stop the sequence. Codes 4–10 remain recorded in
the boxes and summary while testing continues through cyan and white. Only a
transport/state integrity failure produces a full red halt. The four bottom
white/black boxes show the binary error code, most-significant bit first:

| Code | Meaning | Class |
|---:|---|---|
| 0 | none | — |
| 1 | BUSY timeout | fatal |
| 2 | write while BUSY | fatal |
| 3 | sample cadence/width corruption | fatal |
| 4 | no PCM request | phase-local |
| 5 | no capture/progress | phase-local |
| 6 | source lane remained zero | phase-local |
| 7 | source lane live but JT10 final zero | phase-local |
| 8 | JT10 final live but HW output zero | phase-local |
| 9 | stop/zero timeout or pan isolation | phase-local |
| 10 | EOS/restart failure | phase-local |
| 11 | illegal phase | fatal |
| 12 | reset synchronizer contract | fatal/reserved |
| 13 | ROM range violation | fatal |
| 14 | reserved | fatal |
| 15 | unknown/internal contract | fatal |

## MiSTer checklist

- Cold boot/navy: about three seconds with no write and no buzz, pop, hum, or
  DC tone; silence is truly silent.
- Upper-right white/magenta checker is present throughout.
- Blue/FM and green/SSG remain audible references.
- Yellow, orange, and magenta each show six separated attempts.
- Cyan shows three left-only then three right-only attempts.
- White shows three natural-end/restart pairs.
- The ten-second summary is reached even when a PCM row contains red cells.
- Soft reset from yellow, orange, or magenta: immediate silence/navy, then the
  same three-second boot hold and a restart from blue FM.
- Full-screen red means a fatal code 1–3 or 11–15; record its four-bit code.
