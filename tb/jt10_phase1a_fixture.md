# JT10 Phase 1A FM fixture provenance

This fixture is limited to the standalone, test-only standard YM2610 `jt10`
instance. It does not enter a production file list.

## Primary sources

- JT12 upstream commit:
  `6d51e0b6f64728c73408079b2f5ffe911bfd88a9`
- Official fixture:
  `ver/jt12_tb/inputs.cc` at that commit
- Bus and register decode:
  `hdl/jt12_top.v`, `hdl/jt12_mmr.v`, `hdl/jt12_reg.v`, and
  `hdl/jt12_dout.v` at that commit
- Standard YM2610 channel replacement:
  pinned `jt10_acc.v`, which inserts ADPCM-A at `{cur_op,cur_ch}=0,0` and
  ADPCM-B at `{cur_op,cur_ch}=0,4`

The repository's 15 pinned JT10/ADPCM files are blob-checked against the
same upstream commit before each run. Local JT12 fork differences and the
Phase 0 deterministic counter reset are applied only in a temporary test
tree by the existing compatibility generators.

## Bus contract

`jt12_top` defines a write as `!cs_n && !wr_n`; both controls are therefore
active low. The four address values are:

| `addr[1:0]` | Function |
|---|---|
| `00` | port 0 address |
| `01` | port 0 data |
| `10` | port 1 address |
| `11` | port 1 data |

`din` and `dout` are eight bits. A port address write captures the selected
register and `addr[1]` part. A data write captures data and asserts status
bit 7 (BUSY). `jt12_mmr` keeps BUSY for 32 `clk_en` synth cycles. The BFM
reads status with `addr=00`, confirms BUSY assertion, and polls until it
clears before issuing another address phase. The warm-up wrapper gates only
the public audio outputs; it does not gate the CPU bus or the JT10 core.
An address write does not assert BUSY; the BFM holds it for one full system
clock and deasserts write before the data phase. A data write sets BUSY on
its first active system-clock edge. MMR capture itself runs at system-clock
rate, while BUSY clearing advances only with synth `clk_en`, which is derived
from chip CEN. Reset takes precedence over writes, so writes during reset are
not accepted. Writes during the private warm-up interval are possible, but
this fixture waits for public ready so every audio landmark is unambiguous.

## Audible channel choice

The tone uses logical FM channel 1, register/key-on encoding 1, on port 0.
It is one of the four standard-YM2610 FM channels that reach the accumulator.
Internal channel encodings 0 and 4 are deliberately avoided because
`jt10_acc` replaces those accumulator time slots with ADPCM-A and ADPCM-B.

The other transport is exercised with a harmless port 1 `B5=C0` write for
channel encoding 5 while that channel remains key-off. The test checks the
MMR part, selected register, data, update channel, update class, and streamed
pan state.

## Ordered register transactions

The values follow the official fixture's defaults and write order. The tone
is algorithm 7 with feedback 0. Only S1 is audible (`TL=0`) and keyed on;
S3/S2/S4 use `TL=127`. All operators use multiplier 1, attack 31, decay 0,
sustain rate 0, sustain level 10, release 15, and SSG-EG disabled. Pan is
left+right, AMS/PMS are zero. Primary FNUM is 512 at block 4.

| Index | Port | Register | Data | Purpose |
|---:|---:|---:|---:|---|
| 1–6 | 0 | `28` | `00,01,02,04,05,06` | key-off all six internal encodings |
| 7 | 0 | `22` | `00` | LFO disabled |
| 8 | 0 | `27` | `00` | timers/mode disabled |
| 9 | 0 | `2B` | `00` | DAC disabled |
| 10 | 1 | `B5` | `C0` | harmless channel-5 pan/MMR transport audit |
| 11 | 0 | `A5` | `22` | channel 1 block 4/FNUM high |
| 12 | 0 | `A1` | `00` | channel 1 FNUM low; FNUM 512 |
| 13 | 0 | `B1` | `07` | feedback 0, algorithm 7 |
| 14 | 0 | `B5` | `C0` | left+right, AMS 0, PMS 0 |
| 15–21 | 0 | `31,41,51,61,71,81,91` | `01,00,1F,00,00,AF,00` | S1 |
| 22–28 | 0 | `39,49,59,69,79,89,99` | `01,7F,1F,00,00,AF,00` | S3 muted |
| 29–35 | 0 | `35,45,55,65,75,85,95` | `01,7F,1F,00,00,AF,00` | S2 muted |
| 36–42 | 0 | `3D,4D,5D,6D,7D,8D,9D` | `01,7F,1F,00,00,AF,00` | S4 muted |
| 43 | 0 | `28` | `11` | key-on channel 1 S1 only |
| 44 | 0 | `28` | `01` | primary tone key-off |
| 45 | 0 | `41` | `7F` | maximum-TL mute control |
| 46 | 0 | `28` | `11` | mute-control key-on |
| 47 | 0 | `28` | `01` | mute-control key-off |
| 48 | 0 | `41` | `00` | restore S1 TL |
| 49 | 0 | `A5` | `22` | changed-frequency high latch |
| 50 | 0 | `A1` | `DE` | changed FNUM 734 low/commit |
| 51 | 0 | `28` | `11` | changed-frequency key-on |
| 52 | 0 | `28` | `01` | changed-frequency key-off |

The test first hashes 16 initial-idle public samples, then hashes another 16
pre-key-on samples after configuration. The primary and changed-frequency
paths each capture 4096 attack samples
followed by 4096 steady samples. Hashing uses 64-bit FNV-1a over little-endian
left then right 16-bit public samples. Only rising edges of the Phase 0
sample-qualified public pulse are hashed.
