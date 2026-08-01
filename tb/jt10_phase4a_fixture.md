# Phase 4A standalone JT10 ADPCM-B single-shot fixture

## Scope

This fixture validates the formal Phase 4A-FIX `PC-GATE` overlay as a
standalone JT10/YM2610 source candidate.  It covers register transport,
external-ROM single-shot playback, the complete ADPCM-B arithmetic and audio
path, stop/EOS behavior, and deterministic same-session restart.  It does not
connect the overlay to production and does not cover repeat playback, CPU
memory or record modes, ADPCM-A/B concurrency, YM2610B, VGM commands/data
blocks, DDR, Quartus, or Phase 4B.

The reproducible entry point is:

```text
bash tb/run_jt10_phase4a.sh
```

All generated source trees, executables, SIMULATION raw files, and logs are
created below `/tmp`; no generated artifact is stored in the repository.

## Baseline and protected files

- Branch: `ym2610-family-bringup`
- Base HEAD: `7ae45b1b11a1fe8b43c6d214d56639a4c1bd71be`
- Base subject: `Fix JT10 ADPCM-B lifecycle contracts`
- Tracked and staged diffs at entry: clean
- Existing untracked diagnostics: exactly the expected 23 files
- The 23-file SHA-256/stat manifest was captured before and after the full
  run; content, size, mtime, and inode matched byte-for-byte.  The complete
  46-line manifest SHA-256 is
  `9a423c962e9edda97ca1f83b5a764c15cf9ebae4f4bcba7534a471dbbf62fcf3`.
- Sacred `tb/tb_jt49_audio_compare.sv`: SHA-256
  `35cbd96d057e9889815229f2c0e154614eea7956ae895afdb74f6ace2b65406c`,
  size `4939`, mtime `1784686524`, inode `21984214`.
- Pristine pin: 15/15 entries matched both the Git-blob and SHA-256 manifest.
- Formal overlay: five Verilog files and `PC_GATE_PROVENANCE.md` matched base
  HEAD blobs.
- Production JT49, compatibility scripts, warm-up wrapper, `files.qip`, and
  QSF matched base HEAD.  Two independent compatibility generations matched.
- Production references to the formal overlay and standalone fixture: zero.

The complete protected-file entry manifest is already preserved in
`tb/jt10_phase4afix_fixture.md`; Phase 4A rechecked that same manifest rather
than rewriting any diagnostic.

## Source composition and evidence

The simulation source root is assembled in `/tmp`: the 15 unchanged modules
come from `tb/jt10_pinned/6d51e0b6/`, the remaining JT12/JT49 support comes
from the immutable production source, test-only local-interface compatibility
is generated, and exactly these formal modules replace their pristine copies:

- `rtl/genesis_audio/jt10_ym2610/adpcm/jt10_adpcm_div.v`
- `rtl/genesis_audio/jt10_ym2610/adpcm/jt10_adpcm_drvB.v`
- `rtl/genesis_audio/jt10_ym2610/adpcm/jt10_adpcmb_cnt.v`
- `rtl/genesis_audio/jt10_ym2610/adpcm/jt10_adpcmb_gain.v`
- `rtl/genesis_audio/jt10_ym2610/adpcm/jt10_adpcmb_interpol.v`

There are no duplicate modules.  The compatibility layer reconnects the
locally pinned command-update signal that remains commented in the upstream
top (`rtl/genesis_audio/jt12/jt12_top.v:248-274`); neither the compatibility
scripts nor production top were changed.

The source audit used the pinned upstream commit
`6d51e0b6f64728c73408079b2f5ffe911bfd88a9`, not generic YM2610 knowledge.
Relevant anchors are:

- ADPCM-B MMR decode: `rtl/genesis_audio/jt12/jt12_mmr.v:377-390`
- ADPCM-B top wiring and public ROM interface:
  `rtl/genesis_audio/jt12/jt12_top.v:207-298`
- status mux: `rtl/genesis_audio/jt12/jt12_dout.v:37-44`
- raw request/capture/decode/interpolate/gain/lane:
  `rtl/genesis_audio/jt10_ym2610/adpcm/jt10_adpcm_drvB.v:48-136`
- Delta-N, cursor, active, end, and EOS:
  `rtl/genesis_audio/jt10_ym2610/adpcm/jt10_adpcmb_cnt.v:49-121`
- decoder arithmetic:
  `tb/jt10_pinned/6d51e0b6/adpcm/jt10_adpcmb.v:35-129`
- interpolation and divider:
  `rtl/genesis_audio/jt10_ym2610/adpcm/jt10_adpcmb_interpol.v:35-127` and
  `rtl/genesis_audio/jt10_ym2610/adpcm/jt10_adpcm_div.v:37-62`
- gain: `rtl/genesis_audio/jt10_ym2610/adpcm/jt10_adpcmb_gain.v:34-41`
- standard accumulator slot/input:
  `tb/jt10_pinned/6d51e0b6/jt10_acc.v:77-135`
- final saturation/publish:
  `rtl/genesis_audio/jt12/jt12_single_acc.v:45-68`
- pinned official fixtures:
  `ver/verilator/tests/adpcmb.jtt:7-28`,
  `adpcmb_delta.jtt:3-26`, and `adpcm_flags.jtt:39-62` at the pinned commit.
  They use `80` START, `01` RESET, `90` repeat START, start/end, Delta-N,
  pan, and level writes consistent with this audit.

## Register and lifecycle contract

ADPCM-B registers are on port 0 in the `10-1c` window:

| Register | Implemented transport |
|---|---|
| `10` Control 1 | bit 7 START, bit 4 REPEAT, bit 0 command RESET |
| `11` Control 2 | bit 7 left pan, bit 6 right pan |
| `12/13` | 16-bit start low/high |
| `14/15` | 16-bit end low/high |
| `19/1a` | 16-bit Delta-N low/high |
| `1b` | 8-bit linear output level |
| `1c` | bit 7 clears the ADPCM-B EOS flag through `flag_ctl[6]` |

The pinned MMR does not store Control-1 external-memory, CPU-memory, or
record-mode bits: bits 6, 5, 3, and 2 are ignored.  Playback is presented by
the fixed external ROM interface.  Control-2 lower bits are likewise ignored.
This is a pinned-source limitation, not an inferred hardware statement.

- START accept: pre-edge `acmd_up_b && acmd_on_b`.
- RESET accept: pre-edge `acmd_up_b && acmd_rst_b`; writing `10=01` clears
  active.  `10=00` is an inert command value used only in Stage P.
- Repeat remains zero for every Phase 4A START (`10=80`).
- Active is loaded when `restart && adv` commits, and cleared immediately by
  `!on || clr` or by the terminal non-repeat branch.
- The natural terminal predicate is pre-edge
  `cen55 && chon && adv && ({addr,nibble_sel} ==
  {aend,8'hff,1'b1})`; repeat zero sets the pending flag and clears active.
- EOS cold reset is zero, accepted START and register `1c[7]` clear it, and
  natural end sets it.  Command RESET leaves it at the source-defined current
  value; all tested RESET cases started before EOS and therefore retained
  zero.  Status addresses `2'b1?` publish EOS at bit 7 and the six ADPCM-A
  flags at bits 5:0.

Start/end registers have 256-byte units.  The byte interval is
`{start,8'h00}` through `{end,8'hff}`, both inclusive.  The cursor begins at
the start byte/high nibble and ends at the end byte/low nibble.  The public
address is 24 bits, with no separate ADPCM-B bank port; data is 8 bits and
`roe_n` is active low.  The source captures high nibble first, then low nibble,
using an edge-captured `din` and no ready/valid handshake.

PC-GATE retains the formal contracts: V1 globally resets interpolator/divider
state; PO-GATE zeros only the stopped ADPCM-B lane; PR gates raw requests with
`chon | restart`; PS clears EOS, Delta-N phase, and stale interpolation/gain/
lane validity on accepted START.  PC-CLEAR and stop-state clearing are absent.

## Event taxonomy

All expressions below describe pre-edge ownership unless explicitly marked
post-edge.  The non-SIMULATION four-state run applies individual unknown
checks to every predicate and payload.

| Event | Exact source-derived observation contract |
|---|---|
| `START_accept_event` | `acmd_up_b && acmd_on_b` |
| `RESET_accept_event` | `acmd_up_b && acmd_rst_b` |
| `raw_b_request_event` | post-edge `adpcmb_roe_n == 0`; generated from pre-edge `adv && cen55 && (chon || restart)` |
| `rom_b_capture_event` | the same qualified transaction edge as raw request; post-edge captured nibble/data/address must be known |
| `logical_b_consume_event` | `cen && cen55 && adv && chon && !restart && !flag` |
| `decoder_b_state_commit_event` | `cen && decoder_adv_pipe[0] && chon && !need_clr` |
| `delta_n_commit_event` | `cen && cen55`; START/RESET priority is modeled exactly |
| `delta_n_carry_event` | Delta commit with bit 16 of `{1'b0,cnt}+{1'b0,delta_n}` set while active |
| `cursor_b_commit_event` | `cen55 && ((restart && adv) || (chon && adv))` |
| `interpolation_b_commit_event` | `cen55 && chon`, after its source pipeline; accepted START has clear priority |
| `gain_b_commit_event` | `cen55`, with accepted-START clear priority |
| `lane_b_commit_event` | `cen55`, with accepted-START clear priority and `chon`/pan gating |
| `standard_accumulator_b_commit_event` | `clk_en && {cur_op,cur_ch} == {2'd0,3'd4}` |
| `final_b_publish_event` | `clk_en && zero`; publishes the preceding saturated accumulator |
| `EOS_set_event` | post-edge EOS 0-to-1 after terminal `set_flag` |
| `EOS_clear_event` | post-edge EOS 1-to-0 after accepted START or `flag_ctl[6]` |

`restart` owns the first request/address reload and old `chon` owns the final
low-nibble request.  Inactive raw request/capture/consume are required to be
zero.  Decoder, interpolation, gain, lane, accumulator, and final publication
have distinct pipeline ownership and are never conflated with ROM reads.

## Bit-exact reference model

`jt10_phase4a_adpcmb_reference.sv` independently models:

- the 16-bit Delta-N accumulator and 17-bit carry expression;
- high/low nibble selection and 24-bit cursor progression;
- signed 16-bit decoder accumulator, 15-bit step, sign application, and
  accumulator/step clamps (`-32768..32767`, `127..24576`);
- interpolator state, unsigned division, direction, widths, and truncation;
- signed `pcm * unsigned level`, selecting product bits `[23:8]` with no
  rounding;
- pan-qualified signed 16-bit lanes;
- ADPCM-B accumulator input arithmetic shift right by one in slot `{0,4}`;
- 16-bit same-sign overflow saturation to `-32768/32767`, and final publish
  on `zero`.  There is no wrap at the final saturation boundary.

Every scenario reports compare and mismatch counts; a single mismatch calls
the common failure path and prevents commit.

## Deterministic ROM provenance

The combinational 24-bit-address/8-bit-data ROM matches the source's capture
contract and adds no latency protocol.  It generates bytes, so no ROM binary
is stored.

| Pattern | Rule modulo 256 | full 2^24-byte SHA-256 | first 32 bytes |
|---|---|---|---|
| primary | `addr[7:0]*73 + addr[15:8]*29 + 41` | `f3adda860c5ca1935fc253275455b21daf6a58a474f43cc7b8a03d79067b4790` | `2972bb044d96df2871ba034c95de2770b9024b94dd266fb8014a93dc256eb700` |
| changed | `addr[7:0]*151 + addr[15:8]*67 + 109` | `1b558bb37ce8bf70dc59b9d6939dd6bfcf747cf07bece0550e491c52a8f067ee` | `6d049b32c960f78e25bc53ea8118af46dd740ba239d067fe952cc35af1881fb6` |

Both patterns ignore the top address byte and repeat every 65,536 bytes.
At primary start `002000`, the first 32 addressed bytes are
`c9 12 5b a4 ed 36 7f c8 11 5a a3 ec 35 7e c7 10 59 a2 eb 34 7d c6 0f 58 a1 ea 33 7c c5 0e 57 a0`.
The TB logs the first 64 raw tuples and first 64 logical tuples explicitly;
those logical tuples are the high then low nibbles of these 32 bytes.

## Playback fixtures and measured results

- Anchor: start/end `0020/0020`, effective `002000-0020ff`, Delta-N `8000`,
  level `ff`, pan `c0`, repeat off.
- Long primary: start/end `0020/004f`, effective `002000-004fff` (12,288
  bytes).  This safely exceeds the 2,048/1,024 logical consumes observed in
  the 4,098-sample primary/changed-Delta windows and crosses multiple pages.
- Shifted range: start/end `0021/0050`, preserving the same byte length.
- Changed Delta-N: `4000`; the actual CEN-driven logical interval moved from
  288 system cycles (2 public samples) to 576 cycles (4 public samples).

### Anchor lifecycle

The 512-nibble anchor consumed 256 high and 256 low nibbles, visited 256
unique bytes, finished at `0020ff` low, set EOS, and stopped active/request/
capture/consume.  Digital zero latency was four public samples at natural end
and three after command RESET at logical consume 100.  Each subsequent 4,096
sample soak was entirely zero.

| Metric | Hash |
|---|---|
| raw request | `e60907109cc90925` |
| logical consume | `d3f50a660ff4da1a` |
| ROM/nibble | `b58835a15fc1d005` |
| Delta-N | `3ef011c519a87325` |
| decoder | `46ce068d48f530a5` |
| interpolation | `977cceaa11432cb1` |
| active-owned gain | `a009ad964647c074` |
| active-owned lane | `a9a4d74927a92055` |
| final stereo | `e142f7da424b1531` |

The historical Phase 4A-X full-window gain/lane hashes
`c44dda0e59862d8a`/`16e284660dfd24e1` remain unchanged provenance.  They
include post-stop commits; the formal Phase 4A-FIX metric deliberately hashes
active-owned commits and therefore uses `a009...`/`a9a4...`.  Both definitions
are preserved without treating one measurement window as the other.

### Long primary, pan, mute, and variation

The long primary measured 4,098 public samples: raw/capture `2049/2049`,
logical `2048` (`1024/1024` high/low), 1,024 unique addresses, Delta commits/
carries `4097/2048`, and arithmetic compares/mismatches `241736/0`.
START was issued/accepted at system cycles `8497498/8497499`; active asserted
at `8497587`.  First raw/capture, logical consume, Delta carry, decoder commit,
and interpolation commit were `8497588/8497588`, `8497875`, `8497731`,
`8497591`, and `8497587`.  The first nonzero lane was cycle `8498595`
(START-accept +1096); the first nonzero final sample was cycle `8498943`
(+1444), measured public index 11.

| Metric | Primary hash |
|---|---|
| raw tuple / raw-cycle | `20184c5d06256fca` / `a5d20b95c8a92ae5` |
| logical address | `5a9fd47c8dd6e081` |
| logical/ROM nibble | `3b7987e523827959` / `a66f655aea051ae5` |
| Delta-N | `39ab6ce8b83b6325` |
| decoder | `1b3d6157f86a526c` |
| interpolation | `9bdebca94cb15689` |
| gain / stereo lane | `7fd7d99a3c89c3c4` / `3afbbbd10454bca5` |
| left / right / stereo | `23036c6c82c6cf5c` / `23036c6c82c6cf5c` / `1207d84363d4ed39` |

Both channels had 4,088 nonzero samples, peak magnitude `16320`, ranges
`-16320..16319`, 794 zero crossings, and DC sum `-643987` (mean about
`-157.15`) per side.

- Left-only: left hash/waveform matched primary; right was all zero, leak 0.
- Right-only: right hash/waveform matched primary; left was all zero, leak 0;
  amplitude and polarity matched left-only.
- Level mute `1b=00`: active/request/consume/decode/interpolation continued;
  512/512 final samples were zero with hash `28c31cf8df2ec325`.
  Restoring `ff` resumed the current stream without decoder/restart reset.
- Delta `4000`: logical count `1024`, interval-576 count `1023`, Delta hash
  `8e64eab63a7ec325`, decoder `911d28d1923781b5`, interpolation
  `11efbbd0682cb37b`, stereo `9d1614887cc055b5`; 393 crossings and DC
  `-1301696` per side.  Arithmetic mismatch remained zero.
- Start shift: first address `002100`, address hash `86a36ee3c49c8881`, ROM
  `765ef0ad23e31525`, decoder `4edb39220e4097d5`, stereo
  `6cb61ca9cc4000d1`; out-of-range accesses zero.
- Changed ROM: request-cycle and logical-address hashes remained
  `a5d20b95c8a92ae5` and `5a9fd47c8dd6e081`, while ROM, decoder,
  interpolation, and stereo changed to `cb2c4febee0d83e5`,
  `3ee08681f99dd156`, `c2e7ba1b116cba3b`, and `101ee148e994c019`.

### Stop, EOS, and restart matrix

- Mid-stream RESET was accepted exactly after 100 logical consumes.  Active,
  raw/capture/consume/decoder progression stopped; digital output became zero
  in three public samples and remained zero for 4,096 samples.
- Natural end consumed exactly 512 nibbles, ended on `0020ff` low, set EOS,
  stopped all progression, became zero in four samples, and remained zero for
  4,096 samples.  With repeat disabled there was no autonomous restart.
- Natural-end, direct-RESET, RESET-to-00, and 65,536-sample-inactive retriggers
  all reproduced every active-owned anchor hash and relative landmark.
- The long soak had active/request/capture/consume/decoder/output/X-Z all
  zero.  Every restart had stale prefix/tag count zero and no old sample
  re-exposure.

## Transport, sample, determinism, and idle result

- Accepted writes: `492` (`474` port 0, `18` port 1).
- Every write used address then data phase and waited for BUSY assertion and
  clear.  BUSY duration range was `190..192` system cycles, hash
  `fb1b6d3978f0e2ad`; timeout/write-while-BUSY were `0/0`.
- Warm-up ready internal pulse: `6`; public pulse 1 is internal pulse 6.
- Warm-up ready transition / first public sample system cycle: `1078/1215`.
- Stage A and explicit Stage B each published 16/16 zero samples with
  all-stereo hash `b9b23f3a46fd0825`; configure-without-START orders each
  kept every event/output zero for 16,384 samples with hash
  `eb05052ea5b62325`.
- Public sample cadence/width: `144/6` system cycles; cadence errors, width
  errors, drops, and duplicate pulses were all zero.
- Relevant X/Z: zero in the non-SIMULATION four-state reference run.
- ADPCM-A active/raw/logical/lane: `0/0/0/0`; FM idle violations: `0`; SSG
  data/control idle violations: `0/0`.
- Three complete non-SIMULATION A-Q runs matched every normalized count, hash,
  landmark, transport, sample, status, and inactive-soak record (3/3).
- The complete SIMULATION A-Q summary matched non-SIMULATION run 1.

## Tool and regression result

- Icarus non-SIMULATION compile/elaboration: PASS; full A-Q: PASS 3/3.
- Icarus SIMULATION compile/elaboration and normalized comparison: PASS.
- Both Icarus compiles emitted the same one aggregate missing-time-unit
  warning, five nonfatal `always_comb` constant-select support notices for the
  test-only ROM, and two inherited 64-entry LFO LUT sensitivity warnings.
- Phase 4A Verilator lint/elaboration: return code 0 with 417 nonfatal
  warnings: BLKSEQ 149, DECLFILENAME 1, EOFNEWLINE 20, GENUNNAMED 10,
  IMPORTSTAR 1, PINCONNECTEMPTY 8, PINMISSING 4, PROCASSINIT 42,
  SYNCASYNCNET 1, TIMESCALEMOD 61, UNUSEDPARAM 7, UNUSEDSIGNAL 84,
  WIDTHEXPAND 18, and WIDTHTRUNC 11.  Duplicate/undefined module, latch,
  combinational-loop, and fatal diagnostics were zero.
- Phase 4A-FIX lifecycle, Phase 3C, Phase 3B, Phase 3A, Phase 2B, and Phase 1C
  overlay regressions: PASS with their committed fixed hashes unchanged.
- Production isolation and protected before/after manifests: PASS.

Selected frozen regression evidence is: Phase 4A-FIX active final
`e142f7da424b1531`, natural/RESET zero latency `4/3`, inactive request/capture
zero, and stale prefix zero; Phase 3C G logical/dummy `16382/1`, aggregate
`c2b40827f24142ce`, final `3f7b4b26b65b7091`, stereo
`32cb891931682fe9`, I/K final `13eca1bccb000782`/`f7f493af1ca508f7`,
arithmetic/ownership/Class-C errors zero; Phase 3B canonical fetch/address/ROM/
decode `0395a9d360fa7ca4`/`ee97dacc6be4aac1`/`8a7e8727bcc15bea`/
`f04661980311a408`, aligned waveform `5b52746e5b1c3d75`; Phase 2B raw/PSG/
final/mute/fixed-DC/period `a05a9500edbbca25`/`3beb13acc8e83f25`/
`54730095b12b6325`/`28c31cf8df2ec325`/`0f24568f5401b325`/
`ce0045fbf79de325`; and Phase 1C steady/attack/mute
`8aadd7a6819038e5`/`c8bafcdd6f79173d`/`28c31cf8df2ec325` with cadence/width
`144/6`.

The runner records the exact Icarus and Verilator warning counts/types in its
`/tmp` log directory.  Verilator is used only for lint/elaboration; all X/Z
claims come from Icarus non-SIMULATION four-state execution.

## Result

Phase 4A standalone ADPCM-B single-shot bring-up passes.  Formal overlay,
pristine pin, compatibility layer, production source/build lists, protected
diagnostics, and Sacred TB remain unchanged.  Repeat behavior remains for
Phase 4B.
