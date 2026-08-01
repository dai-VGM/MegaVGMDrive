# Phase 4A-FIX JT10 ADPCM-B lifecycle regression

## Scope and result

Phase 4A-FIX applies the Phase 4A-P selected `PC-GATE` patch set to a
standalone/test-only source overlay.  It does not connect JT10 to a production
build and does not cover the Phase 4A single-shot matrix, repeat, ADPCM-A/B
concurrency, VGM/parser/data-block/DDR integration, or Quartus.

The formal command was:

```text
bash tb/run_jt10_phase4afix.sh
```

It completed with `PHASE4AFIX_LOCAL_AUDIT PASS`.  Generated sources, binaries,
and logs were confined to `/tmp/jt10_phase4afix_*` and the child runners'
`/private/tmp/jt10-phase*` directories.

## Baseline and protected diagnostics

- Branch: `ym2610-family-bringup`
- Base HEAD: `48df6033e104c3685488f068f9fe9e4c83c34c01`
- Tracked diff at entry: clean
- Staged diff at entry: clean
- Existing untracked diagnostics: 23
- Protected before/after digest and stat manifests: byte-for-byte identical
- Sacred `tb/tb_jt49_audio_compare.sv` SHA-256:
  `35cbd96d057e9889815229f2c0e154614eea7956ae895afdb74f6ace2b65406c`;
  size `4939`, mtime `1784686524`, inode `21984214`.

The 23-file entry manifest was:

| File | SHA-256 | size | mtime | inode |
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

## Source and overlay reproducibility

- Upstream repository: `https://github.com/jotego/jt12`
- Upstream base: `6d51e0b6f64728c73408079b2f5ffe911bfd88a9`
- Pristine pinned JT10 files: 15/15 Git blob and SHA-256 matches
- Production JT12 tree: `d4a5b9be7720f802f706ab8449bf2e6269f1240a`
- Production JT49 tree: `63a434df533450acc14170bc3d2e91fa13faf806`
- Compatibility tree: `da66c91ef1c7a15f5ff70385a81ea67f9bb88dcd`
- Warm-up wrapper SHA-256:
  `b5ec92841b2653b1e3615587aad4c1c06c9d4eb4de1334a32ce58fa7bb3e18f0`
- `files.qip` Git blob: `71d98974f2672207467eac493c06bbc23c74e45b`
- QSF Git blob: `898ae5a61d7c1f94d9f824a9007fcadff65383f9`
- Production standalone-JT10 references: 0

Compatibility plus V1 plus PC-GATE was independently generated twice.  The
complete generated-tree manifest digest was
`b00f53ed1149a8d4fc18fc9bc543bb2f8fd0509791d32e0814388d0f4d9d30ad`
for both runs.  Generator output digest was
`53f1030fc7bd0352ab128fd883ce9e0d008a957c5cd4303656d2e0b964e95a8c`
for both runs.

PC-GATE relative to V1 is a 168-line unified diff over four modules, with 45
added and 9 removed lines; its SHA-256 is
`ffed023863b0eb5da8956d58c439243bc7a2bdb4b18a8153b8444f0d67b1d471`.
V1 plus PC-GATE relative to the compatible base is a 243-line unified diff
over five modules, with 95 added and 39 removed lines; its SHA-256 is
`da120d85168744f87cad009530a9191936e99adc3be7d026c4ad2b5229e3e8cb`.

| Overlay file | SHA-256 |
|---|---|
| `jt10_adpcm_div.v` | `ff7ec22d2662b8e837e58e14877fabe62cb8a4a73015736e81e03e9723638856` |
| `jt10_adpcm_drvB.v` | `183a4143885a17757b0788c268157fc36056e47f06136b20e5595dc5d87e4731` |
| `jt10_adpcmb_cnt.v` | `34e956261947b1257fdd4a0d151d2b147ed6a6b7d684b3c66866cc64b9c95a75` |
| `jt10_adpcmb_gain.v` | `5f5098aacce66460b0918e7a8daa944bd1193840bfad69a796c489dd77e52fee` |
| `jt10_adpcmb_interpol.v` | `33079ac1bef4782c0e58177e69d12c64d7bebfcfd622065887818b39f1398100` |

The sorted five-file SHA manifest hashes to
`a165479eb34af933ff736e75e9a705f1855f43800858652f08fda4c7a69372a7`.
Every formal overlay file compared byte-exact with both independently
generated copies.  File list differences, extra changes, missing changes,
`stop_clr`, active SIMULATION preprocessor branches, testbench-only `initial`,
`force`, and `release` constructs were absent.  PC-CLEAR was not mixed in.
The generator preserves upstream trailing spaces on divider line 40, driver
line 115, and counter line 66.  These three `git diff --check` findings are
retained intentionally because normalizing them would break byte-exact
overlay/generated equivalence; there are no other whitespace findings.

## Patch composition

- V1 / X-A: asynchronous active-low chip reset covers every interpolator
  state register and divider `d/r`.  It adds no natural-end, command-RESET,
  `chon`, gain, or lane reset and does not include V2/V3 expansion.
- PO-GATE / O-A: only the ADPCM-B digital lane contribution is zero when
  `chon=0`; internal decoder/interpolator/gain hold is permitted and the
  final shared output is not globally gated.
- PR / R-B: raw request is qualified by `(chon | restart)`, preserving first
  and terminal low-nibble fetches while making every inactive soak quiet.
- PS: accepted START clears EOS/pending terminal state and stale
  interpolation/gain/lane validity, restores the source-defined Delta-N
  phase, and reuses the existing address/nibble/active and decoder restart
  paths.
- PC-CLEAR rejection: its stop-state clearing leaves one stale public sample
  in `RESET=01 -> Control=00 -> START=80`; PC-GATE has stale prefix zero.

## F0: source separation

- Pristine JT10: 15 source files, unchanged and blob-matched
- Overlay: exactly five changed Verilog modules
- Manifest modules: 65
- Duplicate modules: 0
- Pristine/overlay simultaneous versions: 0
- Undefined modules: 0 (Icarus elaboration passed)
- Production build references: 0

The Phase 1C/2B/3A/3B/3C runners retain their pristine default and accept the
overlay only when `JT10_OVERLAY_ROOT` is set.  The helper replaces precisely
the five changed module files in temporary source roots; functional test
sequences are unchanged.

## F1-F10 lifecycle result

| Test | Formal result |
|---|---|
| F1 pan then level | 16384 samples; raw/capture/logical/decoder/cursor/nonzero/X-Z all 0; interpolation/gain/lane/final known zero; hash `c74b47c8c74a2325` |
| F1 level then pan | Same 16384-sample result and hash |
| F1 full configure, no START | 32768 samples; every event and output 0; hash `9c735bed0a722325` |
| F2 primary playback | raw/logical/decoder `512/512/512`; interpolation/gain/lane `1024/1024/1024`; cursor `0020ff/low`; EOS 1, active 0; X/Z 0 |
| F3 natural end | 32768-sample soak; request/capture/logical/decoder/cursor 0; digital zero at sample 4; no later nonzero; hash `67ae23c008f2401b` |
| F4 command RESET | RESET after logical consume 100; 32768-sample soak; all progression 0; digital zero at sample 3; no later nonzero; hash `e755314ec38c1919` |
| F5 inactive request soak | configure-before-START, natural end, and command RESET all observed for 32768 samples with raw/capture/logical/decoder/cursor/range/output/X-Z 0 |
| F6 natural restart | all core/final hashes and five landmarks match; EOS lifecycle correct; stale prefix 0 |
| F7 direct RESET restart | all core/final hashes and five landmarks match; stale prefix 0 |
| F8 RESET to 00 restart | all core/final hashes and five landmarks match; PC-CLEAR's one-sample stale prefix is absent |
| F9 long inactive restart | 65536 samples with all progression/output/X-Z 0; hash `6a5b37c38744401b`; restart fully matches |
| F10 global reset | reset during nonzero playback and after stop makes V1 interpolation/gain/lane/public state known zero and active clear; cold contract remains valid; restart fully matches |

F2 and every restart used these active-owned measurements:

```text
raw request hash     e60907109cc90925
logical hash         d3f50a660ff4da1a
Delta-N hash         3ef011c519a87325
decoder hash         46ce068d48f530a5
interpolation hash   977cceaa11432cb1
active gain hash     a009ad964647c074
active lane hash     a9a4d74927a92055
final hash           e142f7da424b1531
relative landmarks   85 / 86 / 373 / 147541 / 147542
logical consume      512
final cursor         0020ff / low
stale prefix         0
```

The historical Phase 4A-X/RV1 full-window gain/lane hashes
`c44dda0e59862d8a` and `16e284660dfd24e1` remain unchanged provenance.  The
`a009...`/`a9a4...` hashes above deliberately cover active-owned commits and
exclude post-stop commits, matching the Phase 4A-P metric definition.

Natural end sets EOS and clears active.  Accepted START clears EOS, asserts
active, and every completed restart sets EOS again.  Global reset uses the
source-defined EOS reset value zero.  No stale contribution or repeat restart
was observed.

## Transport, sample, idle, and determinism

- Accepted writes: 213
- BUSY duration: 190-193 system cycles
- BUSY hash: `ef51df3830035415`
- BUSY timeout / write while BUSY: 0 / 0
- Public cadence / strobe width: 144 / 6 system cycles
- Cadence errors / width errors: 0 / 0
- Drops / duplicate pulses: 0 / 0
- Relevant X/Z: 0
- ADPCM-A active/raw/logical/lane: `0/0/0/0`
- FM idle violations: 0
- SSG data/control idle violations: `0/0`
- Classification: output `ZERO`, request `GATED`, restart `REPLAY`, selected
  PC-GATE, failures 0
- non-SIMULATION: three runs, every normalized count/hash/landmark matched
- SIMULATION: full normalized summary matched non-SIMULATION run 1

## Phase 4A-P reproduction

The formal overlay passed the existing PC-GATE selected-candidate smoke:
natural zero 4, RESET zero 3, inactive raw/capture 0, logical 512, cursor
`0020ff/low`, stale prefix 0, active hashes unchanged, and all restart hashes
and landmarks matched.  No Phase 4A-P diagnostic file was changed.

## Phase 1-3 overlay regressions

### Phase 3C

Scenarios A-L each passed the existing non-SIMULATION three-run deterministic
contract, SIMULATION comparison, and Verilator elaboration.  Selected fixed
results:

- Scenario G logical consume `16382`, dummy request `1`
- G aggregate L/R `c2b40827f24142ce`
- G final L/R `3f7b4b26b65b7091`
- G stereo `32cb891931682fe9`
- I final L/R `13eca1bccb000782`
- K final L/R `f7f493af1ca508f7`
- G arithmetic compares `1467018`, mismatch `0`
- G ownership and Class-C violations `0/0`
- cadence/width `144/6`, errors/drop/duplicate/X-Z all 0
- ADPCM-B idle during the ADPCM-A regression

### Phase 3B and 3A

Phase 3B voice 1-5 non-SIMULATION three-run results and every SIMULATION
comparison passed.  Canonical hashes remained fetch
`0395a9d360fa7ca4`, address `ee97dacc6be4aac1`, ROM
`8a7e8727bcc15bea`, and decode `f04661980311a408`; aligned voice 0-5 waveform
was `5b52746e5b1c3d75`.  Stereo hashes remained voice 0
`adf8cc2f2f81c1b9`, voice 1 `17e3063b8387e235`, voices 2/3
`a4240e15b4fa2d55`, and voices 4/5 `baa7fbb9cf648ced`.

Phase 3A passed start shift, changed ROM, left/right pan, global mute,
key-off, natural end, retrigger, three-run determinism, SIMULATION comparison,
and its existing hash/landmark assertions.

### Phase 2B and 1C

Phase 2B SSG chA/B/C passed three-run and SIMULATION comparison.  Fixed
hashes remained raw `a05a9500edbbca25`, PSG `3beb13acc8e83f25`, final
`54730095b12b6325`, volume-zero mute `28c31cf8df2ec325`, mixer-disabled
positive DC `0f24568f5401b325` (512/512 samples at value 8160), and
period-change `ce0045fbf79de325`.

Phase 1C FM ch1/ch2/ch5/ch6 passed.  Fixed hashes remained steady
`8aadd7a6819038e5`, attack `c8bafcdd6f79173d`, and mute/key-off
`28c31cf8df2ec325`; cadence/width remained `144/6`.  Four-channel waveform
alignment is zero with same polarity and phase.

## Tool results and warnings

- Icarus non-SIMULATION compile/elaboration: return code 0; four warnings
- Icarus SIMULATION compile/elaboration: return code 0; the same four warnings
- Icarus warnings: inherited/missing timescale, two 64-entry LFO LUT
  sensitivity warnings, and the aggregate missing-time-unit warning
- Phase 4A-FIX Verilator: return code 0, 602 warnings
- Phase 4A-FIX warning classes: BLKSEQ 176, DECLFILENAME 1, EOFNEWLINE 20,
  GENUNNAMED 10, PINCONNECTEMPTY 8, PINMISSING 4, PROCASSINIT 157,
  SYNCASYNCNET 1, TIMESCALEMOD 61, UNUSEDPARAM 7, UNUSEDSIGNAL 86,
  WIDTHEXPAND 49, WIDTHTRUNC 22
- Phase 3C Verilator: return code 0, 592 warnings
- Phase 3C warning classes: BLKSEQ 218, DECLFILENAME 2, EOFNEWLINE 20,
  GENUNNAMED 10, PINCONNECTEMPTY 8, PINMISSING 4, PROCASSINIT 120,
  SYNCASYNCNET 1, TIMESCALEMOD 61, UNUSEDPARAM 5, UNUSEDSIGNAL 102,
  WIDTHEXPAND 24, WIDTHTRUNC 17
- Phase 3B, Phase 3A, Phase 2B, and Phase 1C representative Verilator
  lint/elaboration: return code 0 through their complete regression runners
- Duplicate/undefined module, reset polarity/width, fatal latch,
  combinational-loop, unreachable-branch, and fatal signedness errors: 0

Verilator was used only for lint/elaboration; non-SIMULATION Icarus remained
the X/Z authority.

## Production isolation

Blob/tree comparison against the base HEAD passed for the production JT12 and
JT49 trees, top, parser, DDR backend, MD/YM2203 sound modules, `emu`,
`sys_top`, SegaPCM, production mixer, compatibility layer, warm-up wrapper,
`files.qip`, and QSF.  Production build-list references to the candidate,
Phase 4A-FIX helpers, prior Phase 3C-R/4A diagnostics, and the pinned test tree
were zero.  No repository simulation artifact was present.  Quartus was not
run.
