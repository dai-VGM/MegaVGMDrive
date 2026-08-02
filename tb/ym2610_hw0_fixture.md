# YM2610 HW-0 fixture and verification contract

## Frozen baseline recorded before work

- Branch: `ym2610-family-bringup`.
- HEAD: `9c6feb302ffee54443a822c02901cd09537ab976`.
- Subject: `Add standalone JT10 ADPCM-B single-shot bring-up`.
- Tracked and staged diffs: clean.
- Existing untracked set: exactly the 23 protected diagnostics below.
- Start-record manifest digest: `9a423c962e9edda97ca1f83b5a764c15cf9ebae4f4bcba7534a471dbbf62fcf3`.
- The local verifier's sorted `path/SHA-256/size/mtime/inode` encoding is
  `42ed2aca1a859f43278641607b21e5134e0b09bc053a3f0dc22e08f9a46dbf74`.
- Production Git blobs: `files.qip`
  `71d98974f2672207467eac493c06bbc23c74e45b`, QSF
  `898ae5a61d7c1f94d9f824a9007fcadff65383f9`.
- Pristine JT10: 15/15 Git blobs and SHA-256 values match
  `tb/jt10_compat/pristine_blobs.tsv`.
- Formal overlay five files and provenance: match HEAD; production references
  zero.
- JT49, compatibility generators, and Phase 0 warm-up wrapper: match HEAD.

| Protected path | SHA-256 | size | mtime | inode |
|---|---|---:|---:|---:|
| `tb/generate_jt10_phase4ap_variants.py` | `f9584088fad83c1f3f916a694dcc8c138cb9d96977825d956ea1f514fcde83d2` | 9827 | 1785575962 | 23212536 |
| `tb/generate_jt10_phase4ax_variants.py` | `fbf036b633cf7bf046824ae69a739222e72e1098deecd060d8d94ceea1b7fa2a` | 6634 | 1785564257 | 23174754 |
| `tb/jt10_phase3cr_fixture.md` | `69f6b34de80b613846b41b6b59e54d851cacd9e4f9fed83f0a4ce76e08e99cd5` | 13869 | 1785511396 | 23092116 |
| `tb/jt10_phase3cr_sources.f` | `20aaa483f095cdd8893f8d8f42e9faca6a6c7e4d42d413bc7cba1fb551b532a3` | 130 | 1785508919 | 23091109 |
| `tb/jt10_phase4ap_fixture.md` | `482369319419915eff3e24a5ac0473a28f7fafb866b7a3ea06f5d32029843b73` | 24831 | 1785583714 | 23229246 |
| `tb/jt10_phase4ap_sources.f` | `0b5735947acf56851145923b9521592adb3c1322e3308372e8dd4f5f56c49192` | 99 | 1785575447 | 23213551 |
| `tb/jt10_phase4ar_fixture.md` | `3cf148330de8526bd07c75461b8b62e9e18007d035a3d3e8353d946300e33d50` | 7939 | 1785551099 | 23173366 |
| `tb/jt10_phase4ar_sources.f` | `e97b914c66bbf614b8de1b5a6f09e3826cc6d56cf4e0d9aaa4efd3f445731a6f` | 100 | 1785550360 | 23172872 |
| `tb/jt10_phase4arv1_fixture.md` | `e31b22910d5099692f1f7fe436b4282dc1fbd36691fd41ab5e8b71598a9b0a9a` | 34283 | 1785572003 | 23210807 |
| `tb/jt10_phase4arv1_sources.f` | `c996a508e35e125210f2fb860b9f69feac4403343ca11896fadf0430e6ff9e7c` | 102 | 1785565657 | 23203184 |
| `tb/jt10_phase4ax_fixture.md` | `8b01467105f9095ea38384f2761a5984318868732f2b057daa00e3cf6853937a` | 21219 | 1785564151 | 23182850 |
| `tb/jt10_phase4ax_sources.f` | `d12dc3cd20309ef77affcdd2182da601d7c0c2153cc6a1a86d68929e373a5a9c` | 101 | 1785553572 | 23174951 |
| `tb/run_jt10_phase3cr.sh` | `3232c45a5d792836bd3500f0cbaabb638fb4dabffc7ebba42631911f77d6aa73` | 15188 | 1785511001 | 23091838 |
| `tb/run_jt10_phase4ap.sh` | `59d66fdae6a2b66f57cd7499278bd4a1c1b06d221af6cd04729b01b1d8433961` | 12935 | 1785576545 | 23214978 |
| `tb/run_jt10_phase4ar.sh` | `6f31d0932b07a363638dcb4291b287d7bfd6bcf06d0bbe27eae8d16e578c4623` | 10006 | 1785550451 | 23172906 |
| `tb/run_jt10_phase4arv1.sh` | `d8b2ab947652c2926a9c0b294fcc69750cdf3932b2f0517902c434db914d7dd9` | 12486 | 1785569525 | 23203252 |
| `tb/run_jt10_phase4ax.sh` | `54101e3930a5c9c93a874ea907ea92ef3fb07c0ad9dd0d6c6f19b2dee0365493` | 15096 | 1785556556 | 23174992 |
| `tb/tb_jt10_phase3cr_clear_boundary_audit.sv` | `6d5a9dbe541036c6cede174d89825727b5f9944323cd5ce9affebf19d30c16c2` | 66122 | 1785510646 | 23091111 |
| `tb/tb_jt10_phase4ap_adpcmb_patch_matrix.sv` | `92d4b60a29edad2357716a2ce3b0dd701831a5cbc63e24b03b99e8d19018e7a6` | 40814 | 1785576281 | 23213550 |
| `tb/tb_jt10_phase4ar_adpcmb_stop_contract.sv` | `a7dab72ba78547982a665db5af9c64fb1a22052e97a81530eb4f8cb324c9c067` | 43222 | 1785551002 | 23172873 |
| `tb/tb_jt10_phase4arv1_adpcmb_stop_contract.sv` | `5cadb9b72e7d3c7dcd0c1e0b42930ba771e28fbac6e2084749e842902e5a7265` | 5801 | 1785569525 | 23203183 |
| `tb/tb_jt10_phase4ax_adpcmb_reset_coverage.sv` | `e733c1822306ea01a51d2246da2a5a4eeb87dd1434c59e2c9ca1ba688cb019da` | 59441 | 1785555908 | 23174952 |
| `tb/tb_jt49_audio_compare.sv` | `35cbd96d057e9889815229f2c0e154614eea7956ae895afdb74f6ace2b65406c` | 4939 | 1784686524 | 21984214 |

The static audit recomputes every row and aborts on content or metadata drift.

## Hardware/public timing contract

- PLL source: the existing `rtl/pll.qip`, 50 MHz input and 20 MHz `clk_sys`.
- JT10 fractional CEN: increment 6,434,443 in a 24-bit accumulator,
  7.6704538 MHz nominal chip-enable rate.
- Internal/public sample: 144 CEN rising interval and six CEN-wide pulse.
  With the production fractional CEN this is 375 or 376 `clk_sys` cycles per
  public sample and 15 or 16 `clk_sys` high cycles. `FAST_SIM` observes the
  equivalent 144-cycle cadence and six-cycle high width.
- Before this pacing change, the sequencer already used
  `sample_strobe && !sample_d`, so its duration counter advanced once per
  logical sample, not six times. The approximately six-times-too-fast
  hypothesis is rejected. The actual short real-hardware constants were
  boot 32768 (0.615 s), gap 24576 (0.461 s), main hold 81920 (1.538 s), and
  pan hold 53248 (1.000 s), with no color-only pre-roll. Color and program
  launch also happened at the same state transition.
- The canonical HW-0 `sample_tick` is now generated once in the top from the
  public-valid 0-to-1 transition. The sequencer receives no raw valid level.
  Old and new duration-counter increments are both exactly one per public
  sample; the fix is explicit ownership plus corrected durations, not a
  divide-by-six workaround. A synthesizable 144-CEN cadence/six-CEN width
  monitor makes a violation red and halts.
- Global reset receives at least six asserted CENs. The core continues running
  while the first five internal samples are hidden; the sixth is the first
  public sample. Shell reset or PLL unlock asserts the test reset; deassertion
  crosses a three-stage `clk_sys` synchronizer. The sequencer then requires
  ready, known-zero internal audio, and BUSY clear, performs 159801 public
  ticks (3.000 s) of navy silence with zero writes, and only then applies the
  initial silence program. PLL unlock separately resets video timing; a soft
  reset returns only `display_phase` to navy and leaves H/V counters running.
- Writes use status-clear wait → address → data → BUSY-assert wait → BUSY-clear
  wait. A 16-bit watchdog failure or a data write while BUSY halts, mutes, and
  makes video red.
- Durations use the canonical public-sample tick, never a fixed system-cycle
  delay or public-valid level.
- The final HW-0 output mux is the only human-silence mute. It is asserted in
  reset/pre-ready/boot/pre-roll/inter/final states. It remains off after every
  stop until internal L/R are zero for 32 consecutive public ticks. ADPCM-B
  also requires request and active clear. Zero timeout, cadence/width error,
  phase overflow/unexpected state, BUSY failure, or write-while-BUSY halts,
  mutes, and selects red.

### Hardware duration constants

| Contract | Public ticks | Seconds at 53.267040 kHz |
|---|---:|---:|
| boot navy | 159801 | 2.999998 |
| color-only pre-roll | 53267 | 0.999999 |
| FM/SSG/A0/A6/B stereo dwell | 213068 | 3.999997 |
| ordinary navy gap | 79901 | 1.500008 |
| left/right pan dwell | 159801 | 2.999998 |
| left-to-right navy gap | 53267 | 0.999999 |
| white natural-end gap | 79901 | 1.500008 |
| final navy gap | 159801 | 2.999998 |

The exact-count pacing TB drives one logical tick per simulation clock and
checks all eight constants over two complete loops. The integrated audio TB
uses reduced timing parameters only to make four full JT10 runs practical;
it retains the production measurement alignment/counts and separately proves
the 144/6 public waveform contract.

## Self-test/hash windows

| Phase | Contract | Hash samples | Expected stereo FNV-1a |
|---:|---|---:|---|
| 0 | boot silence | 159801 zero, zero writes | zero contract |
| 1 | FM encoding 1, ALG7 | 4096 after 4096 attack | `8aadd7a6819038e5` |
| 2 | SSG A, period 0020, volume 0F | 4096 after 263 startup | `54730095b12b6325` |
| 3 | ADPCM-A voice 0 | first 4096 | `adf8cc2f2f81c1b9` |
| 4 | ADPCM-A six-voice Scenario G | first 8192 | `32cb891931682fe9` |
| 5 | ADPCM-B 0020–004f/8000/C0/FF | Phase 4A aligned boundary + 4096 | `1207d84363d4ed39` |
| 6 | left-only, silence, right-only | isolation | leak 0 |
| 7 | short 0020/0020 twice | 512 logical each | restart `e142f7da424b1531` |
| 0 | final silence then loop | 159801 zero | loop count increments |

The source timeline in sample-tick units is:

1. change `display_phase` from navy to the source color;
2. hold muted/internal-zero for 53267 ticks;
3. retain the old register order and accept the source START;
4. keep the source color until 213068 ticks from START (159801 for each pan);
5. accept the explicit stop/reset, leave external mute off, and wait for 32
   consecutive internal-zero ticks (plus ADPCM-B request/active clear);
6. change to navy and start the 79901-tick gap (53267 between left/right);
7. for white, keep white during the 79901-tick verified-zero gap and restart
   without reconfiguration; after its second verified natural end, change to
   navy for 159801 ticks.

FM splits only the old final key-on write from its configuration program. SSG
keeps its four old writes contiguous and launches the complete program after
pre-roll, after waiting for the established free-running-divider alignment at
`chip_cycle_mod432=428` and `sample_tick_count mod 128=53`. With the YM2610
SSG prescaler, JT49 `cen16`, and period 0020, the complete tone waveform has a
128-public-sample repeating relationship; the second condition therefore
returns the retained tone counter to the same measurement phase on every
loop. Focused one- and two-loop regressions reproduce the Phase 2A hash
without a program-handoff gap. ADPCM-A/B retain the existing
`chip_cycle_mod432` alignment waits, so their
START acceptance can follow the one-second timer by a bounded scheduler
alignment interval while color is already stable and internal audio remains
zero. Fixture logs record both the color timer boundary and accepted START
tick; the 53267-tick pre-roll counter itself is exact.

The pristine ADPCM-A counter does not reset every internal `on`/`roe_n`
pipeline register. A soft reset injected during six-voice playback can
therefore leave harmless raw ROM-request pulses during the write-free boot
hold even though internal and external audio are both known zero. HW-0 does
not hide or change that pinned-source behavior. The reset TB requires zero
audio and zero accepted writes throughout boot, then requires both ADPCM-A and
ADPCM-B requests clear after the unchanged initial-silence program and before
the blue FM announcement.

Phase 4A sets its 4096 goal only after `start_b()` returns, but its monitor has
already hashed one active boundary sample. Thus the published stereo hash is
over 4097 active samples. HW-0 aligns START, first logical consume, and first
non-zero to that contract and records `counts=.../4097`; shortening it to 4096
changes the hash to `a92e942c75142561` and is rejected.

The short natural/restart anchor is likewise a fixed 1024-public-sample window
containing 512 logical nibbles. Raw decoder `chon` is not the end boundary: it
may remain asserted with PC-GATE output already at digital zero until a later
command RESET. The integrated TB caps each restart hash at the formal 1024
samples, checks 512 logical consumes independently, then checks EOS, public
request/active clear, zero latency, and stale-prefix count separately.

The HW-0 ADPCM-B active output is a sequencer/debug status, not an audio-path
control. It asserts from the first explicitly routed ROM request, stays latched
between requests, and clears on command RESET or EOS before being routed
through the existing HW-0 ports. The command latch alone is intentionally not
used as start status because it leads the decoder-active boundary by one public
sample. The decoder's actual `chon` remains local to `jt10_adpcm_drvB`;
synthesizable HW-0 RTL does not inspect it hierarchically. PC-GATE alone
continues to own ROM request qualification, decoder activity, audio lane
gating, and natural end.

The TB uses individual `$isunknown` calls for left, right, sample strobe,
phase/error controls, each PSG channel and sum, and address/data during every
valid A/B ROM request. An upstream idle ADPCM-A output-enable pipeline is a
don't-care until it owns a request; it is not treated as a valid fetch.

## QSF/QIP assignments saved for audit

The QSF uses Tcl `source` only for the two board adapters and registers the
three missing MiSTer shell PLL authorities plus the core QIP through Quartus'
`QIP_FILE` assignment:

```tcl
source sys_ym2610_hw0.tcl
source ../../sys/sys_analog.tcl
set_global_assignment -name QIP_FILE ../../sys/pll_hdmi.qip
set_global_assignment -name QIP_FILE ../../sys/pll_audio.qip
set_global_assignment -name QIP_FILE ../../sys/pll_cfg.qip
set_global_assignment -name QIP_FILE files_ym2610_hw0.qip
```

The core QIP is not executed directly as Tcl. Quartus supplies
`$::quartus(qip_path)` while processing a `QIP_FILE`; direct `source` from the
QSF does not provide that QIP context. The static audit requires zero direct
QIP `source` commands and exactly four QSF `QIP_FILE` assignments. Without
running Quartus, it also models `$::quartus(qip_path)` as the directory holding
each QIP, expands every relative path, and requires every target to exist.

Production `sys/sys.qip` selects `sys/pll_q17.qip`, whose four authorities are
the core, HDMI, audio, and HDMI-reconfiguration PLL QIPs. HW-0 registers that
same four-QIP set: the core PLL through `sys_ym2610_hw0.qip` and the other three
through the QSF. The recursive audit reaches seven QIP nodes, ten generated
synthesis sources, three nested PLL constraint QIPs, and the existing
`sys/sys_top.sdc`. It requires exactly one definition each for `pll_hdmi`,
`pll_cfg_hdmi`, and `pll_audio` and rejects individual-source duplication.

The board adapter selects `sys_ym2610_hw0.qip`; the core QIP assigns 66 files:

- 13 `rtl/ym2610_hw0/` hardware/compatibility sources;
- five formal PC-GATE overlay sources;
- seven direct immutable JT10 pin leaves;
- 35 shared JT12 FM/mixer sources;
- six shared JT49 sources.

Together with the 33 MiSTer shell source/constraint assignments and ten PLL
generated sources, the recursively expanded static project graph is 109
source/constraint paths. `audit_ym2610_hw0.py` prints and saves the exact
66-path core list on every run. It reports missing path 0, duplicate source 0,
duplicate module 0, absolute path 0, production `files.qip`/`rtl/emu.sv`
references 0, testbench or diagnostic references 0, and
production-to-HW-0 references 0.

## Verification results

Observed before commit from `run_ym2610_hw0.sh` and the formal-overlay
regression runners:

- non-`SIMULATION` full loop: 3/3 normalized output match;
- `SIMULATION`: exact normalized match to non-`SIMULATION` run 1;
- phase hashes/counts:
  `8aadd7a6819038e5/54730095b12b6325/adf8cc2f2f81c1b9/32cb891931682fe9/1207d84363d4ed39`
  and `4096/4096/4096/8192/4097`;
- accepted writes: 174; BUSY timeout/write-while-BUSY: 0/0;
- cadence/width/drop/duplicate/X: 0/0/0/0/0;
- pre-ready X/non-zero, control X, PSG X, and valid ROM A/B X: all zero;
- cold/final silence: 32768/32768 public zero samples;
- ADPCM-B command RESET reaches zero in two public samples and has zero
  post-stop requests;
- pan leak: 0; left/right audible non-zero counts: 4086/4086;
- natural logical counts: 512/512; public zero latency: 3/3;
- stale restart prefix: 0; both restart hashes `e142f7da424b1531`;
- self-test loop restart count: 1;
- SSG B/C spurious output, idle ADPCM fetch, and Scenario G arithmetic
  overflow events: all zero;
- Icarus inner top and minimal `emu` elaborate. The full inner compile emits
  57 inherited timescale/LUT warnings plus 16 Icarus constant-select
  sensitivity notices; the minimal `emu` compile emits the same 16 notices;
- Verilator return code: 0; warning count: 145. Types are
  `DECLFILENAME=1`, `EOFNEWLINE=19`, `GENUNNAMED=10`,
  `PINCONNECTEMPTY=11`, `PROCASSINIT=12`, `SYNCASYNCNET=1`,
  `TIMESCALEMOD=6`, `UNUSEDPARAM=5`, `UNUSEDSIGNAL=72`,
  `WIDTHEXPAND=6`, and `WIDTHTRUNC=2`;
- Verilator error, latch-warning, and combinational-loop-warning counts: 0;
- static project graph: 100 sources (66 core plus 34 MiSTer shell), missing
  paths 0, duplicate sources 0, duplicate modules 0, absolute paths 0,
  production `files.qip`/`rtl/emu.sv` references 0, test/diagnostic/tmp
  references 0, and production-to-HW-0 references 0;
- Phase 4A, Phase 4A-FIX, Phase 3C, Phase 3B, Phase 3A, Phase 2B, and
  Phase 1C: PASS with the formal PC-GATE overlay;
- the combined Phase 4A runner created 12 repository-root waveform files
  before entering its nested regression chain. The nested Phase 1C functional
  and lint work completed, then its untracked-artifact guard rejected those
  outer-runner files. They were moved unchanged outside the repository and
  Phase 1C was rerun with the formal overlay: all four FM encodings,
  non-`SIMULATION` determinism, `SIMULATION`, Verilator, production isolation,
  Sacred-TB preservation, and repository-artifact guard PASS. No RTL, runner,
  compatibility, overlay, or production source was changed for this rerun;
- `git diff --check`: PASS;
- Quartus on macOS: not run.

### Startup/pacing verification

The startup/pacing runner completed on the final candidate before commit:

- exact hardware-count model, two loops: boot/pre-roll/dwell/gap/pan/pan-gap/
  natural-gap/final =
  `159801/53267/213068/79901/159801/53267/79901/159801`, phase visits 17,
  sound starts 18, accepted writes 328, loop count 2;
- full integrated self-test: non-`SIMULATION` 3/3 normalized match and
  `SIMULATION` exact normalized match, with two complete loops in every run;
- first- and second-loop hashes:
  `8aadd7a6819038e5/54730095b12b6325/adf8cc2f2f81c1b9/32cb891931682fe9/1207d84363d4ed39`,
  counts `4096/4096/4096/8192/4097` in both loops;
- natural/restart: logical `512/512/512/512`, public window
  `1024/1024/1024/1024`, all four hashes `e142f7da424b1531`, stale prefix 0;
- reduced-duration integrated timeline, shown as
  `color/start/stop/verified-zero` public ticks:
  FM `280/408/8602/8883`, SSG `9011/9146/17339/17373`, A0
  `17501/17630/25823/25868`, A6 `25996/26124/34317/34364`, stereo B
  `34492/34620/42813/42847`, left `42975/43104/45152/45186`, right
  `45314/45444/47492/47526`, first natural play
  `47654/47784/48809/48844`, restart `49356/50381/50416`;
- BUSY timeout, write while BUSY, zero timeout, phase error, cadence error,
  width error, missed/duplicate sample tick, X/Z, pan leak, SSG B/C output,
  idle ADPCM fetch, ADPCM-A6 overflow, ADPCM-B post-stop request, and stale
  prefix: all zero; ADPCM-B RESET-to-zero latency: two public samples;
- reset injection during FM, ADPCM-A six-voice, and ADPCM-B: immediate final
  audio zero, navy display, ten video pixels over twenty system clocks, boot
  256/256 ticks in the reduced model, boot writes 0, and restart from FM;
- Icarus inner top, `SIMULATION` top, reset fixture, and minimal MiSTer `emu`:
  elaborate PASS. Each full compile reports 73 inherited-timescale/LUT or
  constant-select sensitivity diagnostics and no error;
- Verilator: return code 0, warning count 154, latch 0, combinational loop 0.
  Warning types are `DECLFILENAME=2`, `EOFNEWLINE=19`, `GENUNNAMED=10`,
  `PINCONNECTEMPTY=11`, `PROCASSINIT=12`, `SYNCASYNCNET=1`,
  `TIMESCALEMOD=6`, `UNUSEDPARAM=5`, `UNUSEDSIGNAL=70`,
  `WIDTHEXPAND=16`, and `WIDTHTRUNC=2`;
- static project/QIP audit: 109 recursively expanded paths, 66 core paths,
  ten PLL generated sources, seven QIP nodes, missing/duplicate/absolute/test
  source paths 0, QIP path expansion simulated PASS;
- Phase 4A single-shot and Phase 4A-FIX formal PC-GATE lifecycle smoke:
  PASS, including final/restart anchor `e142f7da424b1531`;
- formal PC-GATE overlay, pristine JT10 15-file manifest, JT49,
  compatibility/warm-up layers, production project/source, HW-0 QSF/QIP,
  the 23 protected diagnostics, and Sacred TB: unchanged;
- `git diff --check`: PASS; Quartus on macOS: not run.
