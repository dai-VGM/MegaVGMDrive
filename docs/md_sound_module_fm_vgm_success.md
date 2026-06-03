# MD Sound Module FM VGM Success Note

This note records the current successful state where a VGM-derived YM2612/FM
intro plays musically through JT12 in `md_sound_module`.

## Current Changed File Set

This workspace is not a git repository, so this is the known project-local file
set involved in the current successful state.

- `rtl/md_sound_module.sv`
- `tb/tb_md_sound_module.sv`
- `tools/vgm_inspector/vgm_inspector.cpp`
- `tools/vgm_inspector/README.md`
- `tools/vgm_inspector/Makefile`
- `tools/audio_txt_to_wav/audio_txt_to_wav.py`
- `rtl/genesis_audio/README.md`
- `rtl/genesis_audio/filters/audio_iir_filter.v`
- `rtl/genesis_audio/filters/genesis_lpf.v`
- `rtl/genesis_audio/jt12/**/*.v`
- `rtl/genesis_audio/jt89/**/*.v`

## Fixes Needed For Successful FM VGM Playback

- Copied the minimal Genesis_MiSTer/JT HDL dependency set under
  `rtl/genesis_audio/`.
- Added `md_sound_module` as a small wrapper around `jt12`, `jt89`,
  `jt12_genmix`, and `genesis_lpf`.
- Matched JT12 register write order to the official JT12 style:
  address write, data write, then wait for `jt12_dout[7]` busy clear.
- Held JT12/JT89 write strobes long enough to be seen by the relevant clock
  enable domain.
- Added a JT12 reset stretcher so reset remains asserted for enough FM clock
  enable cycles.
- Gated the FM signal into the mixer until the internal audio path is ready, to
  avoid early X propagation into the mixer/filter path.
- Changed `tb_md_sound_module` `wait_samples(n)` to count
  `audio_sample_valid` rising edges, not clock cycles or signal level time.
- Changed WAV dumping to write exactly one sample per `audio_sample_valid`
  rising edge.
- Added `vgm_inspector --emit-sv` output for VGM-derived `send_ym`,
  `send_psg`, and `wait_samples` calls.

## Short Regression Test Procedure

The testbench currently uses a local constant in `tb/tb_md_sound_module.sv`:

```systemverilog
localparam int AUDIO_DUMP_SAMPLE_COUNT = <sample_count>;
```

For each short test, set the count and temporary text filenames to the desired
suffix, then run:

```sh
iverilog -g2012 -Wall -DSIMULATION -s tb_md_sound_module \
  -o /tmp/tb_md_sound_module_vgm_<N>.vvp \
  tb/tb_md_sound_module.sv \
  rtl/md_sound_module.sv \
  rtl/genesis_audio/**/*.v

vvp /tmp/tb_md_sound_module_vgm_<N>.vvp > /tmp/vgm_<N>.log
```

Expected checks:

- `wav_written_samples == audio_sample_valid_edges`
- `wait_requested_total == wait_actual_edges_total`
- `ym_writes_during_wait == 0`
- `psg_writes_during_wait == 0`

### 5k Result

```text
wav_written_samples=5000
audio_sample_valid_edges=5000
wait_requested_total=714
wait_actual_edges_total=714
final_tb_vgm_pc=000006de
YM write count=505
PSG write count=11
```

### 10k Result

```text
wav_written_samples=10000
audio_sample_valid_edges=10000
wait_requested_total=6953
wait_actual_edges_total=6953
final_tb_vgm_pc=00000743
YM write count=527
PSG write count=11
```

### 15k Result

```text
wav_written_samples=15000
audio_sample_valid_edges=15000
wait_requested_total=14443
wait_actual_edges_total=14443
final_tb_vgm_pc=0000085e
YM write count=591
PSG write count=22
```

## Successful WAV Outputs

The following WAVs were generated from the successful edge-synchronized runs:

- `~/Downloads/md_sound_vgm_fixed_final_gain1_5k.wav`
- `~/Downloads/md_sound_vgm_fixed_fm_only_gain1_5k.wav`
- `~/Downloads/md_sound_vgm_fixed_final_gain1_10k.wav`
- `~/Downloads/md_sound_vgm_fixed_fm_only_gain1_10k.wav`
- `~/Downloads/md_sound_vgm_fixed_final_gain1_15k.wav`
- `~/Downloads/md_sound_vgm_fixed_fm_only_gain1_15k.wav`

15k stats:

```text
final gain1:
frames=15000 min=-2478 max=3305 nonzero=28790 rms=864.71 clip_count=0

fm_only gain1:
frames=15000 min=-2515 max=3359 nonzero=28796 rms=877.98 clip_count=0
```

## Next Phase TODO

PSG:

- Verify VGM `0x50` PSG writes against JT89 with musical PSG test material.
- Add PSG-only and FM+PSG short regression WAVs.

DAC/PCM:

- Decide how to handle VGM data blocks `0x67`, PCM seek `0xE0`, and DAC stream
  commands `0x80`-`0x8f` in the HDL-side playback path.
- Keep non-DAC FM playback stable while adding DAC support.

Loop/end:

- Add controlled handling for VGM end `0x66`.
- Add loop offset / loop sample support after the straight-line player remains
  stable.

Long run speed:

- Reduce simulation cost before returning to 20k+ or full-song runs.
- Consider parameterized sample counts and output paths instead of manually
  editing the testbench for each length.
- Keep VCD and verbose debug logs disabled by default.
