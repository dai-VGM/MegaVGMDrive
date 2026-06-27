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

The preferred experimental loaded-payload smoke source is additionally guarded by:

```verilog
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_SMALL_RAM_TEST
```

The lighter tap-only capture debug build is guarded by:

```verilog
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_TAP_ONLY_TEST
```

The tiny RAM loaded-source smoke build is guarded by:

```verilog
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_TINY_RAM_TEST
```

The DDR-backed loaded-source smoke build is guarded by:

```verilog
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
```

The smoke-only loaded-player/parser start diagnostic is guarded by:

```verilog
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_PARSER_RUN_TEST
```

The older full-size mirror is separately guarded by:

```verilog
`ifdef MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_SOURCE_TEST
```

All loaded-source/tap macros are intentionally off by default. The lightest
hardware experiment is `MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_TAP_ONLY_TEST`, which
only counts accepted type-`0x80` payload bytes and records the last payload index
and byte. It does not instantiate a payload RAM and Source `Loaded` still falls
back to the known-good Preload smoke audio path.

If the tap-only build shows `CE=0001` but no parser progress, enable
`MEGAVGMDRIVE_SEGAPCM_SMOKE_PARSER_RUN_TEST` with it. This diagnostic keeps the
Preload smoke audio path unchanged, still ignores VGM C0 writes, and only starts
the loaded-player/parser after a VGM file is ready so parser progress can be
observed.

In tap-only builds, the type-`0x80` payload byte tap is a read-through debug
path. It does not assert the real SegaPCM copy write request, does not allocate
RAM, and Source `Loaded` still falls back to Preload. The tap reads the payload
after the 8-byte SegaPCM ROM data-block header so `CA/LL` count payload bytes,
not header bytes.

`MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_TINY_RAM_TEST` uses the same proven
read-through tap stream, stores the first payload bytes in a tiny synchronous
RAM, and lets Source `Loaded` loop that captured window once `LP=1`. Source
`Preload` remains the default known-good path, and no real C0 writes are
reconnected.

The hardware-facing tiny RAM depth is selected with explicit boolean macros:

```verilog
`define MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_512B_TEST 1
`define MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_1K_TEST 1
`define MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_2K_TEST 1
`define MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_4K_TEST 1
```

Leave all size macros undefined for the proven 256-byte baseline. Define
`MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_512B_TEST` for 512 bytes or
`MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_1K_TEST` for 1024 bytes. Define
`MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_2K_TEST` for 2048 bytes or
`MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_4K_TEST` for 4096 bytes. If multiple size
macros are defined, priority is `4K`, then `2K`, then `1K`, then `512B`. The numeric
`MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_RAM_DEPTH_LOG2` selector is still accepted as
a simulation/backstop knob, but hardware experiments should use the explicit
boolean macros.

The next heavier experiment is `MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_SMALL_RAM_TEST`,
which uses a 16 KiB synchronous RAM for the first accepted type-`0x80` payload
bytes. The older `MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_SOURCE_TEST` path keeps the
larger full-size mirror for comparison only.

`MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST` is the first external-memory
loaded-source experiment. It keeps Source `Preload` unchanged, keeps the smoke
channel/control path forced, and uses the proven type-`0x80` payload tap to copy
only the first 4096 payload bytes into the existing DDRAM SegaPCM ROM window at
`SEGAPCM_ROM_BASE_ADDR`. After `DN/LP` goes high, the debug build issues
continuous sequential readback requests over the captured 4 KiB window while
Source `Loaded` is selected. Source `Loaded` uses a held DDR audio byte after the
first read-valid event; before that, or when no DDR payload is present, it falls
back safely to Preload. No real VGM C0 channel writes are reconnected.

The current QSF enables the base smoke macro for this checkpoint build:

```tcl
set_global_assignment -name VERILOG_MACRO "MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST=1"
set_global_assignment -name VERILOG_MACRO "MEGAVGMDRIVE_SEGAPCM_SMOKE_VARIANT=0"
set_global_assignment -name VERILOG_MACRO "MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST=1"
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
- source `1` / Loaded is selectable in the OSD, but with loaded-source macros off it falls back to the Preload source and reports no loaded payload present
- when `MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_TAP_ONLY_TEST` is explicitly enabled, source `1` / Loaded still falls back to Preload; the build only exposes payload tap counters
- when `MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST` is explicitly enabled, source `1` / Loaded reads from the first 4 KiB copied to DDR after `LP=1` and at least one DDR read-valid event; the held audio byte is not cleared between read returns
- when `MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_SMALL_RAM_TEST` is explicitly enabled, source `1` / Loaded reads from a 16 KiB smoke-only RAM containing the first accepted VGM type-`0x80` SegaPCM payload bytes
- when `MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_SOURCE_TEST` is explicitly enabled instead, source `1` / Loaded reads from the older full-size smoke-only local mirror
- the smoke channel/control state remains forced; VGM C0 register writes are still ignored in smoke mode
- if Loaded is selected before a type-`0x80` payload has been copied, `LP=0` and the smoke path falls back to Preload
- the small RAM stores 16 KiB, which covers the current smoke windows around `0x2600..0x2fff`

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
- Source `Loaded` with loaded-source macros off: `SC=0001`, `LP=0000`, and the path should keep running via the Preload fallback
- Source `Loaded` with `MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_TAP_ONLY_TEST` on: `SC=0001`, `LP=0000`, `CE=0001`, and the path should keep running via the Preload fallback while `CT/CA/WA/WD/LL/LH` expose the payload tap
- Source `Loaded` with `MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_TINY_RAM_TEST` on and a copied SegaPCM type-`0x80` payload:
  - no size macro: `LS=0008`, `LP=0001`, `LC=0100`, `WA=00FF`, and sound should change to a 256-byte loop
  - `MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_512B_TEST`: `LS=0009`, `LP=0001`, `LC=0200`, `WA=01FF`, and sound should change to a 512-byte loop
  - `MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_1K_TEST`: `LS=000A`, `LP=0001`, `LC=0400`, `WA=03FF`, and sound should change to a 1024-byte loop
  - `MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_2K_TEST`: `LS=000B`, `LP=0001`, `LC=0800`, `WA=07FF`, and sound should change to a 2048-byte loop
  - `MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_4K_TEST`: `LS=000C`, `LP=0001`, `LC=1000`, `WA=0FFF`, and sound should change to a 4096-byte loop
- Source `Loaded` with `MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST` on and a copied SegaPCM type-`0x80` payload: `SC=0001`, `DS=0002`, `WQ/WK=1000`, `WI=0FFF`, `WL=0007`, `DN=0001`, `LP=0001`, and `RQ/RK/RI/RW/RL/RD/RP/RN/RC/RV` should update after capture. After the first DDR read-valid event, `DH/DV/DU` should show the held byte, sticky valid flag, and update count; `DA/MD/DD` should reflect the held DDR audio byte and Source `Loaded` should sound different from Preload.
- Source `Loaded` with `MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_SMALL_RAM_TEST` on and a copied SegaPCM type-`0x80` payload: `LP=0001`, `LL=4000`, `LH=0000`, and sound should change depending on the loaded VGM payload
- Source `Loaded` with the small RAM macro on but without a copied SegaPCM type-`0x80` payload: `SC=0001`, `LP=0000`, and the path should keep running via the Preload fallback
- With a valid loaded payload, `DA=MD`, `PV=0001`, and `FU=0000` should remain true

Tap-only loaded-source debug:

- `CE`: tap debug enabled flag, expected `0001`
- `PS`: parser-start debug flags from `mode5_direct_start_debug`; bit0..3 start-attempt count, bit4 parser-run/direct-start debug enabled, bit5 loaded-player start input, bit6 effective start hold, bit7 direct-start used, bit8 smoke parser start hold, bit9 smoke parser start used, bit10 smoke parser-run enabled
- `RD`: readiness flags; bit7 load done, bit6 load busy, bit5 load error, bit4 load overflow, bit3 loaded size greater than 64 bytes, bit2 VGM header valid, bit1 top file ready, bit0 load session active
- `BS`: busy/reset flags; bit7 mode-5 sound reset active, bit6 loaded-player reset, bit5 top reset, bit4 player busy, bit3 SegaPCM scan busy, bit2 player error, bit1 start seen, bit0 header request seen
- `PR`: parser progress flags; bit0 player-or-scan active, bit1 player busy, bit2 scan busy, bit3 scan state nonzero, bit4 header valid
- `PC`: parser command count low word
- `LA`: last parser address low word
- `LB`: last parser command byte
- `DB`: parser data-block count for `0x67 0x66` blocks
- `BT`: last parser data-block type
- `B8`: parser type-`0x80` block count
- `CT`: parser type-`0x80` block count mirrored from `B8`
- `CA`: type-`0x80` payload bytes observed by the tap-only read-through path
- `WA`: last observed payload byte index low word
- `WD`: last observed payload byte
- `LL` / `LH`: observed payload byte count low/high
- `LP`: forced `0000`; Source `Loaded` falls back to Preload in this build
- `PV` / `FU`: smoke ROM valid/fallback sanity flags

Tap-only compact rows when `CE=0001`:

| Row | Label | Value |
| --- | --- | --- |
| 0 | `SK` | smoke marker, expected `5A5A` |
| 1 | `CE` | tap debug enabled marker |
| 2 | `PS` | parser-start flags |
| 3 | `RD` | load/readiness flags |
| 4 | `BS` | busy/reset flags |
| 5 | `PR` | parser progress flags |
| 6 | `PC` | parser command count low word |
| 7 | `LA` | last parser address low word |
| 8 | `LB` | last parser command byte |
| 9 | `DB` | parser data-block count |
| 10 | `BT` | last parser data-block type |
| 11 | `B8` | parser type-`0x80` block count |
| 12 | `CT` | parser type-`0x80` count mirrored from `B8` |
| 13 | `CA` | observed payload byte count |
| 14 | `WA` | last observed payload index low word |
| 15 | `WD` | last observed payload byte |
| 16 | `LL` | observed payload byte count low word |
| 17 | `LH` | observed payload byte count high bits |
| 18 | `PV` | preload/data valid flag |
| 19 | `FU` | fallback used flag |

Tiny-RAM loaded-source rows when `MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_TINY_RAM_TEST`
is enabled:

| Row | Label | Value |
| --- | --- | --- |
| 0 | `SK` | smoke marker, expected `5A5A` |
| 1 | `SC` | OSD smoke source |
| 2 | `LP` | tiny RAM payload present |
| 3 | `SV` | active smoke variant |
| 4 | `B8` | parser type-`0x80` count |
| 5 | `CT` | parser type-`0x80` count mirrored from `B8` |
| 6 | `CA` | full tap observed payload byte count |
| 7 | `LL` | full tap observed payload byte count low word |
| 8 | `LC` | tiny RAM captured byte count, expected `0100` |
| 9 | `WA` | last tiny RAM write address, expected `00FF` |
| 10 | `WD` | last tiny RAM written byte |
| 11 | `DA` | final byte delivered to `jtoutrun_pcm` |
| 12 | `MD` | memory/source byte before fallback mux |
| 13 | `PV` | preload/data valid flag |
| 14 | `FU` | fallback used flag |
| 15 | `LS` | tiny RAM depth log2, expected `0008` through `000C` |
| 18 | `AP` | forced smoke volume/pan display |
| 19 | `ON` | forced smoke cfg display |

DDR loaded-source rows when `MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST` is
enabled:

| Row | Label | Value |
| --- | --- | --- |
| 0 | `SK` | smoke marker, expected `5A5A` |
| 1 | `SC` | OSD smoke source, `0000` Preload or `0001` Loaded |
| 2 | `DS` | DDR smoke marker, expected `0002` |
| 3 | `LP` | DDR payload present, expected `0001` only after `WK=1000` |
| 4 | `WQ` | in-range DDR smoke write request cycles before done, expected `1000` |
| 5 | `WK` | accepted DDR smoke capture bytes, expected `1000` |
| 6 | `WI` | last accepted payload byte index, expected `0FFF` |
| 7 | `WL` | last accepted write byte lane, expected `0007` |
| 8 | `DN` | DDR smoke write done flag, expected `0001` |
| 9 | `RQ` | throttled DDR read request count |
| 10 | `RK` | DDR read returned-valid count |
| 11 | `RI` | last accepted DDR read payload byte index |
| 12 | `RW` | last accepted DDR/backend read word address low |
| 13 | `RL` | last accepted read byte lane |
| 14 | `RD` | last returned DDR read byte |
| 15 | `DH` | held DDR audio byte |
| 16 | `DV` | sticky held DDR audio byte valid flag |
| 17 | `DU` | held DDR audio byte update count |
| 18 | `DA` | final byte delivered to `jtoutrun_pcm` |
| 19 | `MD` | source byte before fallback mux |
| 20 | `DD` | held DDR byte available to the smoke loaded-source mux |
| 21 | `PV` | preload/data valid flag, expected `0001` |
| 22 | `FU` | fallback used flag, expected `0000` |
| 23 | `RP` | last nonzero selected DDR read byte |
| 24 | `RN` | nonzero selected DDR read byte count |
| 25 | `RC` | changing selected DDR read byte count |
| 26 | `RV` | sticky DDR read-valid seen flag |
| 27 | `RB` | DDR read request blocked/backpressure count |
| 28 | `BA` | DDR SegaPCM base address low word shared by write/read |
| 29 | `B8` | parser type-`0x80` block count |
| 30 | `LL` | loaded/tap payload length low word, expected `5A00` |

Small-RAM loaded-source capture debug:

- `CE`: capture path compiled/enabled flag, expected `0001` in small-RAM builds
- `CT`: type-`0x80` SegaPCM block scan count from the top-level scan/copy path
- `LL`: top-reported copied payload byte count low word
- `LC` / `LH`: local small-RAM accepted capture count low/high
- `CA`: accepted copy event count reaching `segapcm_sound_module`
- `WR`: in-range small-RAM write count
- `WA`: last in-range small-RAM write address low word
- `WD`: last in-range small-RAM write byte
- `LP`: local loaded-payload-present latch

When the small-RAM capture build reports the `CE=0001` marker, the compact
SegaPCM overlay is remapped to prioritize capture visibility:

| Row | Label | Value |
| --- | --- | --- |
| 0 | `SK` | smoke marker, expected `5A5A` |
| 1 | `SC` | OSD smoke source |
| 2 | `LP` | loaded payload present |
| 3 | `CE` | capture path compiled/enabled marker |
| 4 | `CT` | type-`0x80` block count |
| 5 | `CA` | copy accept count reaching `segapcm_sound_module` |
| 6 | `WR` | small RAM write count |
| 7 | `WA` | last write address |
| 8 | `WD` | last written byte |
| 9 | `LL` | top copied payload count low word |
| 10 | `DA` | final byte delivered to `jtoutrun_pcm` |
| 11 | `MD` | memory/source byte before fallback mux |
| 12 | `LC` | local capture count low word |
| 13 | `LH` | local capture count high bits |
| 14 | `PV` | preload/data valid flag |
| 15 | `FU` | fallback used flag |
| 18 | `AP` | forced smoke volume/pan display |
| 19 | `ON` | forced smoke cfg display |

Useful interpretation:

- `CT=0`: the current build did not see a type-`0x80` SegaPCM payload block.
- `CT>0` but `CA=0`: the scanner saw a block, but accepted copy events are not reaching the smoke module.
- `CA>0` but `WR=0`: accepted copy events reached the module, but their addresses were outside the small RAM window.
- `WR>0` but `LP=0`: bytes were captured, but the loaded-payload-present/flush indication did not latch.
- `LP=1` with `LC/WR` nonzero: Source `Loaded` should read captured RAM instead of falling back to Preload.

## Overlay Rows Of Interest

- `SK`: smoke marker, expected `5A5A`
- `SC`: smoke source, `0000` = Preload, `0001` = Loaded
- `SV`: smoke variant number
- `DS`: DDR loaded-source marker, expected `0002` in DDR smoke builds
- `WQ` / `WK`: DDR smoke write request and accepted-capture counts
- `WI` / `WL`: last accepted payload byte index and write byte lane
- `WD`: last accepted DDR smoke write data byte
- `DN`: DDR smoke write done flag; this is the same terminal condition that raises `LP`
- `BA`: DDR SegaPCM base address low word used by both write and read debug paths
- `RQ` / `RK` / `RB`: DDR readback request, returned-valid, and blocked-cycle counts
- `RI` / `RW` / `RL`: read payload index, backend read word address low, and read byte lane
- `R0` / `R1`: low/high 16-bit slices of the returned DDR 64-bit word
- `RD` / `RP` / `DD`: selected read byte, last nonzero read byte, and held DDR byte fed to the smoke loaded-source mux
- `DH` / `DV` / `DU`: DDR audio byte hold, sticky hold-valid flag, and hold update count
- `RZ` / `RN` / `RC` / `RV`: zero-byte count, nonzero-byte count, changing-byte count, and sticky valid-seen flag
- `LP`: loaded payload present
- `LL` / `LH`: loaded payload length low/high, or small-RAM top length/local count high in loaded-source capture debug
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
