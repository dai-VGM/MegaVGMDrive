# JT10 Phase 1C standard-YM2610 four-channel fixture

Phase 1C remains standalone and test-only. It uses the pristine JT10/ADPCM
sources pinned to JT12 commit
`6d51e0b6f64728c73408079b2f5ffe911bfd88a9`, the Phase 0 compatibility
generators and warm-up wrapper, and the Phase 1A CPU-bus BFM. Nothing in this
fixture is referenced by the production QSF or `files.qip`.

## Channel mapping

`jt12_mmr` captures `part=addr[1]` during an address write. During the
following data write it produces
`up_ch <= {part, selected_register[1:0]}`. The official pinned
`ver/jt12_tb/inputs.cc` writer likewise selects port 1 for upper channels and
adds `(chnum & 3)` to the channel/operator register base.

The two Phase 1C targets therefore use channel offset two:

| Encoding | Port | Internal channel | FNUM high/low | ALG | pan | Operator low nibbles | Key-on/off through port 0 |
|---:|---:|---:|---|---|---|---|---|
| 2 | 0 | 2 | `A6/A2` | `B2` | `B6` | `2, A, 6, E` for S1/S3/S2/S4 | `28=12 / 28=02` |
| 6 | 1 | 6 | `A6/A2` | `B2` | `B6` | `2, A, 6, E` for S1/S3/S2/S4 | `28=16 / 28=06` |

Register `28` is global: pinned `jt12_mmr` asserts
`up_keyon <= selected_register == REG_KON && !part`. Encoding 6 tone
registers consequently use port 1, but its key-on/off transactions use
port 0.

## Standard YM2610 accumulator structure

Pinned `jt10_acc` selects its input with the exact predicate
`case ({cur_op,cur_ch})`:

- `{2'd0,3'd0}` selects ADPCM-A;
- `{2'd0,3'd4}` selects ADPCM-B;
- `default` selects signed FM `opext >>> 1` and gates it with the algorithm
  carrier decision and stereo pan.

Thus encodings 0 and 4 own the ADPCM replacement slots at operator slot zero.
Encodings 1, 2, 5, and 6 never match either replacement predicate and remain
the four audible standard-YM2610 FM channel slots. The Phase 1C TB observes
the time-multiplexed `{cur_op,cur_ch}` selector without keying encodings 0 or
4, and checks that slots 0/4 select their ADPCM expressions while targets
2/6 select the default FM expression.

## Shared tone

All four fixtures use ALG7, feedback 0, stereo left/right, block 4, primary
FNUM 512, changed FNUM 734, multiplier 1, AR 31, DR/SR 0, SL 10, RR 15,
SSG-EG disabled, LFO disabled, DAC disabled, and timers disabled. S1 is the
only keyed audible carrier (`TL=0`); S3/S2/S4 have `TL=127`.

Phase 1A encoding 1 retains its established 52-write sequence exactly.
Phase 1B encoding 5 retains its established 48-write sequence exactly.
Each new Phase 1C channel uses the following 48-write sequence, with `P`
equal to its target port and `C` equal to its encoding:

| Index | Port | Register | Data | Purpose |
|---:|---:|---:|---:|---|
| 1–6 | 0 | `28` | `00,01,02,04,05,06` | key-off all internal encodings |
| 7 | 0 | `22` | `00` | LFO disabled |
| 8 | 0 | `27` | `00` | timers/mode disabled |
| 9 | 0 | `2B` | `00` | DAC disabled |
| 10 | P | `B6` | `C0` | port/channel capture audit |
| 11 | P | `A6` | `22` | block 4/FNUM high |
| 12 | P | `A2` | `00` | primary FNUM 512 low/commit |
| 13 | P | `B2` | `07` | feedback 0, ALG7 |
| 14 | P | `B6` | `C0` | stereo pan, AMS/PMS 0 |
| 15–21 | P | `32,42,52,62,72,82,92` | `01,00,1F,00,00,AF,00` | S1 carrier |
| 22–28 | P | `3A,4A,5A,6A,7A,8A,9A` | `01,7F,1F,00,00,AF,00` | S3 muted |
| 29–35 | P | `36,46,56,66,76,86,96` | `01,7F,1F,00,00,AF,00` | S2 muted |
| 36–42 | P | `3E,4E,5E,6E,7E,8E,9E` | `01,7F,1F,00,00,AF,00` | S4 muted |
| 43 | 0 | `28` | `10 \| C` | target S1 key-on |
| 44 | P | `42` | `7F` | carrier TL mute while keyed |
| 45 | P | `42` | `00` | restore carrier TL |
| 46 | P | `A6` | `22` | changed-frequency high latch |
| 47 | P | `A2` | `DE` | changed FNUM 734 low/commit |
| 48 | 0 | `28` | `C` | target key-off |

After key-on, each fixture captures 4096 attack and 4096 steady samples.
TL mute must reach 16 consecutive zeros within 256 samples, followed by a
512-sample zero window. Frequency changes while key-on remains asserted.
Final key-off must reach 256 consecutive zeros within 8192 samples, followed
by a 512-sample zero window.

## Fixed regression values

The Phase 1C reference run established the following deterministic values.
Encodings 2 and 6 reproduced every hash and landmark in three of three
non-`SIMULATION` runs and in the `SIMULATION` build:

| Encoding | Writes P0/P1 | BUSY hash | Attack hash | Steady hash | Mute/key-off hash | Changed-frequency hash |
|---:|---:|---|---|---|---|---|
| 1 | 51/1 | `c46243ae1f792b2a` | `c8bafcdd6f79173d` | `8aadd7a6819038e5` | `28c31cf8df2ec325` | `00c6bce80cda4ce1` |
| 2 | 48/0 | `99b902b786403dfa` | `c8bafcdd6f79173d` | `8aadd7a6819038e5` | `28c31cf8df2ec325` | `3877bd297ab451fd` |
| 5 | 11/37 | `99b902b786403dfa` | `c8bafcdd6f79173d` | `8aadd7a6819038e5` | `28c31cf8df2ec325` | `3877bd297ab451fd` |
| 6 | 11/37 | `99b902b786403dfa` | `c8bafcdd6f79173d` | `8aadd7a6819038e5` | `28c31cf8df2ec325` | `3877bd297ab451fd` |

All four primary steady windows are sample-for-sample identical at alignment
zero: peak `4084`, min/max `-4084/+4084`, 32 zero crossings, and DC sum
`-208`. The identical 64-bit stereo hash also proves matching polarity,
phase, sample alignment, and frequency for the captured window.
