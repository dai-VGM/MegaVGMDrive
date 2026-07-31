# JT10 Phase 2B three-channel SSG fixture

Phase 2B remains standalone and test-only. It reuses the Phase 2A CPU-bus,
warm-up, hash, fixed-DC, mute, period-change, and lane-isolation checks
through one parameterized common TB. Channel B and C add only thin wrapper
tops. Production RTL, pinned JT10/JT49 sources, compatibility generators,
QSF, and `files.qip` are not changed.

## Exact channel mapping

Pinned `jt49.v` supplies three identical 12-bit divider instances:

| Target | Fine/coarse | Volume | Tone disable | Noise disable | Raw output | JT49 register indices |
|---|---|---|---|---|---|---|
| A (`0`) | `00/01` | `08` | R7 bit 0 | R7 bit 3 | `psg_A` | 0, 1, 8 |
| B (`1`) | `02/03` | `09` | R7 bit 1 | R7 bit 4 | `psg_B` | 2, 3, 9 |
| C (`2`) | `04/05` | `0A` | R7 bit 2 | R7 bit 5 | `psg_C` | 4, 5, 10 |

All SSG registers remain on JT10 port 0. The common TB selects the raw
target and both non-target raw channels from `TARGET_CHANNEL`; every
non-target sample must remain zero.

## Common 29-write sequence

Indices 1–17 and final index 29 are identical for all targets:

- `28=00,01,02,04,05,06`: all FM encodings key-off;
- `22=00`, `27=00`, `2B=00`: LFO, timers/mode, DAC disabled;
- port 1 `00=BF`: ADPCM-A all voices off;
- port 0 `10=01,00`: ADPCM-B reset/stop;
- `08=00`, `09=00`, `0A=00`, `06=00`, `07=3F`: explicit SSG silence.

The target-dependent writes are:

| Stage | A | B | C |
|---|---|---|---|
| Primary period | `00=20,01=00` | `02=20,03=00` | `04=20,05=00` |
| Tone-only mixer | `07=3E` | `07=3D` | `07=3B` |
| Fixed volume | `08=0F` | `09=0F` | `0A=0F` |
| Volume mute | `08=00` | `09=00` | `0A=00` |
| Fixed-DC setup | `08=0F,07=3F` | `09=0F,07=3F` | `0A=0F,07=3F` |
| Changed period | `00=10,01=00,07=3E` | `02=10,03=00,07=3D` | `04=10,05=00,07=3B` |
| Final stop | `08=00,07=3F` | `09=00,07=3F` | `0A=00,07=3F` |

R7 tone/noise disable gates force the selected mixer bit High when both
sources are disabled. Fixed volume `0F` therefore produces raw target
`255`, combined PSG `255`, and final left/right `8160`. True silence uses
target volume zero. All noise gates remain disabled, all volume bit 4
envelope selects remain zero, and envelope period/shape registers remain
at reset values.

## Measured three-channel comparison

A, B, and C are sample-for-sample identical at zero alignment with the
common reset and write schedule:

| Window | Target raw hash | PSG hash | Final stereo hash | Statistics |
|---|---|---|---|---|
| Primary period 32 | `a05a9500edbbca25` | `3beb13acc8e83f25` | `54730095b12b6325` | 2048/4096 non-zero, transitions 576, DC 16711680 |
| Volume mute | `7da144b97d054b25` | `51d88627df287325` | `28c31cf8df2ec325` | 512 zeros |
| Fixed DC | `be78bcdbd952dd25` | `fbd6d46c9105fb25` | `0f24568f5401b325` | 512 at 8160, transitions 0 |
| Changed period 16 | `198a0f033c98f725` | `6524f6223fd9d325` | `ce0045fbf79de325` | 2048/4096 non-zero, transitions 1151 |
| Final stop | `7da144b97d054b25` | `51d88627df287325` | `28c31cf8df2ec325` | 512 zeros |

Primary and changed windows have peak/min/max `8160/0/8160`, mean `4080`,
and no clipping. Each target uses 29 accepted writes (port 0/1 = 28/1),
17 JT49 register updates, BUSY hash `077f33fe691dd273`, warm-up ready cycle
662, first public cycle 799, and tone-enable issue cycle 9322.
