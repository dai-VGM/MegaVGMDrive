# Large VGM Backend Plan

## Goal

Support VGM files larger than the current mode5 internal BRAM limit without
regressing the proven BRAM-loaded playback path.

The first implementation must keep the existing mode5 BRAM backend as the
default and reference path. Large-file work should be added behind an explicit
backend selection layer, not by rewriting `vgm_loaded_player` or the mode5
session/repeat controller.

## Current Mode5 Path

Mode5 currently works as:

```text
hps_io ioctl file download
  -> vgm_file_loader internal BRAM
  -> vgm_bram_read_adapter
  -> vgm_loaded_player byte-read IF
  -> md_sound_module
```

Important current properties:

- `VGM_LOAD_ADDR_WIDTH=18`, so the active file capacity is 256 KiB.
- `hps_io` already provides `ioctl_download`, `ioctl_wr`, `ioctl_addr[26:0]`,
  `ioctl_dout`, and `ioctl_index`.
- `vgm_loaded_player` no longer reads BRAM directly. It consumes a byte read
  interface:

```systemverilog
mem_rd_req
mem_rd_addr
mem_rd_ready
mem_rd_valid
mem_rd_data
```

This byte-read IF is the right boundary for large-file backend work.

## Template Memory Paths Found In This Repo

The local Template_MiSTer-derived wrapper exposes several storage paths:

- `hps_io.sv` file download path:
  - ARM -> FPGA download through `ioctl_*`.
  - Address is already 27 bits wide on `ioctl_addr`.
  - Good for full-file loading, but current `vgm_file_loader` truncates to the
    configured internal BRAM width.
- `hps_io.sv` SD block path:
  - `sd_lba`, `sd_rd`, `sd_wr`, `sd_ack`, and `sd_buff_*` exist in the template.
  - Suitable for sector/block streaming, but it requires a mounted image or
    block-oriented flow, not the current simple OSD file download flow.
- DDRAM framework path:
  - `emu.sv` exposes `DDRAM_CLK`, `DDRAM_BUSY`, `DDRAM_BURSTCNT`,
    `DDRAM_ADDR`, `DDRAM_DOUT`, `DDRAM_DOUT_READY`, `DDRAM_RD`,
    `DDRAM_DIN`, `DDRAM_BE`, and `DDRAM_WE`.
  - `sys/sys_top.v` connects those signals to the MiSTer framework RAM bridge.
  - `sys/arcade_video.v` shows an existing write-only DDRAM usage pattern.
- SDRAM pins:
  - `emu.sv` exposes the raw SDRAM pin set.
  - `sys/sys.tcl` assigns the SDRAM pins.
  - No SDRAM controller is currently instantiated in this core.

Today, `emu.sv` leaves SD, SDRAM, and DDRAM outputs inactive/defaulted. Large
VGM support should first use the existing DDRAM framework-style port or a new
well-scoped SDRAM controller adapter, rather than wiring raw memory access into
the player.

## Backend Options

### Option A: Full VGM In DDRAM

Load the whole VGM through `ioctl_*`, write it into DDRAM, then serve player
byte reads from DDRAM through a cache/prefetch adapter.

Pros:

- Closest mental model to the current BRAM loader.
- Keeps VGM parser semantics unchanged.
- Supports command bytes, header, data blocks, and PCM bank as one address
  space.
- Good first large-file target because `ioctl_addr` is already wider than the
  BRAM address.

Cons:

- Needs an HPS-download-to-DDRAM writer.
- Needs arbitration between loader writes and player reads.
- DDRAM read latency is not byte-like, so a cache line or FIFO is mandatory.

Recommendation: best first real large-file backend.

### Option B: Full VGM In SDRAM

Load the whole VGM into external SDRAM and serve player byte reads from SDRAM.

Pros:

- SDRAM can offer lower and more deterministic latency than DDRAM if the
  controller is simple and dedicated.
- Keeps one file address space.

Cons:

- This repo currently has raw SDRAM pins but no active SDRAM controller in the
  VGM path.
- Controller bring-up can distract from the already-working mode5 path.
- Board SDRAM presence/size must be handled.

Recommendation: viable later, but not the safest first step.

### Option C: Command Stream In External Memory + PCM Bank In External Memory

Parse the VGM during load, store command stream and type-0 PCM bank in separate
regions, then make player reads target the appropriate region.

Pros:

- Can optimize command prefetch and PCM reads independently.
- Gives clearer cache behavior for DAC stream playback.
- Sets up future metadata/indexing.

Cons:

- Requires a load-time parser or relocation table.
- Higher risk of changing PCM/DAC parser semantics.
- More debug surface before the basic 1 MiB file works.

Recommendation: do not start here. Consider after full-file external backend is
stable.

### Option D: BRAM Cache/Prefetch + External Memory

Keep the file in DDRAM/SDRAM, but put a small BRAM cache in front of the
existing byte-read IF.

Pros:

- Matches `vgm_loaded_player` naturally.
- Hides most command stream latency.
- Can be tested with artificial-latency backends before using real DDRAM.
- Keeps the existing BRAM loader as a separate backend.

Cons:

- Needs cache miss and refill logic.
- Must handle non-sequential reads: VGM header reads, command stream, loop
  target, PCM bank seeks, and DAC stream byte reads.

Recommendation: required component for either DDRAM or SDRAM backend.

### Option E: HPS/SD Streaming

Use the `hps_io` SD block path or another HPS-mediated path to stream sectors
on demand rather than loading the whole file first.

Pros:

- Could support files much larger than memory.
- Avoids a full preload step.

Cons:

- Sector latency is large and variable.
- Hard to guarantee PCM DAC stream timing without deep buffering.
- More moving pieces than the current stable OSD load flow.

Recommendation: later-stage feature, not the first large-file backend.

## Recommended Architecture

Add a backend-select layer between mode5 control and `vgm_loaded_player`:

```text
mode5 loader/control
  -> backend select
      0: existing BRAM backend
          vgm_file_loader + vgm_bram_read_adapter
      1: external-memory backend
          ioctl_to_extmem_loader
          vgm_extmem_cache_adapter
          DDRAM or SDRAM memory port adapter
  -> vgm_loaded_player byte-read IF
```

Initial build default must remain backend 0.

Suggested parameter names:

```systemverilog
parameter int MODE5_VGM_BACKEND     = 0;
localparam int MODE5_BACKEND_BRAM   = 0;
localparam int MODE5_BACKEND_DDRAM  = 1;
localparam int MODE5_BACKEND_SDRAM  = 2;
```

For the first implementation, only instantiate backend 0 in synthesis-visible
mode unless a new test define explicitly enables backend 1.

Current skeleton status:

- `mister_vgm_md_top` has `MODE5_VGM_BACKEND`, defaulting to backend 0.
- Backend 0 explicitly instantiates the existing `vgm_file_loader` plus
  `vgm_bram_read_adapter` path.
- Backend 1 is reserved for DDRAM and intentionally reports unavailable rather
  than instantiating any DDRAM logic.
- No external-memory backend is active by default.
- The existing BRAM path remains the hardware reference path.

## Adapter Contracts

### Existing BRAM Backend

Keep as-is:

```text
vgm_file_loader
  -> rd_addr/rd_data
  -> vgm_bram_read_adapter
  -> mem_rd_req/ready/valid/data
```

This remains the golden reference for behavior tests.

### External Loader

Add a loader that accepts the same `ioctl_*` stream but writes to external
memory:

```systemverilog
ioctl_download
ioctl_wr
ioctl_addr[26:0]
ioctl_dout[7:0]
ioctl_index[15:0]

ext_wr_req
ext_wr_addr
ext_wr_data
ext_wr_ready
load_busy
load_done
load_done_pulse
loaded_size
load_overflow
```

The external loader should preserve current mode5 load semantics:

- selected `ioctl_index` only;
- `load_done_pulse` on download falling edge;
- real load begin quiesces/resets player before writes;
- menu browsing without download must not disturb playback.

### External Byte Cache Adapter

Add an adapter that implements the existing player byte-read IF:

```systemverilog
mem_rd_req
mem_rd_addr
mem_rd_ready
mem_rd_valid
mem_rd_data
```

Internally it can read 64-bit DDRAM words or SDRAM bursts and return one byte.
The player should not know whether the byte came from BRAM, cache, DDRAM, or
SDRAM.

Minimum cache behavior:

- direct-mapped or small two-line cache;
- line size at least 16 bytes, preferably 32 or 64 bytes for DDRAM;
- hit returns through `mem_rd_valid`;
- miss stalls `mem_rd_ready` or accepts one outstanding request and returns
  `mem_rd_valid` later;
- debug counters for hit, miss, refill, and max wait cycles.

## PCM/DAC Timing Policy

Do not change PCM/DAC parser semantics. The player still issues one memory byte
read when a DAC stream command needs a PCM byte.

To keep read latency from affecting audible timing:

- prefetch sequential command bytes ahead of the parser;
- keep the active PCM bank region cacheable;
- when an `0xE0` PCM seek occurs, invalidate or retarget the PCM-side cache
  line;
- for `0x80..0x8f` DAC stream commands, require PCM byte cache hit in the
  steady state;
- expose an underrun/stall counter, but do not compensate by changing wait
  timing;
- for bring-up, allow parser stalls; for final playback, treat PCM/cache
  underruns as a backend performance bug.

The wait tick, JT12/JT89 clocks, genmix, filters, gain, and DAC command meaning
must remain untouched.

## Address And Size Widening

The current player and many debug signals are parameterized by
`VGM_LOAD_ADDR_WIDTH`. A large backend should widen mode5 only after the backend
select layer exists.

Suggested first widening target:

- `VGM_LOAD_ADDR_WIDTH=21` for 2 MiB smoke testing.
- Keep debug overlay low16 display as-is for readability.
- Add high address debug only if needed.

Do not widen fixed-ROM mode3 paths.

## Bring-Up Sequence

1. Keep backend 0 as default and run all current mode5 BRAM tests.
2. Add a simulation-only latency backend implementing the byte-read IF.
3. Run `vgm_loaded_player` tests against BRAM adapter and artificial-latency
   adapter.
4. Add `MODE5_STORAGE_BACKEND` parameter and backend select wiring, with BRAM
   selected by default.
5. Add DDRAM loader/cache adapter behind an off-by-default build/test define.
6. Widen mode5 address/size to 21 bits only after backend select tests pass.
7. Try a 1 MiB+ uncompressed VGM.

## First RTL Files For The Next Task

Touch these first:

- `rtl/mister_vgm_md_top.sv`
  - Add backend parameter and route current BRAM backend through a named backend
    select block.
- `rtl/vgm_bram_read_adapter.sv`
  - Keep unchanged behavior; use as the reference byte-read adapter contract.
- New `rtl/vgm_latency_read_adapter.sv`
  - Simulation/synthesis-safe artificial-latency adapter for TB coverage.
- New `tb/tb_mode5_backend_select.sv`
  - Proves backend 0 is identical to current BRAM path.
- New `tb/tb_vgm_latency_read_adapter.sv`
  - Proves delayed `mem_rd_valid` does not break player byte-read sequencing.

Only after that:

- New `rtl/vgm_ddram_loader.sv`
- New `rtl/vgm_ddram_cache_adapter.sv`
- `rtl/emu.sv` DDRAM signal ownership and debug wiring
- `files.qip` additions

## Regression Tests To Protect BRAM Mode5

Run before and after every backend change:

```sh
git diff --check

iverilog -g2012 -Wall -DSIMULATION -s tb_mode5_repeat_policy \
  -o /tmp/tb_mode5_repeat_policy.vvp \
  tb/tb_mode5_repeat_policy.sv \
  rtl/mister_vgm_md_top.sv \
  rtl/vgm_file_loader.sv \
  rtl/vgm_bram_read_adapter.sv \
  rtl/vgm_loaded_player.sv \
  rtl/md_sound_module.sv \
  rtl/vgm_region_player.sv \
  rtl/genesis_audio/jt12/*.v \
  rtl/genesis_audio/jt12/adpcm/*.v \
  rtl/genesis_audio/jt12/mixer/*.v \
  rtl/genesis_audio/jt89/*.v \
  rtl/genesis_audio/filters/*.v
vvp /tmp/tb_mode5_repeat_policy.vvp

iverilog -g2012 -Wall -DSIMULATION -s tb_mode5_load_while_playing_session \
  -o /tmp/tb_mode5_load_while_playing_session.vvp \
  tb/tb_mode5_load_while_playing_session.sv \
  rtl/mister_vgm_md_top.sv \
  rtl/vgm_file_loader.sv \
  rtl/vgm_bram_read_adapter.sv \
  rtl/vgm_loaded_player.sv \
  rtl/md_sound_module.sv \
  rtl/vgm_region_player.sv \
  rtl/genesis_audio/jt12/*.v \
  rtl/genesis_audio/jt12/adpcm/*.v \
  rtl/genesis_audio/jt12/mixer/*.v \
  rtl/genesis_audio/jt89/*.v \
  rtl/genesis_audio/filters/*.v
vvp /tmp/tb_mode5_load_while_playing_session.vvp
```

Also run existing focused player/loader tests when available:

- `tb/tb_vgm_file_loader.sv`
- `tb/tb_vgm_loaded_player.sv`
- `tb/tb_vgm_loaded_player_mem_if.sv`
- `tb/tb_vgm_loaded_player_boundary.sv`
- `tb/tb_vgm_loaded_player_error_halt.sv`

Hardware smoke tests:

- `behavior_short_end.vgm`, repeat off: END stops with `AM=1`, `PB=0`.
- `behavior_short_end.vgm`, repeat on: loops `pi-bo, pi-bo...`.
- `behavior_long_wait.vgm`: load-while-playing mutes old playback and starts
  new file cleanly.
- `behavior_bad_cmd_f2.vgm`: unsupported command halts cleanly with error
  debug.
- `behavior_pcm_probe_short.vgm`: DAC burst still plays.

## Non-Goals

- No JT12/JT89 changes.
- No genmix, LPF, ladder, CEN, gain, or audio-quality tuning.
- No VGM wait timing changes.
- No PCM/DAC parser semantic changes.
- No mode5 session/repeat control changes while adding the backend skeleton.
- No mode3 fixed-ROM path changes.
