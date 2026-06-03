# MD Sound Module PSG Phase Note

This note records the first PSG phase after the FM VGM success baseline. The
goal was not to add DAC/PCM support, but only to confirm whether VGM `0x50`
SN76489 writes reach JT89 and whether PSG can be isolated from the final mix.

## Baseline

- FM success state is the baseline.
- `tb/tb_md_sound_module.sv` remained at the 15k short regression length.
- Detailed logs and VCD remained disabled.
- DAC/PCM was not touched.

## PSG Path Confirmed

VGM `0x50` follows this path:

```text
vgm_inspector --emit-sv
  -> send_psg(8'hDD)
  -> tb psg_cmd_valid / psg_cmd_data
  -> md_sound_module jt89_din / jt89_wr_n
  -> jt89 sound
  -> psg_adjust
  -> jt12_genmix psg_snd
  -> final audio_l/audio_r
```

The 15k run reached PSG writes:

```text
PSG write count=22
```

The first PSG commands emitted by the current VGM include are initialization /
mute-style writes:

```text
send_psg(8'h80)
send_psg(8'h00)
send_psg(8'hA0)
send_psg(8'h00)
send_psg(8'hC0)
send_psg(8'h00)
send_psg(8'hE0)
send_psg(8'h9F)
send_psg(8'hBF)
send_psg(8'hDF)
send_psg(8'hFF)
```

That matches the observed PSG-only output being silent in the current 15k
window.

## Minimal Code Changes

- Added `MUTE_PSG` define support in `rtl/md_sound_module.sv`.
  - Default: PSG is unmuted and connected to `jt12_genmix`.
  - With `-DMUTE_PSG`: PSG input to the mixer is forced to zero.
- Added a PSG-only text dump in `tb/tb_md_sound_module.sv`:
  - `/tmp/md_sound_psg_only_15k.txt`
  - It dumps `dut.psg_adjust` as stereo for simple WAV conversion.

`-DMUTE_PSG` build check passed:

```sh
iverilog -g2012 -Wall -DSIMULATION -DMUTE_PSG -s tb_md_sound_module \
  -o /tmp/tb_md_sound_module_mute_psg_check.vvp \
  tb/tb_md_sound_module.sv \
  rtl/md_sound_module.sv \
  rtl/genesis_audio/**/*.v
```

## 15k Regression Result

```text
wav_written_samples=15000
audio_sample_valid_edges=15000
wait_requested_total=14443
wait_actual_edges_total=14443
final_tb_vgm_pc=0000085e
YM write count=591
PSG write count=22
```

Checks:

```text
wav_written_samples == audio_sample_valid_edges : OK
wait_requested_total == wait_actual_edges_total : OK
```

No writes occurred during a VGM wait:

```text
ym_writes_during_wait=0
psg_writes_during_wait=0
```

## Audio Stats

```text
final:
samples=15000 min=-2478 max=3305 nonzero=28790 rms=864.71 clip_count=0

FM only:
samples=15000 min=-2515 max=3359 nonzero=28796 rms=877.98 clip_count=0

PSG only:
samples=15000 min=0 max=0 nonzero=0 rms=0.00 clip_count=0
```

The final and FM-only stats match the prior FM success 15k run, so the FM
success baseline was not broken by the PSG phase changes.

## WAV Outputs

- `~/Downloads/md_sound_vgm_psg_phase_final_gain1_15k.wav`
- `~/Downloads/md_sound_vgm_psg_phase_fm_only_gain1_15k.wav`
- `~/Downloads/md_sound_vgm_psg_phase_psg_only_gain1_15k.wav`

## Conclusion

- VGM `0x50` writes are entering the existing PSG command path.
- JT89 is instantiated and connected into `jt12_genmix`.
- PSG can now be muted at compile time with `-DMUTE_PSG`.
- In the current 15k VGM window, PSG output is silent because the observed PSG
  writes are initialization/mute writes.
- FM playback remains intact.

## Next PSG TODO

- Test with a VGM segment or small generated sequence that contains audible PSG
  tone/volume writes.
- Add a PSG-only tone regression using VGM-style `send_psg` commands.
- Once audible PSG is confirmed, compare final mix with and without
  `-DMUTE_PSG`.

## Manual PSG Tone Result

`TEST_PSG_TONE` was used to bypass the VGM include and drive JT89 with manual
`send_psg` commands only.

Sequence:

```text
send_psg(8'h9F)  channel 0 volume silent
send_psg(8'hBF)  channel 1 volume silent
send_psg(8'hDF)  channel 2 volume silent
send_psg(8'hFF)  noise volume silent
send_psg(8'h80)  channel 0 tone low latch
send_psg(8'h10)  channel 0 tone high bits
send_psg(8'h90)  channel 0 volume unmuted
```

Build/run:

```sh
iverilog -g2012 -Wall -DSIMULATION -DTEST_PSG_TONE -s tb_md_sound_module \
  -o /tmp/tb_md_sound_module_psg_tone.vvp \
  tb/tb_md_sound_module.sv \
  rtl/md_sound_module.sv \
  rtl/genesis_audio/**/*.v

vvp /tmp/tb_md_sound_module_psg_tone.vvp > /tmp/psg_tone.log
```

Result:

```text
wav_written_samples=10000
audio_sample_valid_edges=10000
ym_write_count=0
psg_write_count=7
```

Audio stats:

```text
final:
samples=10000 min=-1812 max=1795 nonzero=19990 rms=1786.25

PSG only:
samples=10000 min=-247 max=248 nonzero=20000 rms=247.51

FM only:
samples=10000 min=0 max=0 nonzero=0 rms=0.00
```

WAV outputs:

```text
~/Downloads/md_sound_psg_tone_gain1.wav
~/Downloads/md_sound_psg_tone_gain4.wav
```

`MUTE_PSG` check:

```sh
iverilog -g2012 -Wall -DSIMULATION -DTEST_PSG_TONE -DMUTE_PSG \
  -s tb_md_sound_module \
  -o /tmp/tb_md_sound_module_psg_tone_muted.vvp \
  tb/tb_md_sound_module.sv \
  rtl/md_sound_module.sv \
  rtl/genesis_audio/**/*.v

vvp /tmp/tb_md_sound_module_psg_tone_muted.vvp > /tmp/psg_tone_muted.log
```

Muted stats:

```text
final:
samples=10000 min=0 max=0 nonzero=0 rms=0.00

PSG source tap:
samples=10000 min=-247 max=248 nonzero=20000 rms=247.51
```

Conclusion:

- Manual PSG tone reaches JT89.
- `psg_adjust` is nonzero.
- The PSG signal reaches the final mix when `MUTE_PSG` is not defined.
- `-DMUTE_PSG` mutes only the mixer input; the JT89/source tap still runs.
- Normal FM 15k configuration still builds after this change.
