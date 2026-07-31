# JT10 Phase 3B ADPCM-A six-voice fixture provenance

## Scope

This fixture remains entirely inside the production-disconnected standalone
standard JT10 environment. It reuses the Phase 3A ROM and CPU-bus fixture and
tests ADPCM-A voices 1-5 one at a time. No fixture ever keys on two ADPCM-A
voices simultaneously.

It does not add multi-voice summing, ADPCM-B, YM2610B, VGM parser, data-block,
DDR, production mixer, QSF, files.qip, Quartus, tag, release, or hardware
integration.

The pinned source baseline remains Jotego JT12 commit
`6d51e0b6f64728c73408079b2f5ffe911bfd88a9`. The 15 pristine JT10/ADPCM
files and their Git blob/SHA-256 values remain in
`tb/jt10_compat/pristine_blobs.tsv`.

The official register fixture cross-check remains:

- path: `ver/verilator/tests/adpcma.jtt`
- commit:
  `6d51e0b6f64728c73408079b2f5ffe911bfd88a9`
- Git blob: `d6ab6d54e273a1612b9577b960e057513eb1dcc2`
- raw SHA-256:
  `9290f17f1386e20e96f86a67254542296bf81fe62c0e82321c45e01c0e062cec`
- upstream:
  `https://github.com/jotego/jt12/blob/6d51e0b6f64728c73408079b2f5ffe911bfd88a9/ver/verilator/tests/adpcma.jtt`

## Exact six-voice register mapping

`jt12_mmr.v` accepts ADPCM-A writes only on CPU port 1 while
`selected_register[7:6]==0`. The voice number is the low three register
bits for the six implemented voices:

| Voice | Pan/level | Start low/high | End low/high | Key bit |
| ---: | ---: | ---: | ---: | ---: |
| 0 | `08` | `10/18` | `20/28` | `0` |
| 1 | `09` | `11/19` | `21/29` | `1` |
| 2 | `0A` | `12/1A` | `22/2A` | `2` |
| 3 | `0B` | `13/1B` | `23/2B` | `3` |
| 4 | `0C` | `14/1C` | `24/2C` | `4` |
| 5 | `0D` | `15/1D` | `25/2D` | `5` |

The key-control register is port 1 register `00`.
`jt10_adpcm_drvA.v` derives:

`aon_sr = ~{6{command[7]}} & command[5:0]`

`aoff_sr = {6{command[7]}} & command[5:0]`

Thus bit 7 clear is key-on, bit 7 set is key-off, and bits 5:0 are
active-high voice masks. Individual commands are:

| Voice | Key-on | Key-off |
| ---: | ---: | ---: |
| 0 | `01` | `81` |
| 1 | `02` | `82` |
| 2 | `04` | `84` |
| 3 | `08` | `88` |
| 4 | `10` | `90` |
| 5 | `20` | `A0` |

`BF` means key-off mode plus all six voice bits set. Reserved bit 6 is
clear and ignored by the six-bit command shift registers.

## Scheduler mapping and alignment

`jt10_adpcm_drvA.v` starts `cur_ch` and `en_ch` as one-hot bit 0.
`cur_ch` rotates every 666-kHz enable. After `cur_ch[5]`, `en_ch` rotates
to the next serialized decoder channel. The six voices therefore use
one-hot scheduler slots 0-5, with slot mask `1<<voice`.

The full ADPCM-A serialized scheduler repeats every 432 system cycles.
The test reconstructs the six-channel active mask from `cur_ch` and the
counter pipeline's `on1..on6` stages. A valid fetch is attributed to the
target only while the reconstructed active mask contains no non-target bit.
This avoids incorrectly assigning an already-pipelined fetch from the
post-edge value of `en_ch`.

Phase 3A voice 0's canonical key-on issue phase is
`13190 mod 432 = 230`. For Phase 3B, the voice target slot moves by 60
system cycles. The per-voice issue phase is therefore selected as:

`(230 - 60*(voice-1)) mod 432`

for voices 1-5. The resulting phases are:

| Voice | Issue phase | Key-on accept to target slot |
| ---: | ---: | ---: |
| 1 | 230 | 221 cycles |
| 2 | 170 | 221 cycles |
| 3 | 110 | 221 cycles |
| 4 | 50 | 221 cycles |
| 5 | 422 | 221 cycles |

This alignment prevents a clear/start boundary fetch from being counted as
the first canonical nibble and makes each voice's primary, pan, natural-end,
and retrigger windows internally repeatable. Public audio is sampled every
144 cycles, so the different legal issue phases can leave fixed whole-sample
alignment shifts between voices. The fixture records both the command-aligned
4096-sample hash and a 2048-sample hash beginning at the first non-zero
sample.

## Address and nibble contract

The Phase 3A address contract is reused unchanged:

- start/end register unit: 256 bytes;
- internal nibble address: `{start[11:0],9'b0}`;
- public byte address: `addr1[20:1]`;
- nibble select: `addr1[0]`;
- bank: `start[15:12]`;
- inclusive byte range:
  `start<<8` through `((end+1)<<8)-1`;
- valid fetch:
  `clk_en_666 && !adpcma_roe_n && decon`;
- high nibble first, low nibble second;
- the byte address increments only after the low nibble.

Address, bank, ROM byte, captured nibble, decode value, attenuation data,
accumulator lane, and public audio are required known at their valid
observation points. Inactive address and bank remain don't-care.

## ROM

The Phase 3A zero-latency combinational ROM is reused without modification.
There is no ready/valid handshake.

Primary pattern:

`((address[7:0]*73) + (address[11:8]*29) + 41) mod 256`

- period: 4096 bytes
- SHA-256:
  `2972dcd165c94f9ddfd9371d8999beab00e7b08b0b10ac0644454fa6071ad0da`

The Phase 3A changed-ROM control remains in the voice 0 regression. It is
not repeated for voices 1-5.

## Mapping sentinel

Before canonical playback, every Phase 3B simulation writes distinct legal
start/end pages to all six voices:

| Voice | Start/end register | First byte |
| ---: | ---: | ---: |
| 0 | `000/00F` | `000000` |
| 1 | `010/01F` | `001000` |
| 2 | `020/02F` | `002000` |
| 3 | `030/03F` | `003000` |
| 4 | `040/04F` | `004000` |
| 5 | `050/05F` | `005000` |

The fixture then keys on each voice sequentially, observes the first byte,
keys it off, waits for complete idle, and proceeds to the next voice.
There is never more than one active voice.

## Canonical and control stages

After sentinel verification, only TARGET_VOICE gets canonical registers:

- start `0000`;
- end `000F`;
- global total level `3F`;
- pan/individual level `F5`;
- primary ROM.

All non-target voice levels are zero and their key bits remain off.

Each TARGET_VOICE fixture runs:

1. reset and six-CEN warm-up;
2. explicit FM/SSG/ADPCM-A/ADPCM-B silence;
3. all-register sentinel initialization;
4. six sequential mapping-sentinel probes;
5. 4096-sample canonical stereo playback;
6. left-only `B5`;
7. right-only `75`;
8. global-TL mute `01=00`;
9. unique start `voice<<8`, with end register `voice+0F`;
10. mid-stream individual key-off;
11. natural end over bytes `000000..0000FF`;
12. scheduler-aligned deterministic retrigger;
13. final all-off command `BF`.

The natural-end stage requires exactly 512 target nibble events, last byte
`0000FF` low nibble, active clear, no out-of-range fetch, and 512 following
zero samples.

## Isolation and regression

During each target fixture:

- the reconstructed active mask may contain only TARGET_VOICE;
- only TARGET_VOICE may receive a key-on command;
- only TARGET_VOICE may own a valid fetch;
- only TARGET_VOICE may produce a non-zero decoder event;
- the target ADPCM-A accumulator lane must become non-zero;
- ADPCM-B start, active, fetch, and lanes remain zero;
- all FM channels remain key-off and the FM lane remains zero;
- SSG A/B/C volumes and output remain zero;
- SSG noise and envelope enable events remain zero;
- BUSY timeout and write-while-busy counts remain zero;
- sample X/Z, clipping, drops, and duplicates remain zero.

The Phase 3B runner executes each voice 1-5 three times under Icarus
non-SIMULATION, compares every summary and landmark, repeats each under
SIMULATION, runs Verilator lint/elaboration, then executes the complete
Phase 3A runner. The Phase 3A runner in turn executes the Phase 2B and
Phase 1C regressions. Production source trees and build lists are compared
by Git blob/diff against Phase 3A HEAD.

## Recorded canonical results

The accepted CPU-write sequence is identical for voices 1-5:

- port 0 writes: 17;
- port 1 writes: 88;
- total accepted writes: 105;
- ADPCM-A register writes: 88;
- ADPCM-A command updates: 29;
- BUSY range: 190-192 system cycles;
- BUSY hash: `d8a9137523a7206d`;
- ready cycle: 662;
- first public sample: 799;
- public cadence/width: 144/6 system cycles.

All five canonical fixtures produce 1365 fetches over 683 unique byte
addresses. Their common source-path hashes are:

- fetch: `0395a9d360fa7ca4`;
- address: `ee97dacc6be4aac1`;
- ROM: `8a7e8727bcc15bea`;
- decode: `f04661980311a408`;
- aligned 2048-sample waveform: `5b52746e5b1c3d75`.

The command-aligned results preserve the legal public-sample phase:

| Voice | Issue | Active | First fetch/decode | First lane | First final/index | Attack | Accumulator | Stereo |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 101750 | 101839 | 101983 | 103183 | 103471 / 11 | `644c96291f4e35f1` | `1a18e6c1859ac9b1` | `17e3063b8387e235` |
| 2 | 100826 | 100915 | 101059 | 102319 | 102607 / 12 | `13598990d6fa7801` | `5a49586808fcc2a1` | `a4240e15b4fa2d55` |
| 3 | 100766 | 100855 | 100999 | 102319 | 102607 / 12 | `13598990d6fa7801` | `5a49586808fcc2a1` | `a4240e15b4fa2d55` |
| 4 | 102434 | 102523 | 102667 | 104047 | 104335 / 13 | `5188c28373a617d1` | `d14680af0a188ff5` | `baa7fbb9cf648ced` |
| 5 | 102374 | 102463 | 102607 | 104047 | 104335 / 13 | `5188c28373a617d1` | `d14680af0a188ff5` | `baa7fbb9cf648ced` |

The differing fixed-window hashes reduce to whole-public-sample alignment:
voices 0-5 all produce aligned hash `5b52746e5b1c3d75` with identical
polarity. Every voice reproduces its canonical fetch, address, ROM, decode,
attack, accumulator, aligned, and final hashes on the deterministic
retrigger.

All five natural-end stages produce exactly 512 nibbles through byte
`0000FF` low nibble and then the 512-sample zero hash
`28c31cf8df2ec325`. All mute and post-key-off zero windows have the same
zero hash.
