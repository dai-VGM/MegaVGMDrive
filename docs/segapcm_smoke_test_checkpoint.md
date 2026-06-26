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

The experimental loaded-payload smoke source is additionally guarded by:

```verilog
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_SOURCE_TEST
```

This second macro is intentionally off by default. It owns the local mirror used
to store accepted type-`0x80` payload bytes, so leaving it off prevents Quartus
from allocating that experimental storage in normal smoke builds.

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
status[5]   -> segapcm_smoke_source_loaded
```

The smoke OSD rows are:

```text
SegaPCM Smoke: 0 Base, 1 Slow, 2 Step2, 3 Step4, 4 LowVol, 5 Left, 6 Right, 7 Short
SegaPCM Smoke Source: Preload, Loaded
```

`MEGAVGMDRIVE_SEGAPCM_SMOKE_VARIANT` remains as a guarded compile-time fallback/default for non-OSD harnesses, but normal hardware listening tests should use the OSD selector instead of rebuilding the QSF/RBF for each variant.

Smoke source behavior:

- source `0` / Preload is the default and keeps using the RBF-preloaded known-good payload ROM
- source `1` / Loaded is selectable in the OSD, but with `MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_SOURCE_TEST` off it falls back to the Preload source and reports no loaded payload present
- when `MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_SOURCE_TEST` is explicitly enabled, source `1` / Loaded reads from a smoke-only local mirror of accepted VGM type-`0x80` SegaPCM payload copy bytes
- the smoke channel/control state remains forced; VGM C0 register writes are still ignored in smoke mode
- if Loaded is selected before a type-`0x80` payload has been copied, `LP=0` and the smoke path falls back to Preload
- when enabled, the local loaded mirror stores the first `PRELOAD_ROM_BYTES` bytes, which covers the current smoke windows around `0x2600`

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

Hardware listening notes:

- variant `0`: baseline continuous zaaa/vibrato-like texture
- variant `1`: rough low-rate diesel-engine-like texture
- variants `2` / `3`: audibly different but strange/high-rate noise texture
- variant `4`: machine-gun/retrigger-like texture
- pan variants work; left/right behavior is confirmed
- runtime OSD selector works in one RBF

These observations confirm that the smoke payload step/window/AP controls affect audible output.

Expected smoke source checks:

- Source `Preload`: behavior should match the existing smoke baseline exactly
- Source `Loaded` with `MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_SOURCE_TEST` off: `SC=0001`, `LP=0000`, and the path should keep running via the Preload fallback
- Source `Loaded` with the loaded-source macro on and a copied SegaPCM type-`0x80` payload: sound should change depending on the loaded VGM payload
- Source `Loaded` with the loaded-source macro on but without a copied SegaPCM type-`0x80` payload: `SC=0001`, `LP=0000`, and the path should keep running via the Preload fallback
- With a valid loaded payload, `DA=MD`, `PV=0001`, and `FU=0000` should remain true

## Overlay Rows Of Interest

- `SK`: smoke marker, expected `5A5A`
- `SC`: smoke source, `0000` = Preload, `0001` = Loaded
- `SV`: smoke variant number
- `LP`: loaded payload present
- `LL` / `LH`: loaded payload length low/high
- `LM` / `SM`: smoke mapped payload index, expected `0x2xxx`
- `PS` / `PE`: smoke payload start/end
- `SS`: smoke payload address step
- `SD`: smoke step divider
- `DA`: final byte delivered to `jtoutrun_pcm`
- `MD`: active smoke source byte before final mux
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
