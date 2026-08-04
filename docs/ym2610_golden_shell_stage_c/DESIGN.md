# YM2610 Golden Player Shell Stage C

## Scope and immutable boundary

Stage C adds only the playback parser, time-separated parser DDR ownership,
44.1 kHz VGM timeline, header-derived YM2610 clock, and a profile-local
standard-FM/SSG sound adapter. Golden Shell Stage A and the hardware-PASS
Stage B scanner/read/classification modules are direct immutable references.
ADPCM-A/B writes are parsed, classified, counted, and traced but never sent to
JT10. There is no PCM logical reader, cache, DDR client, or multi-client
arbiter.

The source graph uses the six HW-0-validated derivative JT10 boundary files,
the formal PC-GATE overlay, shared FM engine, JT49, and the seven immutable
6d51e0b6 vendor-pin leaves. The latter live under `tb/jt10_pinned` for
provenance but are synthesizable vendor RTL, not testbenches. HW-0 sequencer,
video, ROMs, wrapper, self-test top, and old YM2610 player are absent.

## Lifecycle and reader ownership

The lifecycle is `WAIT_LOAD -> COMPLETE_FENCE -> metadata trailer read ->
SCAN -> HANDOFF -> SOUND_RESET -> SOUND_ZERO_WAIT -> PLAYBACK_ARM ->
PLAYBACK`. Reject, no-loop end, and profile faults enter local safe idle
states. Software Reset returns to `WAIT_LOAD`; a new upload is required.

One unchanged Stage B byte-reader adapter serves two time-separated owners.
The scanner owns it through the atomic scan result. Handoff requires scanner
request low, adapter outstanding low, response-valid low, and two quiet
`clk_sys` cycles. Only then can the parser request. Cancel/reset returns to
`OWNER_NONE`; captured generation metadata, rather than live owner, handles
late responses.

## Parser and forwarding

Supported commands are `58`, `59`, `61`, `62`, `63`, `66`, `67`, and
`70`-`7F`. PC advances only after an accepted byte response. Data blocks use
their declared size and accept only the scanner-supported `82`/`83` forms.
The original VGM body size is the hard limit; MVGMTTL is never decoded as VGM.

Every write contributes command PC, VGM sample, port, address, data,
semantic, forwarding decision, next PC, and sound-accept cycle to the trace.
Standard YM2610 FM channels 1/2/5/6, global controls, and SSG are forwarded.
ADPCM-A/B writes take the suppressed trace path without BUSY delay. B-only,
dual, unknown, malformed, or unsupported input cannot reach playback after a
normal Stage B scan and is still rejected defensively by the parser.

Wait commands count exact 44.1 kHz samples. A 32-bit accumulator adds 44,100
against the 20,000,000 Hz `clk_sys`, giving zero long-term integer-ratio error
and deterministic reset/reload phase. Writes do not advance VGM time. A BUSY
stall beyond 64 VGM samples is fatal and externally muted.

## Sound boundary

The chip CEN accumulator is 32 bits and adds the committed header clock. Olga
uses 8,000,000 Hz from raw `807A1200`; variant and dual bits are removed by the
Stage B result. At 20 MHz the exact mean CEN ratio is 2/5, so mean frequency
error is 0 Hz. Clock zero or above `clk_sys` is rejected.

Reset supplies CEN, clears both accumulators, holds public audio at zero, and
waits for the verified five-sample core warm-up plus a public sample edge.
The parser receives one one-cycle start. Loops change PC only: core reset,
scanner start, and parser start remain zero. No-loop end externally mutes and
preserves final parser diagnostics until reload.

FM and unsigned JT49 output (`psg_snd << 5`) are summed in signed 17-bit
space and saturated to signed 16-bit L/R; wrap is impossible. Gain is 1x and
the Golden Shell `AUDIO_S` format is unchanged. ADPCM ROM data is a known
zero, asserted-low requests are sticky-fatal, PCM outputs are monitored, and
no request is connected to DDR. The pinned ADPCM-A driver leaves inactive
`roe_n` unknown until its first command in four-state simulation, so the
adapter treats only an explicit low as an asserted request; a real low is
still detected and fails Stage C.

## Reference results

- Olga: 171869 commands, 81272 writes, 8372668 samples, 7 data blocks.
- Forwarded FM/global: 78293; forwarded SSG: 0.
- Suppressed ADPCM-A: 2752; suppressed ADPCM-B: 227.
- Trace hash: `7c3088bd1d4eea6f`; first 256: `155cbbc09e7b636b`.
- First ADPCM-B control: sample 4625 (suppressed).
- First standard FM key-on: sample 120851 (forwarded).
- First ADPCM-A control: sample 121270 (suppressed).
- Loop target: `000B6223`; boundary sample 4346806; loop length 4025862.
- Synthetic direct/parser FM audio: `2a1aa6dc21860dfd`.
- Twin direct/parser SSG replay: `37598f8641f2e9ad` at its 8.82 MHz replay contract.
- Standalone SSG A/B/C tone contract: `2d7fa36247dc0e75`.
- Explicit volume mute: `28c31cf8df2ec325`.

`olga_replay_windows.json` records five non-copyright metadata windows for
first key-on, sustained FM, mid-song, loop-target, and loop-crossing order.
The retained-state, accelerated-timeline twin-core replay produced matching
FM-lane and final-L/R hashes in three deterministic runs:

- First FM key-on: `bda45f7a067cf72d`.
- First sustained FM: `dc663bb0b7349cd5`.
- Mid-song FM: `184eec59e4466a7d`.
- Loop target, first pass: `a4a707ca22e4bb61`.
- Loop crossing: `87a5398c48b391c1`.

Only the VGM sample tick is accelerated; the two sound cores retain the exact
header-derived 8 MHz CEN and continuous state through the loop. The full
81272-row RTL trace is compared byte-for-byte with the independent Python
trace in `/tmp` and is never committed.

## Hardware report

Golden Shell Stage C:

- Full Compilation:
- ALM:
- RBF cold start:
- Stage A/Bと同じ解像度:
- LCD/HDMI表示:
- OSD/Menu:
- Olga load:
- Directory:
- Basename:
- scan:
- playback開始:
- 最初の2.74秒:
- FM開始:
- FMの聴感:
- PCMらしき音:
- 30秒:
- 2分:
- 3分10秒以降loop:
- 映像信号維持:
- OSD復帰:
- software Reset:
- reload:
- reload後の曲頭:
- synthetic SSG A:
- synthetic SSG B:
- synthetic SSG C:
- debug自動切替:
- fatal:
- power cycle必要:
- 備考:

Stage D is blocked until this Stage C report passes on MiSTer hardware.
