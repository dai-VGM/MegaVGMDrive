# JT10 Phase 2A JT49 SSG channel-A fixture

Phase 2A remains standalone and test-only. It uses the pristine
JT10/ADPCM sources pinned to JT12 commit
`6d51e0b6f64728c73408079b2f5ffe911bfd88a9`, the production-pinned
JT12/JT49 sources, the Phase 0 compatibility generators and warm-up
wrapper, and the unchanged Phase 1 CPU-bus BFM. Neither the production QSF
nor `files.qip` references this fixture.

## Source provenance

`rtl/genesis_audio/README.md` records the JT49 upstream commit as
`9d097f1eefad3530567b71f13016f6e8546a4bb5`. The vendored local JT49
commit is `6c48d31e70f6959900fe81a8931706fbf00d44ef`; the production pin also
contains the reset-only local commit
`24c4a0cdb8b0ae1940593fd26ec547c16bd9a8cf`. Phase 2A copies these
production-pinned files into a temporary tree and never edits them.

The selected register values come from the repository's established
YM2203/JT49 tone (`00=20`, `01=00`, `07=3E`, `08=0F`) and are checked
against `jt12_mmr` and `jt49`, rather than inferred only from generic
AY-3-8910 documentation.

## Register and clock mapping

Pinned `jt12_mmr` accepts SSG addresses `00` through `0F` only while
`part=0`, so every SSG transaction uses the port-0 `00/01` address/data
phases.

| Register | Function |
|---|---|
| `00`, `01[3:0]` | channel A fine/coarse 12-bit tone period |
| `02`, `03[3:0]` | channel B tone period |
| `04`, `05[3:0]` | channel C tone period |
| `06[4:0]` | noise period |
| `07[2:0]` | tone disable for A/B/C, `1=disable` |
| `07[5:3]` | noise disable for A/B/C, `1=disable` |
| `08`, `09`, `0A` | A/B/C fixed volume in bits `3:0`; envelope select in bit `4` |
| `0B`, `0C` | envelope period low/high |
| `0D[3:0]` | envelope shape |
| `0E`, `0F` | parallel I/O |

Standard JT10 instantiates `jt12_top` with `JT49_DIV=3`. The YM2610 clock
divider supplies the SSG enable at the YM2610 `/4` rate; JT49 uses `sel=1`
and derives `cen16` every eight incoming SSG enables. Raw channels A/B/C
are eight bits and combined `psg_snd` is ten bits.

The standard-YM2610 final mix adds `{1'b0, psg_snd, 5'd0}` to both FM
stereo lanes. With FM and ADPCM idle, channel A is therefore mono-centre
and `snd_left == snd_right == psg_snd << 5`. Fixed volume `0F` produces
raw A `255`, combined PSG `255`, and final left/right `8160`.

## Mixer semantics

Register 7's tone/noise disable bits gate the oscillator and noise source;
they are not channel-mute bits. Pinned `jt49.v` computes channel A's mixer
bit as:

```verilog
Amix <= (noise|use_noA) & (bitA|regarray[7][0]);
```

When both channel-A sources are disabled (`R7[3]=1` and `R7[0]=1`), both
OR terms are forced high and the mixer input becomes fixed High. With a
non-zero fixed volume this deliberately produces constant DC. Channel
silence is obtained by writing volume register `08=00`. This behavior is
the expected behavior of the currently pinned JT49 source.

Phase 2A consequently has two separate controls:

- `08=00` while the tone gate remains enabled must produce 512 zero
  samples;
- `08=0F, 07=3F` must produce 512 constant samples with raw A `255`,
  `psg_snd=255`, and final left/right `8160`, while the internal channel-A
  divider continues toggling.

## Complete write sequence

The BFM reads `dout[7]`, waits for BUSY clear before every phase, performs
the real port address/data transaction, observes BUSY assert and clear,
and rejects timeouts or writes while BUSY.

| Index | Port | Register | Data | Purpose |
|---:|---:|---:|---:|---|
| 1–6 | 0 | `28` | `00,01,02,04,05,06` | key-off all six internal FM encodings |
| 7 | 0 | `22` | `00` | LFO disabled |
| 8 | 0 | `27` | `00` | timers/mode disabled |
| 9 | 0 | `2B` | `00` | DAC disabled |
| 10 | 1 | `00` | `BF` | ADPCM-A all-voice off command |
| 11–12 | 0 | `10` | `01,00` | ADPCM-B reset/stop then clear command |
| 13–15 | 0 | `08,09,0A` | `00,00,00` | fixed volume zero, envelope disabled |
| 16 | 0 | `06` | `00` | known noise period; noise remains gated |
| 17 | 0 | `07` | `3F` | all tone/noise sources disabled |
| 18–19 | 0 | `00,01` | `20,00` | primary channel-A period 32 |
| 20 | 0 | `07` | `3E` | enable A tone only |
| 21 | 0 | `08` | `0F` | fixed maximum volume |
| 22 | 0 | `08` | `00` | true channel mute |
| 23–24 | 0 | `08,07` | `0F,3F` | restore volume, force mixer bit High/DC |
| 25–26 | 0 | `00,01` | `10,00` | changed period 16 |
| 27 | 0 | `07` | `3E` | re-enable A tone |
| 28–29 | 0 | `08,07` | `00,3F` | final volume mute and source gates off |

The envelope period and shape registers remain at reset zero throughout.
Channels B/C retain volume zero and disabled tone/noise gates. The noise
gate is never enabled.

## Capture windows and fixed reference

After the Phase 0 warm-up contract, the fixture captures:

- 16 initial-idle samples;
- 16 explicitly configured idle samples;
- 256 tone-start samples;
- 4096 primary period-32 samples;
- 512 volume-muted samples after 16 consecutive zeros;
- 512 fixed-DC samples after a 256-sample DC lock/soak;
- 4096 changed-period samples;
- 512 final-stop samples after 16 consecutive zeros.

The fixed reference values must match in three non-`SIMULATION` runs and
one `SIMULATION` run:

| Window | Final stereo hash | Raw A hash | `psg_snd` hash | Key statistics |
|---|---|---|---|---|
| tone start | `3d9b8cf5f992b725` | `e5ca3f10da61e8b5` | `8a3bc518252a8fe5` | 128/256 non-zero |
| primary | `54730095b12b6325` | `a05a9500edbbca25` | `3beb13acc8e83f25` | 2048/4096 non-zero, 576 zero transitions |
| volume mute | `28c31cf8df2ec325` | `7da144b97d054b25` | `51d88627df287325` | 512 zeros |
| mixer fixed DC | `0f24568f5401b325` | `be78bcdbd952dd25` | `fbd6d46c9105fb25` | 512/512 at `8160`, zero transitions |
| period change | `ce0045fbf79de325` | `198a0f033c98f725` | `6524f6223fd9d325` | 2048/4096 non-zero, 1151 zero transitions |
| final stop | `28c31cf8df2ec325` | `7da144b97d054b25` | `51d88627df287325` | 512 zeros |

The primary and changed tones both have peak/min/max `8160/0/8160`, DC
sum `16711680`, and mean `4080`. The fixed-DC window has DC sum `4177920`
and mean `8160`. Every window requires equal left/right values, exact
`psg_snd << 5` final mixing, no X/Z, clipping, sample drop, duplicate, FM
activity, PCM activity, ADPCM valid fetch, channel-B/C output, or noise
enable event.
