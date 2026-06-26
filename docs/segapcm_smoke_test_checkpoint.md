# SegaPCM Smoke Test Checkpoint

Date: 2026-06-26

## Milestone

`MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST` is a hardware-proven diagnostic mode for the experimental YM2151 + SegaPCM path. It intentionally bypasses real VGM C0 channel interpretation so the lower-level SegaPCM chain can be tested in isolation.

Hardware validation confirmed:

- `SK = 5A5A`
- `DA = MD`
- `PV = 0001`
- `FU = 0000`
- `AP = 4040`
- `ON = 0030`
- audio starts immediately after RBF load
- smoke sound is continuous and deterministic
- loading different VGMs no longer changes smoke pitch or timbre

This proves on hardware:

- `jtoutrun_pcm` can produce audible output
- the extracted preload ROM payload is read successfully
- final `core_rom_data` receives preload ROM bytes
- fallback `8'h80` is not being selected in smoke mode
- the SegaPCM-only top-level audio path works
- smoke channel state is isolated from VGM loading/playback state

## Guarding

All smoke behavior is guarded by:

```verilog
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
```

The current QSF enables the macro for this checkpoint build:

```tcl
set_global_assignment -name VERILOG_MACRO "MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST=1"
```

Disable this macro before returning to real VGM C0 integration work.

## Smoke Behavior

When the macro is enabled:

- VGM C0 writes are blocked from modifying `jtoutrun_pcm` state.
- Non-smoke SegaPCM channels are forced disabled/silent.
- The smoke channel is forced to a deterministic state:
  - channel: `3`
  - cfg/bank: `8'h30`
  - current: `24'h002600`
  - delta: `8'h20`
  - loop: `24'h002600`
  - volume L/R: `7'h40` / `7'h40`
- the smoke payload window is read from the preload ROM around payload index `0x2600`
- fallback is bypassed when the smoke payload address is in range
- top-level output selects SegaPCM-only audio and does not wait for VGM/player audio unmute state

## Overlay Rows Of Interest

- `SK`: smoke marker, expected `5A5A`
- `LM` / `SM`: smoke mapped payload index, expected `0x2xxx`
- `DA`: final byte delivered to `jtoutrun_pcm`
- `MD`: preload ROM byte before final mux
- `PV`: preload valid, expected `0001`
- `FU`: fallback used, expected `0000`
- `AP`: forced smoke volume/pan display, expected `4040`
- `ON`: forced smoke cfg display, expected `0030`

## Files In Scope

Smoke-mode work is concentrated in:

- `rtl/segapcm_sound_module.sv`
- `rtl/mister_vgm_md_top.sv`
- `rtl/emu.sv`
- `third_party/jtcores/cores/outrun/hdl/jtoutrun_pcm.v`
- `VGM_MD_MiSTer.qsf`

## Third-Party Core Caveat

`third_party/jtcores/cores/outrun/hdl/jtoutrun_pcm.v` currently contains smoke-only guarded edits. This was acceptable for proving the hardware path quickly, but it should be revisited before cleanup or upstream-style integration.

Later cleanup should try to minimize third-party modifications, for example by moving smoke forcing into a wrapper, a narrow debug shim, or a parameterized/test-only interface if feasible.

## Not Yet Done

Do not treat this checkpoint as real SegaPCM VGM integration. The real path still needs separate work on C0 register interpretation, channel mapping, current/start/loop/end handling, and address selection outside smoke mode.

No Quartus compile was run on Mac for this checkpoint.
