# MD Sound Module Hardware Bring-up Plan

This note records the first synthesizable hardware bring-up step after the RTL
simulation success.

The goal is not to build a full SD-card VGM player yet. The goal is only to
embed a tiny fixed VGM-like region in FPGA logic, stream it once into
`md_sound_module`, and confirm that `audio_l` / `audio_r` can produce sound on
real hardware.

## New HDL

```text
rtl/vgm_region_player.sv
```

This file contains two modules:

```text
vgm_region_player
md_sound_fixed_region_test
```

## vgm_region_player

`vgm_region_player` is a small synthesizable sequencer. It does not instantiate
the sound cores by itself. It only generates command handshakes compatible with
`md_sound_module`.

Inputs:

```text
clk
reset
start
audio_sample_valid
ym_cmd_ready
psg_cmd_ready
```

Outputs:

```text
ym_cmd_valid
ym_cmd_port
ym_cmd_reg
ym_cmd_data
psg_cmd_valid
psg_cmd_data
busy
done
pc_debug
last_cmd_debug
```

The sequencer supports only the small command subset needed by the built-in
test region:

```text
0x52 rr dd   YM2612 port 0 write
0x53 rr dd   YM2612 port 1 write
0x50 dd      SN76489 write
0x61 ll hh   wait n samples
0x62         wait 735 samples
0x63         wait 882 samples
0x70-0x7f    short wait 1..16 samples
0xe0 oooo    tiny PCM seek for local built-in PCM bytes
0x80-0x8f    generate YM2612 reg 0x2A DAC write, then wait low nibble
0x66         end
```

Wait timing counts `audio_sample_valid` rising edges from `md_sound_module`.

## Built-in Region

The fixed region is intentionally small, around a few thousand audio samples.
It is based on already successful simulation sequences:

- Simple YM2612 channel-1 FM tone setup from `TEST_YM_TONE`.
- Simple SN76489 channel-0 tone setup from `TEST_PSG_TONE`.
- Tiny DAC exercise using YM register `0x2B` enable and generated `0x2A` writes.

This is not a real song player. It is a smoke test for:

```text
fixed ROM commands
  -> vgm_region_player
  -> md_sound_module YM/PSG command inputs
  -> JT12 / JT89 / mixer
  -> audio_l / audio_r
```

## Convenience Wrapper

`md_sound_fixed_region_test` instantiates both:

```text
vgm_region_player
md_sound_module
```

This wrapper is meant for the first MiSTer/top-level experiment. A top-level can
instantiate it and route:

```text
clk/reset/start -> md_sound_fixed_region_test
audio_l/audio_r -> platform audio output
```

For a more complete design, instantiate `vgm_region_player` and
`md_sound_module` separately and keep the same command wiring.

## No Simulation-only Features

`rtl/vgm_region_player.sv` does not use:

```text
$fopen
$display
$dumpfile
/tmp paths
WAV dump logic
```

Those remain in the testbench only.

## Syntax Check

Standalone player check:

```sh
iverilog -g2012 -Wall -s vgm_region_player \
  -o /tmp/vgm_region_player_check.vvp \
  rtl/vgm_region_player.sv
```

Wrapper plus sound-core dependency check:

```sh
iverilog -g2012 -Wall -DSIMULATION -s md_sound_fixed_region_test \
  -o /tmp/md_sound_fixed_region_test_check.vvp \
  rtl/vgm_region_player.sv \
  rtl/md_sound_module.sv \
  rtl/genesis_audio/**/*.v
```

Both checks passed. Remaining warnings are the existing JT12/timescale style
warnings already seen in earlier simulation work.

## Fixed Region Wrapper Simulation

Before moving to MiSTer hardware, the hardware wrapper can be exercised in a
small simulation testbench:

```text
tb/tb_md_sound_fixed_region_test.sv
```

This testbench instantiates `md_sound_fixed_region_test`, pulses `start`, waits
for `audio_sample_valid` rising edges, and writes 5000 stereo samples to:

```text
/tmp/md_sound_fixed_region_test_5k.txt
```

Build/run:

```sh
iverilog -g2012 -Wall -DSIMULATION -s tb_md_sound_fixed_region_test \
  -o /tmp/tb_md_sound_fixed_region_test.vvp \
  tb/tb_md_sound_fixed_region_test.sv \
  rtl/vgm_region_player.sv \
  rtl/md_sound_module.sv \
  rtl/genesis_audio/**/*.v

vvp /tmp/tb_md_sound_fixed_region_test.vvp \
  > /tmp/tb_md_sound_fixed_region_test.log
```

WAV conversion:

```sh
python3 tools/audio_txt_to_wav/audio_txt_to_wav.py \
  /tmp/md_sound_fixed_region_test_5k.txt \
  /tmp/md_sound_fixed_region_test_5k.wav \
  --gain 2
```

Successful 5k result:

```text
wav_written_samples=5000
audio_sample_valid_edges=5000
pc=126
last_cmd=66
samples=5000
min=-2513
max=6022
nonzero=9916
rms=1856.53
clip_count=0
```

## MiSTer Bring-up Notes

- Feed `clk` with the same master-clock style expected by `md_sound_module`.
- Hold `reset` long enough for the existing JT12 reset stretcher to run.
- Tie `start` high for auto-play once after reset, or pulse it high manually.
- Observe `player_done` to confirm the fixed region has ended.
- Route `audio_l` / `audio_r` to the MiSTer audio path using the same signed
  sample convention expected by the surrounding top-level.

## Not Yet Implemented

- SD card / HPS VGM loading.
- VGZ decompression.
- Large PCM data banks in BRAM.
- Full VGM loop/end handling in hardware.
- DAC Stream Control `0x90`-`0x95`.
- A real hardware VGM parser for arbitrary songs.
- Clock-domain crossing or FIFO buffering for external command sources.
