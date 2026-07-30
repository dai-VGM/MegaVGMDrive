# JT10 Phase 1B port 1 FM fixture provenance

Phase 1B remains a standalone, test-only standard YM2610 test. It reuses the
Phase 0 warm-up wrapper, the Phase 1A CPU-bus BFM, and the pinned JT10 source
set from JT12 commit
`6d51e0b6f64728c73408079b2f5ffe911bfd88a9`.

## Port 1 channel mapping

The official `ver/jt12_tb/inputs.cc` fixture at the pinned commit assigns its
upper three FM channels encodings 4, 5, and 6. Its register writer selects
port 1 for those encodings and adds `(chnum & 3)` to each channel/operator
base register. Encoding 5 therefore uses channel offset one:

- frequency: `A5` high latch and `A1` low/commit
- feedback/algorithm: `B1`
- pan/AMS/PMS: `B5`
- operators: the same offset-one register numbers used by port 0 encoding 1

`jt12_mmr` captures `part=addr[1]` on the address phase and constructs the
internal update channel as `{part,selected_register[1:0]}`. A port 1 `A1`,
`B1`, or offset-one operator write therefore targets internal channel 5.

Key-on register `28` is global and accepted only when `part=0`. The official
fixture consequently emits key-on/off through port 0 even for upper-part
channels. S1-only key-on for encoding 5 is `28=15`; key-off is `28=05`.

The pinned standard `jt10_acc` replaces internal accumulator slots 0 and 4
with ADPCM-A and ADPCM-B. Internal channel 5 is not replaced, so it remains
one of the four audible standard-YM2610 FM channels. It is the upper-part
counterpart of the Phase 1A port 0 encoding-1 channel: both use register
offset one and the same tone values.

## Tone and transaction sequence

Tone parameters are unchanged from Phase 1A: ALG7, feedback 0, block 4,
primary FNUM 512, stereo left+right, multiplier 1, AR 31, DR/SR 0, SL 10,
RR 15, and SSG-EG disabled. Only S1 has `TL=0`; S3/S2/S4 have `TL=127`.

| Index | Port | Register | Data | Purpose |
|---:|---:|---:|---:|---|
| 1–6 | 0 | `28` | `00,01,02,04,05,06` | key-off all encodings |
| 7 | 0 | `22` | `00` | LFO disabled |
| 8 | 0 | `27` | `00` | timers/mode disabled |
| 9 | 0 | `2B` | `00` | DAC disabled |
| 10 | 1 | `B5` | `C0` | port-1 MMR/pan audit |
| 11 | 1 | `A5` | `22` | block 4/FNUM high |
| 12 | 1 | `A1` | `00` | primary FNUM 512 low/commit |
| 13 | 1 | `B1` | `07` | feedback 0, ALG7 |
| 14 | 1 | `B5` | `C0` | stereo pan, AMS/PMS 0 |
| 15–21 | 1 | `31,41,51,61,71,81,91` | `01,00,1F,00,00,AF,00` | S1 carrier |
| 22–28 | 1 | `39,49,59,69,79,89,99` | `01,7F,1F,00,00,AF,00` | S3 muted |
| 29–35 | 1 | `35,45,55,65,75,85,95` | `01,7F,1F,00,00,AF,00` | S2 muted |
| 36–42 | 1 | `3D,4D,5D,6D,7D,8D,9D` | `01,7F,1F,00,00,AF,00` | S4 muted |
| 43 | 0 | `28` | `15` | encoding-5 S1 key-on |
| 44 | 1 | `41` | `7F` | carrier TL mute; key-on retained |
| 45 | 1 | `41` | `00` | restore carrier TL |
| 46 | 1 | `A5` | `22` | changed-frequency high latch |
| 47 | 1 | `A1` | `DE` | changed FNUM 734 low/commit |
| 48 | 0 | `28` | `05` | encoding-5 key-off |

After the TL write, the test observes a bounded 17-sample accumulator
transition until 16 consecutive zero samples have appeared while key-on
remains asserted. The following 512 samples form the mute hash window.

The primary port 1 sample stream has the same measured hash and aggregate
statistics as the Phase 1A port 0 stream after identical attack alignment.
The frequency-control hash differs because Phase 1B changes FNUM while the
same envelope remains keyed, whereas Phase 1A re-keyed its frequency-control
fixture.
