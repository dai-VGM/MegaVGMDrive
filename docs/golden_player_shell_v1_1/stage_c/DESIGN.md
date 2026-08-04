# Golden Player Shell v1.1 Stage C candidate

Stage C migrates the existing standard-YM2610 FM/SSG playback stage behind
the hardware-PASS Golden Player Shell v1.1 boundary. It does not add PCM
playback. ADPCM-A/B commands remain present in the parser trace and counters,
but are not forwarded to JT10 and cannot create a PCM ROM or DDR request.

## Reuse boundary

The new `golden_player_shell_v1_1_profile` is a thin port and safety adapter.
It directly instantiates the existing public `ym2610_golden_stage_a` module
from the immutable Stage C profile source. That profile directly reuses the
Stage B scanner/read adapter and the Stage C owner, parser, and sound adapter.
No scanner, parser, sound adapter, physical DDR protocol, JT10, JT49, or
formal PC-GATE RTL is copied or reimplemented.

The project graph replaces only the old v1.0 shim source with the new wrapper
and the immutable v1.1 shim. The stable `emu`, upload backend, title, video,
OSD/Menu, PLL/reset, pins, device, and SDC remain inherited. The QSF is the
Stage B QSF byte-for-byte after replacing its one profile QIP assignment.

## Lifecycle and ownership

The inherited flow is `WAIT_LOAD -> completion/metadata fences -> SCAN ->
SCANNER_DRAIN/HANDOFF -> SOUND_RESET -> SOUND_ZERO_WAIT -> AUDIO_ARM ->
PLAYBACK_ARM -> PLAYBACK`. Rejection and no-loop completion enter local safe
idle states. Reset, upload/reload, or a profile fault cancels the generation,
closes audio, and returns to the load path.

One unchanged byte-read adapter serves two time-separated owners. Scanner to
parser handoff requires the committed accepted result, scanner request low,
adapter outstanding low, response-valid low, and the inherited two-cycle
quiet fence. Requests are held through acceptance and responses use captured
generation/owner state. PCM DDR clients, cache, and arbitration are absent.

## Registered v1.1 audio gate

`profile_audio_enable` is a `clk_sys` register driven only by public Stage C
outputs. It may rise in `PLAYBACK_ARM` when parser ownership is committed, no
reader transaction is outstanding, the sound adapter is ready, the public
Stage C L/R and sample-valid surface is known zero, and no profile/PCM fault
is present. This edge precedes the parser's consumption of its one start pulse
by a full clock.

The gate remains high through `PLAYBACK`; parser reads are expected there and
therefore are not a hold-condition violation. A loop changes parser PC only:
it does not close/reopen the gate, restart the scanner/parser, or reset JT10.
End, reset, upload/reload, or fault clears the registered gate. Wrapper audio
and sample-valid are fail-closed to known zero whenever it is low.

The immutable v1.1 shim maps enable directly to `audio_gate_open` and its
inverse to `audio_muted`. When open it passes signed 16-bit L/R and
sample-valid into the stable emu `md_audio_l/r` and final `AUDIO_L/R` path.
No synthesis hierarchy reference is used.

## Parser and sound scope

The reused parser supports `58`, `59`, `61`, `62`, `63`, `66`, `67`, and
`70`--`7F`, with defensive PC, size, loop, data-block, opcode, and register
checks. Standard YM2610 FM/global and SSG writes are forwarded. ADPCM-A/B
writes advance PC/time and enter the trace/counters, but do not cause a sound
write or BUSY wait.

The unchanged Stage C sound adapter provides standard YM2610 FM channels
1/2/5/6 and JT49 SSG, 1x signed saturation, header-derived fractional CEN,
deterministic reset phase, BUSY/write sequencing, and public sample-valid.
Olga's raw clock field `0x807A1200` is decoded as B-compatible, non-dual,
8,000,000 Hz; the VGM wait timeline remains 44.1 kHz.

The shared `rtl/genesis_audio/jt12` files in the QIP are the FM engine used by
the retained JT10 boundary. No standalone JT12 device/top, JT51, JTOUTRUN,
SegaPCM, HW-0 sequencer/video/ROM, or Stage D source is included.

## Hardware boundary

All checked results in `NON_QUARTUS_RESULTS.md` are simulation, lint,
elaboration, source-graph, and repository-integrity evidence only. Stage C
remains `hardware_validation_pending`; Stage D is blocked until the dedicated
RBF passes the checklist in `HARDWARE_VALIDATION.md` on MiSTer.
