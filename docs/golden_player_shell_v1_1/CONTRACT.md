# Golden Player Shell v1.1 candidate audio contract

Golden Player Shell v1.1 is a candidate. The hardware-PASS v1.0 baseline at
`35d99c23852a1290257021176e1fe5bc61446726` and stable MegaVGMPlayer v1.0.1
source at `5ecce555edb80bdcb010a322ee46ba8837a6ee27` remain authoritative and
unchanged. No tag or production promotion is made by this work.

## Root cause retained as evidence

The v1.0 compatibility shim drives `audio_gate_open=0` and `audio_muted=1`.
Stable `rtl/emu.sv` correctly implements
`(audio_gate_open && !audio_muted) ? md_audio_l/r : 0`. Consequently the
original Stage C profile reached the shim but could never reach shell-facing
audio. v1.0 is not changed to repair this historical Stage A-only contract.

## v1.1 profile ABI

The versioned profile supplies signed 16-bit `profile_audio_l/r`,
`profile_audio_sample_valid`, and one clocked `profile_audio_enable`.
`profile_audio_enable` is the only gate authority:

| Enable | shim L/R | sample valid | audio_gate_open | audio_muted |
|---:|---|---|---:|---:|
| 0 | signed zero | 0 | 0 | 1 |
| 1 | signed profile L/R | profile valid | 1 | 0 |

The mapping matches stable emu's unchanged active-high open and active-high
mute polarity. The shim explicitly zeros L/R and valid while disabled. No
slice, cast, gain, wrap, or truncation is added. Profiles generate enable in
the `clk_sys` domain and keep it zero through reset, cold start, upload,
abort/reload, fatal/reject/end, and until their audio is known.

Stage A keeps every reader, parser, scanner, sound write, playback status,
and audio output inactive. Audio Lab uses a 44.1 kHz fractional accumulator,
holds each signed sample for the stable shell output, and emits one-cycle
sample-valid pulses only while enabled. Stable MiSTer `audio_out` consumes
the held signed sample; sample-valid remains the existing emu status cadence.
