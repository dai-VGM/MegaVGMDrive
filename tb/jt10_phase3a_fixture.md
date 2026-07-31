# JT10 Phase 3A ADPCM-A voice 0 fixture provenance

## Scope

This fixture exercises only the standalone, production-disconnected standard
JT10 environment. It brings up ADPCM-A voice 0 from a test-only combinational
ROM and does not add ADPCM-A voices 1-5, ADPCM-B, YM2610B, VGM, data-block,
DDR, production-mixer, QSF, or Quartus integration.

The pinned JT10/ADPCM source baseline is Jotego JT12 commit
`6d51e0b6f64728c73408079b2f5ffe911bfd88a9`. The 15 pristine files and their
Git blobs/SHA-256 values remain recorded in
`tb/jt10_compat/pristine_blobs.tsv`.

The official fixture used for the register cross-check is
`ver/verilator/tests/adpcma.jtt` at that exact commit:

- Git blob: `d6ab6d54e273a1612b9577b960e057513eb1dcc2`
- raw SHA-256:
  `9290f17f1386e20e96f86a67254542296bf81fe62c0e82321c45e01c0e062cec`
- size: 450 bytes
- upstream path:
  `https://github.com/jotego/jt12/blob/6d51e0b6f64728c73408079b2f5ffe911bfd88a9/ver/verilator/tests/adpcma.jtt`

It programs voice 0 start `00/00`, end `0F/00`, total level `3F`,
pan/individual level `F5`, key-on `01`, and key-off `81`. The Phase 3A
fixture uses the same primary register values.

## Pinned register contract

`jt12_mmr.v` accepts ADPCM-A registers only on CPU port 1 (`part=1`) while
`selected_register[7:6]==0`:

| Meaning | Register | Voice 0 value |
| --- | --- | --- |
| key control | `00` | `BF` all-off, `01` voice 0 on, `81` voice 0 off |
| global total level | `01[5:0]` | `3F` audible, `00` mute with `F5` |
| pan and individual level | `08` | `F5` stereo, `B5` left, `75` right |
| start low | `10` | `00` primary, `01` shifted control |
| start high | `18` | `00` |
| end low | `20` | `0F` primary, `00` short natural-end control |
| end high | `28` | `00` |

Control register bit 7 selects polarity: bit 7 clear applies key-on to the
voice mask in bits 5:0; bit 7 set applies key-off. Thus `BF` keys off all six
voices, `01` keys on only voice 0, and `81` keys off only voice 0.

`jt10_adpcm_gain.v` takes pan from `lracl[7:6]`: bit 7 is left and bit 6 is
right. `lracl[4:0]` is individual level. Both individual and global level use
larger register values for less attenuation. The global `00` plus individual
`15` in `F5` crosses the pinned gain pipeline's zero-gain threshold and is the
fixture's level-mute control.

## Address, fetch, and decode contract

`jt10_adpcm_cnt.v` stores the low 12 start/end bits and the start register's
upper nibble as the four-bit bank. On key-on it forms the internal nibble
address as `{start[11:0],9'b0}`. Public byte address is internal
`addr1[20:1]`; `addr1[0]` selects the nibble.

Consequently:

- each 16-bit start/end register unit is 256 bytes;
- logical byte address is `{bank[3:0],adpcma_addr[19:0]}`;
- the effective start byte is `start_register << 8`;
- the effective inclusive end byte is
  `((end_register + 1) << 8) - 1`;
- primary `0000..000F` covers bytes `000000..000FFF`;
- shifted `0001..000F` covers bytes `000100..000FFF`;
- short natural-end `0000..0000` covers bytes `000000..0000FF`.

The public ADPCM-A address is 20 bits, bank is four bits, and ROM data is
eight bits. `roe_n` is active-low. The fixture counts a valid serialized
decode/fetch event only when all exact pinned conditions are true:

`clk_en_666 && !adpcma_roe_n && decon`

Inactive address/bank values are not checked. On a valid event, address,
bank, ROM data, captured nibble, decoder PCM, attenuation data, accumulator
input, and public audio must be known.

`jt10_adpcm_drvA.v` captures `datain[7:4]` when `nibble_sel=0`, then
`datain[3:0]` when `nibble_sel=1`. Public byte address therefore repeats
twice: high nibble first, low nibble second, then the address increments by
one byte. The shared decoder runs at `clk_en_666`; its six-stage pipeline
serializes the six voices. Voice isolation is checked with `en_ch`, `cur_ch`,
`match`, the command shift registers, and the counter's active stages.

The decoded sample passes through the individual/global attenuation pipeline,
then through the per-side six-voice accumulator/interpolator. Pan gates the
left and right accumulator inputs. `jt10_acc.v` inserts ADPCM-A at
`{cur_op,cur_ch}={0,0}` and computes each standard accumulator input as
`(adpcmA <<< 2) + (adpcmA <<< 1)`, a factor of six. The standard JT10
accumulator is retained unchanged. With SSG volume zero, final `snd_l/r`
equals this standard accumulator output.

## Test-only ROM

`tb/jt10_phase3a_adpcma_rom.sv` is a zero-wait-state combinational model. It
adds no ready/valid signal and does not alter the JT10 interface. Both
patterns use logical address bits 11:0 and repeat every 4096 bytes.

Primary byte rule:

`((address[7:0] * 73) + (address[11:8] * 29) + 41) mod 256`

- byte count/repeat period: 4096
- SHA-256 over one period:
  `2972dcd165c94f9ddfd9371d8999beab00e7b08b0b10ac0644454fa6071ad0da`
- first 32 bytes:
  `29 72 BB 04 4D 96 DF 28 71 BA 03 4C 95 DE 27 70`
  `B9 02 4B 94 DD 26 6F B8 01 4A 93 DC 25 6E B7 00`

Changed-pattern rule:

`((address[7:0] * 151) + (address[11:8] * 67) + 109) mod 256`

- byte count/repeat period: 4096
- SHA-256 over one period:
  `de9b607745cfdf9c4d2a2983b3d244ce502ac5d50228228510b8be1dbf6ca5fd`
- first 32 bytes:
  `6D 04 9B 32 C9 60 F7 8E 25 BC 53 EA 81 18 AF 46`
  `DD 74 0B A2 39 D0 67 FE 95 2C C3 5A F1 88 1F B6`

Each 256-byte block contains all 256 possible byte values. The block offset
term makes a legal 256-byte start shift change the sequence. The changed
pattern leaves fetch timing/address unchanged but changes returned data,
decode, and audio.

## Register sequence

Every write uses the existing BUSY-polling BFM and performs address and data
phases on the legal port.

1. Port 0 `28=00,01,02,04,05,06`: all FM channels key-off.
2. Port 0 `22=00`, `27=00`, `2B=00`: LFO, timers, and DAC disabled.
3. Port 1 `00=BF`: all six ADPCM-A voices key-off.
4. Port 0 `10=01`, `10=00`: ADPCM-B reset then stopped.
5. Port 0 `08=00`, `09=00`, `0A=00`, `06=00`, `07=3F`: SSG volumes
   zero and tone/noise disabled.
6. Port 1 `10=00`, `18=00`, `20=0F`, `28=00`, `01=3F`, `08=F5`.
7. Port 1 `09=00`, `0A=00`, `0B=00`, `0C=00`, `0D=00`: voices 1-5
   pan/level known and off.
8. Port 1 `00=01`: primary playback; `00=81`: stop.
9. Port 1 `08=B5`, `00=01`: left-only; `00=81`: stop.
10. Port 1 `08=75`, `00=01`: right-only; `00=81`: stop.
11. Port 1 `08=F5`, `01=00`, `00=01`: global-level mute;
    `00=81`, then `01=3F`.
12. Port 1 `10=01`, `00=01`: shifted-start control;
    `00=81`, then `10=00`.
13. Pattern selector changes test-only ROM data; port 1 `00=01` plays the
    changed pattern, then `00=81`.
14. Port 1 `00=01` starts the mid-stream key-off control; `00=81` stops it.
15. Port 1 `20=00`; port 0 `1C=01` clears voice 0's end flag; port 1
    `00=01` runs to natural end; port 1 `20=0F` restores the primary end.
16. After returning to the primary serialized-channel phase, port 1 `00=01`
    performs the deterministic retrigger; `00=81`, then `00=BF` stops all
    voices.

## Measurement stages

The test records reset/warm-up and explicit-silence windows; a 4096-public-
sample primary window; left/right 4096-sample controls; a 512-sample
level-mute; a 4096-sample shifted-start control; a 4096-sample changed-ROM
control; mid-stream key-off followed by 512 zero samples; short natural end
followed by 512 zero samples; and an aligned 4096-sample retrigger.

Fetch timing, address/nibble progression, ROM bytes, captured nibble/decoded
PCM, attack audio, full audio, L/R audio, peak/range/zero crossings/DC,
sample cadence/width, BUSY transport, X/Z, clipping, drops, duplicates,
voice isolation, ADPCM-B idle, FM idle, and SSG idle are hashed or counted.
