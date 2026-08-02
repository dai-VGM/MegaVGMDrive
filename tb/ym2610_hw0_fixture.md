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
- Global reset receives at least six asserted CENs. The core continues running
  while the first five internal samples are hidden; the sixth is the first
  public sample. The sequencer then requires ready, known-zero audio, and BUSY
  clear before its first write.
- Writes use status-clear wait → address → data → BUSY-assert wait → BUSY-clear
  wait. A 16-bit watchdog failure or a data write while BUSY halts, mutes, and
  makes video red.
- Durations use public-sample rising edges, never a fixed system-cycle delay.

## Self-test/hash windows

| Phase | Contract | Hash samples | Expected stereo FNV-1a |
|---:|---|---:|---|
| 0 | cold silence | 32768 zero | zero contract |
| 1 | FM encoding 1, ALG7 | 4096 after 4096 attack | `8aadd7a6819038e5` |
| 2 | SSG A, period 0020, volume 0F | 4096 after 263 startup | `54730095b12b6325` |
| 3 | ADPCM-A voice 0 | first 4096 | `adf8cc2f2f81c1b9` |
| 4 | ADPCM-A six-voice Scenario G | first 8192 | `32cb891931682fe9` |
| 5 | ADPCM-B 0020–004f/8000/C0/FF | Phase 4A aligned boundary + 4096 | `1207d84363d4ed39` |
| 6 | left-only, silence, right-only | isolation | leak 0 |
| 7 | short 0020/0020 twice | 512 logical each | restart `e142f7da424b1531` |
| 0 | final silence then loop | 32768 zero | loop count increments |

Phase 4A sets its 4096 goal only after `start_b()` returns, but its monitor has
already hashed one active boundary sample. Thus the published stereo hash is
over 4097 active samples. HW-0 aligns START, first logical consume, and first
non-zero to that contract and records `counts=.../4097`; shortening it to 4096
changes the hash to `a92e942c75142561` and is rejected.

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
