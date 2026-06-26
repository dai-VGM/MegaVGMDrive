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
set_global_assignment -name VERILOG_MACRO "MEGAVGMDRIVE_SEGAPCM_SMOKE_VARIANT=0"
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

## Smoke Control Sweep

Runtime OSD selection now chooses the active smoke control variant in one RBF:

```verilog
status[4:2] -> segapcm_smoke_variant[2:0]
```

The smoke OSD row is:

```text
SegaPCM Smoke: 0 Base, 1 Slow, 2 Step2, 3 Step4, 4 LowVol, 5 Left, 6 Right, 7 Short
```

`MEGAVGMDRIVE_SEGAPCM_SMOKE_VARIANT` remains as a guarded compile-time fallback/default for non-OSD harnesses, but normal hardware listening tests should use the OSD selector instead of rebuilding the QSF/RBF for each variant.

| Variant | Purpose | Delta | Volume L/R | Payload window |
| --- | --- | --- | --- | --- |
| 0 | Baseline, hardware-proven | `8'h20` | `7'h40` / `7'h40` | `0x2600..0x2fff`, step 1 |
| 1 | Slow payload step | `8'h20` | `7'h40` / `7'h40` | `0x2600..0x2fff`, step 1 every 4 requests |
| 2 | Fast payload step x2 | `8'h20` | `7'h40` / `7'h40` | `0x2600..0x2fff`, step 2 |
| 3 | Fast payload step x4 | `8'h20` | `7'h40` / `7'h40` | `0x2600..0x2fff`, step 4 |
| 4 | Lower volume | `8'h20` | `7'h20` / `7'h20` | `0x2600..0x2fff`, step 1 |
| 5 | Left only | `8'h20` | `7'h40` / `7'h00` | `0x2600..0x2fff`, step 1 |
| 6 | Right only | `8'h20` | `7'h00` / `7'h40` | `0x2600..0x2fff`, step 1 |
| 7 | Shorter periodic window | `8'h20` | `7'h40` / `7'h40` | `0x2600..0x26ff`, step 1 |

Expected hardware checks:

- variant `1` should sound slower/more stretched than baseline
- variant `2` should change faster/brighter than baseline
- variant `3` should change fastest and be most obviously different
- variant `4` should be quieter
- variant `5` should be left-only
- variant `6` should be right-only
- variant `7` should sound more periodic or loop-like

## Overlay Rows Of Interest

- `SK`: smoke marker, expected `5A5A`
- `SV`: smoke variant number
- `LM` / `SM`: smoke mapped payload index, expected `0x2xxx`
- `PS` / `PE`: smoke payload start/end
- `SS`: smoke payload address step
- `SD`: smoke step divider
- `DA`: final byte delivered to `jtoutrun_pcm`
- `MD`: preload ROM byte before final mux
- `PV`: preload valid, expected `0001`
- `FU`: fallback used, expected `0000`
- `AP`: forced smoke volume/pan display, expected `4040`, `2020`, `4000`, or `0040` depending on variant
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
