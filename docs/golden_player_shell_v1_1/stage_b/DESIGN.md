# Golden Player Shell v1.1 Stage B candidate

This stage migrates the already hardware-PASS YM2610 compatibility scan into
the hardware-tested Golden Player Shell v1.1. It adds no playback or audio.
Golden Shell v1.0, the v1.1 shim/audio ABI, Stage A, Audio Lab, and the existing
Stage B implementation remain byte-for-byte unchanged.

## Reuse boundary

The new `golden_player_shell_v1_1_profile` is only a port adapter. It directly
instantiates the existing public `ym2610_golden_stage_a` Stage B profile. That
source, in turn, directly instantiates the existing
`ym2610_golden_stage_b_scanner`,
`ym2610_golden_stage_b_read_adapter`, and compatibility decoder. No Stage B
source is copied or forked.

The existing profile receives `upload_complete` from the unchanged v1.1 shim.
That signal is the stable upload backend's `load_done`, which rises only after
download ends, the byte pack and FIFO drain, the final partial write completes,
and no DDR write is pending. The Stage B lifecycle observes it for two clocks,
validates raw/prepared original size, observes another two-clock scan fence,
and issues one scan start for that load generation.

## State and memory contract

The inherited lifecycle is WAIT_LOAD, completion fence, optional MVGMTTL
metadata reads, metadata validation, scan fence, scan busy, then accepted or
rejected sticky idle. Download or Reset cancels the current generation and
returns to WAIT_LOAD. Reload creates a new generation.

There is exactly one logical DDR client. The existing adapter captures request
address and generation, holds request/address until acceptance, permits at most
one outstanding response, returns data only to the captured generation,
quarantines stale responses, and turns timeout/stale errors into safe rejected
idle. It issues no reads during upload or after scan completion. The unchanged
physical backend performs the existing 64-bit word/lane conversion.

## Scan result

The reused scanner recognizes commands `58`, `59`, `61`, `62`, `63`, `66`,
`67`, and `70`--`7F`. Its sticky classifications are STANDARD,
B_COMPATIBLE, B_REQUIRED, DUAL_UNSUPPORTED, MALFORMED, and
UNSUPPORTED_COMMAND. Reserved/unknown registers reject. Uncompressed `82`
ADPCM-A and `83` ADPCM-B blocks populate separate descriptor tables containing
ROM size, logical range, payload offset/length, source PC, and validity. Stage
B does not connect their mapping surface to playback.

## Inert playback and audio

For every lifecycle state, accepted/rejected result, Reset, abort, and reload:

- `profile_audio_enable`, signed L/R, and sample-valid are zero;
- the unchanged v1.1 shim therefore drives gate closed and mute asserted;
- stable emu final `AUDIO_L/R` remain zero;
- playback/parser starts, sound writes, and both PCM playback requests are
  zero;
- title, video, OSD/Menu, upload, and reset behavior remain inherited.

Stage C migration is forbidden until this candidate passes its separate
Quartus build and MiSTer Stage B hardware validation.
