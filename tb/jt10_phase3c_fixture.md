# JT10 Phase 3C simultaneous ADPCM-A fixture provenance

## Scope, baseline, and result

This is a standalone, production-disconnected test of simultaneous standard
JT10 ADPCM-A voices.  The baseline is branch `ym2610-family-bringup`, commit
`9c71fa03d9c19c41f226458b046142f153e6ad54`.  The pinned JT10/ADPCM source is
Jotego JT12 commit `6d51e0b6f64728c73408079b2f5ffe911bfd88a9`.

Phase 3C passes scenarios A-L in three independent non-`SIMULATION` runs and
in the `SIMULATION` comparison.  No production RTL, pinned JT10/JT49 source,
compatibility code, warm-up wrapper, project build list, or Phase 3C-R
diagnostic is changed.  In particular, the clear-boundary request found by
Phase 3C-R is retained and classified as a Class C physical transaction.  It
is not a consumed ADPCM nibble.

The fixture reuses `jt10_phase3a_adpcma_rom.sv` unchanged.  The primary ROM
byte is `((address[7:0] * 73) + (address[11:8] * 29) + 41) mod 256`; its
one-period SHA-256 is
`2972dcd165c94f9ddfd9371d8999beab00e7b08b0b10ac0644454fa6071ad0da`.
ADPCM-A start/end register units remain 256 bytes.

## Event taxonomy

The monitor samples the following source-level predicates on `clk_en_666`:

| Event | Predicate | Meaning |
| --- | --- | --- |
| raw ROM request | `clk_en_666 && !adpcma_roe_n && decon` | Respond to the ROM bus and audit raw traffic, owner, capture, and clear-boundary requests. |
| logical nibble consume | `clk_en_666 && !adpcma_roe_n && decon && !clr_dec` | Advance the logical address/nibble sequence and its unique, duplicate, range, cadence, and natural-end checks. |
| decoder state commit | `clk_en_666 && u_decoder.chon4` | Commit the decoder accumulator/step state. |
| physical cursor commit | `clk_en_666 && sumup6 && !skip6 && !(clr6 && on6)` | Audit the pinned counter pipeline separately from logical progression. |
| physical contribution write | `clk_en_666 && match` | Observe every shared gain/contribution write. |
| logical contribution | physical write with a propagated, non-clear accepted-nibble tag | Attribute gain and L/R contribution to a logical consume. |

The accepted-nibble tag is propagated through the pinned pipeline.  Decoder
state is checked at tag stage 2 and contribution at tag stage 35.  Owner,
clear flag, address, nibble, data, and source cycle travel with the tag, so a
physical write cannot be silently reclassified as a logical contribution.
ADPCM-A aggregate commit, standard `jt10_acc` insertion, final `snd_l/r`
publication, and public sample-valid are counted separately.

### Class C invariant

At the six-voice start boundary, voice 5 produces one `clr=1` raw request.
The ROM model must answer it and the nibble is visible at decoder input, but
the decoder gate suppresses acceptance.  The invariant requires the request
to produce no decoder state commit tag, logical cursor tag, logical
contribution tag, or non-zero audible effect.  All scenarios report zero
Class C violations, tag-owner mismatches, and tag-age errors.

For the canonical six-voice run the measured separation is:

- raw/capture/decoder input: 16,383;
- clear-boundary dummy raw requests: 1 (voice 5);
- logical consume/decoder state/logical cursor: 16,382;
- physical cursor commits: 16,376;
- physical contribution writes: 16,385;
- logical contributions: 16,377;
- clear request state commits, logical cursor commits, and logical
  contributions: all zero;
- dummy non-zero audible effects: zero.

Thus raw count being one greater than logical count is expected Class C
behavior.  Repetition of the raw `(owner,address,nibble)` tuple is never used
as a logical-duplicate failure.  Logical sequences have zero repeats, gaps,
range errors, missed/duplicate scheduler slots, starvation, or ownership
errors.

## Scheduler, commands, and ownership

The physical request owner is the stable pre-edge one-hot `cur_ch`; logical
ownership is independently checked through capture, decoder state, cursor,
gain, and contribution.  The source rotates `cur_ch` each 666-kHz enable and
`en_ch` once per six slots.  The fixture validates these command mappings:

- `03`, `07`, `0F`, `3F` key on masks `000011`, `000111`, `001111`,
  `111111`;
- `81`, `82`, `84`, `88`, `90`, `A0` independently clear voices 0-5;
- `BF` clears all voices;
- bit 6 has no effect, and command updates are neither missed nor duplicated.

Raw owner unknown, capture owner mismatch, logical owner unknown, decoder
owner mismatch, cursor cross-update, ROM contamination, contribution owner
mismatch, and cross-owner contamination are zero in every scenario.

## Hash contract and packing

All hashes are 64-bit FNV-1a, offset `cbf29ce484222325`, prime
`00000100000001b3`.  Integers wider than one byte are fed least-significant
byte first.  Signed samples are hashed as their two's-complement bit pattern.

- per-voice raw request: relative system cycle u16, logical address u24,
  `{nibble,clr}` byte, selected nibble byte;
- aggregate raw request: owner byte, logical address u24, `{nibble,clr}`;
- per-voice dummy request: logical address u24, nibble-select byte, selected
  nibble byte; aggregate dummy additionally begins each tuple with owner;
- per-voice logical consume: relative system cycle u16, owner byte;
- logical address/cursor: logical address u24, nibble-select byte;
- logical ROM: ROM byte, selected nibble byte;
- aggregate logical consume: owner byte, logical address u24, nibble-select;
- decoder state: selected nibble byte, post-commit signed `x5` u16, `step5`
  byte;
- physical cursor: owner byte, source cursor address zero-extended to u24;
- gain: signed post-gain PCM u16; per-voice L/R contribution hashes use the
  corresponding signed u16 lane;
- aggregate logical contribution: owner byte, left u16, right u16;
- aggregate ADPCM-A and final hashes: one signed u16 lane value per public
  sample; stereo packs left u16 followed by right u16;
- active mask: one byte per `clk_en_666` observation;
- stop/zero: left u16 followed by right u16 for 512 public samples.

The 512-sample all-zero hash is `28c31cf8df2ec325`.

## Arithmetic reference

`jt10_phase3c_arithmetic_reference.sv` is test-only.  It reproduces the
pinned fixed-width path: signed 16-bit per-voice gain, signed 18-bit six-voice
sum, the signed 23-bit interpolation expression and `[22:7]` extraction,
18-bit interpolation state, the source-defined 16-bit limiter, multiplication
of ADPCM-A by six at the standard accumulator insertion point, the standard
16-bit saturating accumulator, and pre-edge publication at `zero`.

The safe setting remains global TL `3F`; level/pan is `C0` stereo, `80` left,
and `40` right.  Scenario G has aggregate peak 672 and final peak 4,032 with
zero aggregate saturation, aggregate wrap, decoder wrap, final saturation,
or final wrap.  Scenario I uses primary level `F5`: aggregate peak 4,152 and
final peak 24,912.  Its measured, source-defined lossy operations are 16,344
gain truncations and 2,703 interpolation truncations; saturation and wrap
counts remain zero.  No source behavior is mislabeled as clipping.

Arithmetic compare/mismatch counts are:

| Scenario | Compare | Mismatch |
| --- | ---: | ---: |
| A | 779352 | 0 |
| B | 779352 | 0 |
| C | 778848 | 0 |
| D | 606480 | 0 |
| E | 778918 | 0 |
| F | 778988 | 0 |
| G | 1467018 | 0 |
| H | 779058 | 0 |
| I | 1467018 | 0 |
| J | 779058 | 0 |
| K | 1639386 | 0 |
| L | 1467018 | 0 |

## Scenario results

Every scenario has BUSY duration 190-192 system cycles, timeout zero,
write-while-BUSY zero, ready cycle 662, first public sample cycle 799, cadence
144, strobe width 6, X/Z zero, sample drop zero, and duplicate sample pulse
zero.

| Scenario | Accepted (p0/p1) | BUSY hash | Result |
| --- | ---: | --- | --- |
| A | 65 (16/49) | `45034dda8eb6ea95` | voices 0/1 simultaneous stereo; independent logical sequences and bit-exact L/R |
| B | 60 (16/44) | `3dab2d6af6efce6d` | hard pan isolated; leak zero |
| C | 84 (16/68) | `6405b5a4de2a1a8b` | voice 0 key-off; voice 1 matches its control run |
| D | 62 (16/46) | `3a0150a6f338ae13` | natural ends at 512/1024 logical nibbles; 512 zero samples |
| E | 50 (16/34) | `b04bd3d78a7d9fdd` | three voices, mask `000111`; voices 3-5 idle |
| F | 60 (16/44) | `3dab2d6af6efce6d` | four voices with mixed pan; voices 4/5 idle |
| G | 50 (16/34) | `b04bd3d78a7d9fdd` | six safe-level voices; Class C dummy isolated |
| H | 80 (16/64) | `012f01eb13af248d` | six-voice L/R/stereo routing; leak zero |
| I | 50 (16/34) | `b04bd3d78a7d9fdd` | primary-level fixed-width stress; bit-exact |
| J | 53 (16/37) | `7f7b72b0358bf63a` | `81`,`84`,`90` selective stops, survivors continue; `BF` then zero |
| K | 49 (16/33) | `d78b20f4fa52412a` | six independent natural ends; final 512 samples zero |
| L | 52 (16/36) | `0b313b669ba0d515` | scheduler-aligned deterministic retrigger matches G |

Scenario K consumes exactly 512, 1,024, 1,536, 2,048, 2,560, and 3,072
logical nibbles for voices 0-5.  Each voice has equal high/low counts, ends on
the low nibble of pages `000`, `002`, `005`, `009`, `00E`, and `014`, and
clears in order with masks `3E`, `3C`, `38`, `30`, `20`, `00`.  The single
voice-5 dummy raw request is excluded from these counts.

## Canonical six-voice hashes

Scenario G and scheduler-aligned retrigger L have the same event and audio
identity:

| Trace | Hash |
| --- | --- |
| raw request | `5603712da3027fc6` |
| dummy request | `d0a14704cb26ceb7` |
| logical consume | `8953c075227e3549` |
| physical cursor | `7453a4cda6ac9cd3` |
| logical contribution | `1a879c69aa265497` |
| raw owner | `32a8709196327301` |
| logical owner | `3aae2a4bf55d4ec4` |
| active mask | `81a882fecf85713d` |
| aggregate ADPCM-A L/R | `c2b40827f24142ce` |
| final `snd_l/r` | `3f7b4b26b65b7091` |
| stereo interleaved | `32cb891931682fe9` |

Per-voice G/L hashes are:

| Voice | Raw | Dummy | Logical | Address/cursor | ROM+nibble | Decoder state | Gain/contribution L/R |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 0 | `4ca981247a2108d1` | offset | `f0d2202aaa1bd581` | `50c99b682273c3e2` | `a66e0cb7e198430d` | `187d97811f4dd8f8` | `7fba68ce02604b4d` |
| 1 | `5781e882f1ea3263` | offset | `c3ac91cff4b66d63` | `cc3d0fb2d791a49a` | `70bc9aa6f8cd02ab` | `67d65a8ffbf382ee` | `9fd267fa85217d3f` |
| 2 | `ec89c907b446fd60` | offset | `6b82957fa137e5e2` | `6f293943fb1654a2` | `6214ee91ad76fe5f` | `23fb8deb0f5c8659` | `b85caa16baa79504` |
| 3 | `47671871a38c1f6a` | offset | `7c8922b96aab5252` | `ff22154f6c68887f` | `a92612b133f4dd37` | `a66c734a378ca3ef` | `7a5fea4fe95a3887` |
| 4 | `f7243a6c598b9206` | offset | `2c7bbfcb659552fd` | `300ca546f9673914` | `6c637ba495fecd7b` | `824ff913d9e93f79` | `3876f8b8cd822482` |
| 5 | `5e8f1352f4d41772` | `c4d6eaaf761f2b2f` | `c9bcd22e03210a8c` | `40d2ea56bb7784fa` | `690462bf905a7d3c` | `2f62db359ef62af0` | `fa937bb9272b527b` |

“offset” is the untouched FNV offset because that voice has no dummy request.
Voice logical counts are 2,730, 2,730, 2,730, 2,731, 2,731, 2,730; the
maximum window-edge difference is one.  Raw counts differ only for voice 5,
which is 2,731 because of its one Class C request.

Scenario I retains the G raw/dummy/logical/cursor/owner hashes while changing
the logical contribution hash to `ca26dc1ca98880d7`, aggregate L/R to
`5bd10156c4797b5b`, final L/R to `13eca1bccb000782`, and stereo to
`f437d5e4978bc389`.

## Tool, isolation, and regression contract

The runner compiles/elaborates four-state non-`SIMULATION` Icarus, executes
A-L three times and compares normalized event/count/hash/landmark output,
then compiles `SIMULATION` and compares every scenario against the first
four-state run.  Verilator is lint/elaboration only; Icarus remains the X/Z
authority.  Non-`SIMULATION` and `SIMULATION` Icarus each report three
pre-existing warnings (one mixed-timescale group and two `jt12_pm` sensitivity
warnings).  Verilator exits zero with 592 warnings: `BLKSEQ` 218,
`DECLFILENAME` 2, `EOFNEWLINE` 20, `GENUNNAMED` 10, `PINCONNECTEMPTY` 8,
`PINMISSING` 4, `PROCASSINIT` 120, `SYNCASYNCNET` 1, `TIMESCALEMOD` 61,
`UNUSEDPARAM` 5, `UNUSEDSIGNAL` 102, `WIDTHEXPAND` 24, and `WIDTHTRUNC` 17.

All scenarios keep ADPCM-B start/active/fetch/lane zero, FM key-off and lane
zero, SSG A/B/C volume and lanes zero, PSG sum zero, and noise/envelope
enable zero.  The Phase 3B, Phase 3A, Phase 2B SSG, and Phase 1C FM complete
regressions are chained by the runner and retain their canonical hashes.

The runner also proves pinned JT10 blobs, the production JT49 tree,
compatibility fixtures and generator reproducibility, the warm-up wrapper,
`files.qip`, and `VGM_MD_MiSTer.qsf` unchanged.  Production build lists have
zero references to the standalone JT10 tree, Phase 1/2/3 testbenches,
Phase 3C arithmetic helper, or Phase 3C-R diagnostics.  Duplicate and
undefined modules are zero, `git diff --check` passes, and no VCD/FST/WAV or
other repository simulation artifact is produced.
