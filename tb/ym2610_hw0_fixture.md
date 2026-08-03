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
  also requires request and active clear. A PCM stop timeout records S6 FAIL
  and continues. Cadence/width corruption, phase overflow/illegal state,
  BUSY failure, write-while-BUSY, or ROM range corruption halts, mutes, and
  selects red.

### Hardware duration constants

| Contract | Public ticks | Seconds at 53.267040 kHz |
|---|---:|---:|
| boot navy | 159801 | 2.999998 |
| color-only pre-roll | 53267 | 0.999999 |
| FM/SSG reference dwell | 159801 | 2.999998 |
| FM/SSG navy gap | 53267 | 0.999999 |
| each PCM attempt | 53267 | 0.999999 |
| PCM attempt gap | 26634 | 0.500009 |
| PCM phase result hold | 159801 | 2.999998 |
| white natural-end gap | 79901 | 1.500008 |
| final summary | 532670 | 10.000000 |

The exact-count pacing TB drives one logical tick per simulation clock and
checks all diagnostic constants, 54 attempt closures, and two summaries over
two complete loops. The integrated audio TB
uses reduced timing parameters only to make four full JT10 runs practical;
it retains the production measurement alignment/counts and separately proves
the 144/6 public waveform contract.

## Self-test/hash windows

| Phase | Contract | Hash samples | Expected stereo FNV-1a |
|---:|---|---:|---|
| 0 | boot silence | 159801 zero, zero writes | zero contract |
| 1 | FM encoding 1, ALG7 | 4096 after 4096 attack | `8aadd7a6819038e5` |
| 2 | SSG A, period 0020, volume 0F | 4096 after 263 startup | `54730095b12b6325` |
| 3 | ADPCM-A voice 0, six attempts | first 4096 each | `adf8cc2f2f81c1b9` |
| 4 | ADPCM-A six-voice Scenario G, six attempts | first 8192 each | `32cb891931682fe9` |
| 5 | ADPCM-B 0020–004f/8000/C0/FF, six attempts | Phase 4A boundary + 4096 each | `1207d84363d4ed39` |
| 6 | left-only ×3, right-only ×3 | isolation | leak 0 |
| 7 | short 0020/0020 plus restart, three pairs | 512 logical each play | restart `e142f7da424b1531` |
| 8 | five-row × seven-column summary | 532670 | result matrix |

The source timeline in sample-tick units is:

1. change `display_phase` from navy to the source color;
2. hold muted/internal-zero for 53267 ticks;
3. retain the old register order and accept the source START;
4. keep FM/SSG audible for 159801 ticks; keep each PCM attempt open for
   53267 ticks without stretching its short sample;
5. accept the explicit stop/reset, leave external mute off, and wait for 32
   consecutive internal-zero ticks (plus ADPCM-B request/active clear);
6. retain the PCM phase color for a 26634-tick muted gap and repeat the same
   verified START six times (three left plus three right for pan);
7. after each PCM phase, retain its color/result for 159801 ticks;
8. for white, keep white during the 79901-tick verified-zero gap and restart
   without reconfiguration; repeat that pair three times;
9. show the dark-navy 5×7 summary for 532670 ticks, then return through the
   159801-tick boot/navy loop head.

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

## PCM path diagnostic contract

The change baseline is branch `ym2610-family-bringup`, HEAD
`b9bcf818d97cb7937106bf1ce2f78b1b1e4beb9a`, subject
`Stabilize YM2610 HW-0 startup and pacing`, with clean tracked/staged state.
The protected 23-file diagnostic aggregate, Sacred TB metadata, formal
PC-GATE tree, pristine 15-file manifest, JT49 tree, HW-0 project files, and
production project files matched their recorded authorities before editing.

The magenta-to-red hardware symptom maps exactly to old state `H_B_DWELL`
(36): it halted whenever the status-only `hw0_adpcmb_active` proxy cleared
during the four-second colored dwell. A short single-shot correctly reaches
EOS and clears the proxy before that dwell ends. The old generic predicate
therefore converted completion into `phase_error`; identical predicates in
left/right dwell would also block later phases. The new sequencer never uses
that proxy as a dwell owner.

Each PCM attempt independently latches these seven columns:

| Bit | Evidence | PASS predicate |
|---:|---|---|
| S0 | RAW_REQ | target public ROM request observed |
| S1 | CAPTURE | qualified zero-wait request/address/data transaction |
| S2 | PROGRESS | at least two addresses and two distinct ROM bytes |
| S3 | SOURCE_LANE | explicitly routed ADPCM-A or ADPCM-B L/R non-zero |
| S4 | JT10_FINAL | JT10 final internal L/R non-zero |
| S5 | HW_OUTPUT | post-mute HW-0 `AUDIO_L/R` non-zero |
| S6 | STOP_RESTART | request/final zero and stop; pan isolation or restart when applicable |

The current attempt retains a seen bit, fail bit, four-bit saturating event
count, first-event tick low 16 bits, eight-bit saturating request/address
change counts, an eight-bit saturating distinct-address progression proxy, and
first/last 24-bit address. For these sequential deterministic fixtures the
first address plus each public address change is the distinct-byte count; no
address-history CAM is synthesized. A three-bit completed-attempt counter,
separate from the sequencer's current attempt index, drives the lower boxes so
a gap can never make the next pending attempt appear complete. Five seven-bit
row accumulators AND the
attempt results. No hash hardware is synthesized. ADPCM-A observation begins
only on accepted key-on, excluding clear-boundary dummy traffic. JT10 final,
ready-gated HW-0 pre-mute, and post-mute AUDIO L/R are separately routed; the
positive TB requires equality across the latter two boundaries whenever mute
is released.

Codes 4–10 are nonfatal and leave a red cell before proceeding. Codes 1–3
and 11–15 halt full-screen red. Mapping is: none 0, BUSY timeout 1,
write-while-BUSY 2, cadence/width 3, no request 4, no capture/progress 5,
lane zero 6, final zero 7, output zero 8, stop/pan 9, EOS/restart 10, illegal
phase 11, reset synchronizer 12, ROM range 13, reserved 14, unknown/internal
15. Simulation treats address/data/audio X/Z as fatal test failure even though
hardware cannot synthesize an X detector.

The upper-right white/magenta checker permanently identifies the diagnostic
RBF. During phases 3–7 the top seven 60×32 boxes show S0–S6, and six bottom
attempt boxes show completed/current/pending. The ten-second phase-8 matrix
uses yellow/orange/magenta/cyan/white rows and the same seven columns. The
fatal screen retains red and shows the four-bit code as bottom white/black
boxes, MSB first.

Negative controls instantiate only the observer with explicit stub inputs:
request without capture, legal progress with a zero lane, live final with a
zero post-mute output, and suppressed EOS/restart. Each produces the expected
red cell and code. A second no-reset pass runs all five diagnostic rows,
proves every later phase remains runnable, and retains the earlier red cells
in the complete summary matrix; no force or fault path exists in synthesizable
HW-0.

Reset injection targets A0, A6, and stereo B attempt dwell. It requires
immediate final zero/navy, continued H/V timing, cleared current status and
5×7 matrix, the complete boot hold with zero writes, and restart from FM.

Windows handoff remains: close Quartus, synchronize the complete repository,
delete `hw\ym2610_hw0\db`, `incremental_db`, and `output_files`, open
`hw\ym2610_hw0\MegaVGMDrive_YM2610_HW0.qpf`, select revision
`MegaVGMDrive_YM2610_HW0`, run Full Compilation, and use
`output_files\MegaVGMDrive_YM2610_HW0.rbf`.

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

### PCM path diagnostic verification

The final HW-0 PCM diagnostic candidate completed the required non-Quartus
verification before commit:

- hardware-count pacing model, two loops: boot `159801`, reference/PCM
  pre-roll `53267`, reference dwell/gap `159801/53267`, PCM observation and
  inter-attempt silence `53267/26634`, result hold `159801`, natural silence
  `79901`, and summary `532670` sample ticks; 16 diagnostic phase visits,
  64 starts, 54 PCM attempts, 478 accepted writes, and two summaries;
- non-`SIMULATION` full-loop runs: 3/3 normalized match; `SIMULATION`: exact
  normalized match. Every run completed two loops and reported summary matrix
  `7ffffffff`, valid rows `1f`, and error code 0 in both loops;
- hashes in every run and both loops: FM `8aadd7a6819038e5`, SSG
  `54730095b12b6325`, ADPCM-A voice 0 `adf8cc2f2f81c1b9`, ADPCM-A six-voice
  `32cb891931682fe9`, ADPCM-B stereo `1207d84363d4ed39`, and ADPCM-B restart
  `e142f7da424b1531`;
- per-loop attempt counts: ADPCM-A0 6, ADPCM-A6 6, ADPCM-B stereo 6, pan 6,
  and natural/restart 3. Across two loops the contract reported
  `12/12/12/12/6`, with all seven stage bits seen and no attempt fail bit;
- BUSY timeout, write while BUSY, zero timeout, fatal error, sample drop,
  duplicate sample, and pan leak: all zero. Relevant-event X/Z: zero, with
  category counts `0/0/0/0/0/0` for control, audio, ADPCM-A lane, ADPCM-B
  lane, ADPCM-A ROM, and ADPCM-B ROM;
- negative controls: ROM response stop, source-lane zero, external-output
  mute, and EOS suppression all continued through five diagnostic rows,
  reached summary, and retained the expected red cells; full-screen fatal red
  was not asserted;
- video contract: white/magenta checker marker, seven status boxes, six
  attempt indicators, 5-by-7 summary, and four-bit fatal code display: PASS;
- reset injection at ADPCM-A0 state 22, ADPCM-A6 state 30, and ADPCM-B state
  38: immediate output zero, video continuity/navy, diagnostic clear, reduced
  boot 256 ticks with zero writes, and restart from FM: PASS in all three;
- Icarus inner top, `SIMULATION` top, reset fixture, and minimal MiSTer `emu`:
  compile/elaborate PASS. The three full compiles each report 57 inherited
  warnings and 26 constant-select sensitivity notices; the minimal `emu`
  compile reports the same 26 notices and no error;
- Verilator: return code 0, warning count 176, latch 0, combinational loop 0.
  Warning types are `DECLFILENAME=3`, `EOFNEWLINE=19`, `GENUNNAMED=10`,
  `PINCONNECTEMPTY=11`, `PROCASSINIT=12`, `SYNCASYNCNET=1`,
  `TIMESCALEMOD=6`, `UNUSEDPARAM=10`, `UNUSEDSIGNAL=73`,
  `WIDTHEXPAND=29`, and `WIDTHTRUNC=2`;
- static project/QIP audit: 109 recursively expanded paths, 66 core sources,
  ten PLL generated sources, and seven QIP nodes; missing, duplicate-source,
  duplicate-module, absolute, production-source, simulation-source,
  diagnostic-source, and temporary-source references: all zero;
- Phase 4A-FIX lifecycle and Phase 4A single-shot formal PC-GATE smoke:
  PASS, including deterministic non-`SIMULATION`, matching `SIMULATION`,
  Verilator return code 0, and restart anchor `e142f7da424b1531`;
- register microcode table, deterministic ROM contents/generation, formal
  PC-GATE overlay, pristine JT10 15-file manifest, JT49, production project,
  HW-0 QPF/QSF/QIP, the 23 protected diagnostics, and Sacred TB: unchanged;
- `git diff --check`: PASS; Quartus on macOS: not run.
