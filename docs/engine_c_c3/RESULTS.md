# C3 verification results

All results below are **simulation or host tests**, not Windows Quartus or MiSTer
hardware results. The C2 Capacity hardware PASS is user-reported for the frozen
base, not transferred automatically to C3.

## Suites

| Check | Result |
| --- | --- |
| Frozen original C2 suite | 47 cases successful |
| Frozen C2 Capacity suite | 67 cases successful |
| C3 suite | 84 cases successful |
| C0 format/reference | 41 tests successful |
| C1 including native converter integration | 22 tests successful; none skipped |
| Dedicated QSF recursive source resolution | 63 unique HDL files; C3 loader/engine/scheduler exactly once |
| `emu` elaboration | Successful using HPS/PLL simulation stubs |
| Freeze audit | Every file tracked at c9fc9a1 unchanged |

C3 includes all 59 C2 Capacity file fixtures. The old model-2-negative fixture
(`8580-unsupported`) is intentionally accepted under C3; a timing-only change
to NTSC while retaining PAL clock remains rejected. Three additional tone
combinations, four equivalent rational clocks, eleven invalid metadata cases,
an eight-session mixed sequence, DDR starvation/corruption, the clock-latch
bench, and three real-shell upload scenarios complete the 84 cases.

## Four combinations

Each 3-second synthetic tone runs twice. Every WRITE is compared to the frozen
C0-decoded native-cycle trace. Every SYS edge checks the exact floor-formula CE
count. Each second session's native audio is compared with both the first run
and a clean-reference SID. A one-edge session reset and non-cleared descriptor
DDR preserve the stale-state stress conditions.

| Model/timing | Clock Hz | WRITEs | Final native cycle / CE count | Publications | WAV frames |
| --- | ---: | ---: | ---: | ---: | ---: |
| PAL / 6581 | 985248 | 10 | 2955744 | 2955743 | 132300 |
| PAL / 8580 | 985248 | 10 | 2955744 | 2955743 | 132300 |
| NTSC / 6581 | 1022727 | 10 | 3068181 | 3068180 | 132300 |
| NTSC / 8580 | 1022727 | 10 | 3068181 | 3068180 | 132300 |

Four files are 44.1-kHz, signed 16-bit mono WAV. Register timing is **not**
quantized to that WAV rate; the harness only samples the final output for WAV.
The synthetic frequency register and wait duration are generated for each clock.

Output directory:

```text
/Users/daizo/Projects/MegaVGMPlayer_EngineC_PhaseC3_Artifacts/
```

| WAV | SHA-256 |
| --- | --- |
| `tone-pal-6581.wav` | `ae3e3527820aaea60bf45915c9bf6a7e18c38ad6dd582b36d29ae5c7e58e2b04` |
| `tone-pal-8580.wav` | `f604f2f51093a9e73d0da227987b3016089c6389724e6987ac8146e683819907` |
| `tone-ntsc-6581.wav` | `3103ec75e13f9ae95d5f244f8f83b73e9d2636fc4220223f1f2b3ff8ec97ede6` |
| `tone-ntsc-8580.wav` | `21bede688f0609b13ef69d8fe9d7bf420494b332f051cacd2baab84a2fb86762` |

PAL/6581 is **byte-identical** to the C2 reference WAV and PCM. The others are
nonzero and exercise the existing model-specific SID arithmetic; no audio
algorithm was edited to achieve these results.

## Session/configuration tests

- Eight sequential loads in one engine instance cover all four combinations,
  PAL↔NTSC and 6581↔8580 changes, including a return to PAL/6581.
- Before each following session, only the reference SID is cleared while the
  DUT still retains its previous pipeline history. Every new publication then
  equals the clean reference for the newly selected model/clock.
- During playback, upload-memory metadata is changed to invalid values and
  stray `start` pulses are injected. Accepted model/clock and CE remain unchanged.
- A separate scheduler bench changes clock inputs to numerator 1 / denominator 0
  immediately after launch. Six cases each check 2,000,000 SYS edges; the
  latched configuration remains intact with exact CE counts.
- Large rational denominator cases use PAL `4294696032/4359` and NTSC
  `4294430673/4199`. Their phase exceeds 32-bit range, with no wrap/truncation:
  final phases 69,744,000,000 and 58,786,000,000 respectively. CE counts at
  2,000,000 SYS edges remain 98,524 and 102,272.
- Unknown model/timing, zero denominator/numerator, mismatched PAL/NTSC rate,
  off-by-one frequency, huge denominator and a forged 32-bit-product-wrap clock
  reject without SID writes, CE, audio or committed session clock.

## Capacity and shell integration retained

- C3 repeats the 128-KiB and 4-MiB boundary tests, including misaligned +/-1 and
  aligned over-capacity rejection, with all existing malformed stream cases.
- The actual ioctl upload, DDR backend, arbiter, parser and SID path plays a
  4-MiB maximum-density fixture twice: 131,068 WRITEs per load, final cycle
  131,067, exact address/data/order/cycle checks. A 144-byte session follows
  without clearing DDR. No address alias or stale descriptor is accepted.
- The shell model/timing sequence loads PAL/6581 → NTSC/8580 → PAL/6581.
  Index-2 remains inert and does not modify accepted configuration.
- Two 4-MiB+1 rejects followed by a small valid session recover normally.
  Physical byte address 0x800000 is rejected without a parser start.
- DDR starvation produces existing scheduler fatal 0x80; corrupt descriptor
  padding produces storage fatal 0x81. No change to underflow recovery semantics.

Machine-readable logs: `results.json`, `wavs.json`, `source-audit.json`,
`resolved-sources.txt`, and `emu-elaboration.log` in the output directory.
Windows synthesis/fit/timing and C3 hardware audio remain unverified.
