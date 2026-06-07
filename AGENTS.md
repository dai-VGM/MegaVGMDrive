# AGENTS.md

## Project

This repository is the MiSTer VGM Player Core project.

The current working directory must be:

`~/Projects/mister-vgm-work`

Do not use or modify the old workspace:

`~/Downloads/NanoDrive6-2.3.0`

That old directory is historical reference only and must not be touched.

## Current branch

Primary working branch:

`mister-core-skeleton`

Create feature branches from this branch unless the user explicitly says otherwise.

## Current milestone

The project has reached the following confirmed hardware milestones on real MiSTer hardware:

- InputTest-based MiSTer shell works.
- OSD/menu returns correctly.
- JT12/YM2612 FM sound works on hardware.
- JT89/PSG sound works on hardware.
- `REGION_MODE=0`: bring-up tone pass.
- `REGION_MODE=1`: PSG/FM smoke pass.
- `REGION_MODE=2`: real VGM-derived FM engine sound pass, stop sound pass.
- `REGION_MODE=3`: real VGM-derived Super Hang-On intro-like phrase plays on MiSTer hardware and repeats with orange/green visual confirmation.
- `REGION_MODE=4`: timing calibration pass. VGM wait timing is separated from `audio_sample_valid` and uses a dedicated 44.1 kHz tick. Effective `clk_sys` is assumed to be corrected to 12.5 MHz.

## Sacred paths

Do not break these known-good paths:

- Existing MiSTer shell / OSD path.
- Existing JT12/YM2612 bus path.
- Existing JT89/PSG bus path.
- `REGION_MODE=0..4`.

Treat `REGION_MODE=3` as the known-good fixed-ROM real-VGM phrase path.

Treat `REGION_MODE=4` as the known-good timing calibration path.

New risky work must be added as a new mode first, not by rewriting working modes.

## Current next target

The next target is to move from fixed-ROM VGM command playback to OSD-loaded playback.

Implement this as:

`REGION_MODE=5`: OSD-loaded mode3-equivalent VGM command region.

Initial goal:

- Add MiSTer OSD file loading via `hps_io` / `ioctl_*`.
- Load a small `.bin` or `.vgm`-like file into internal RAM.
- Replay the same command sequence that currently works in `REGION_MODE=3`.
- Do not implement full VGM header parsing yet unless explicitly requested.
- Do not implement VGZ/gzip.
- Do not implement SDRAM/large-file streaming yet.
- Do not tune original sound accuracy yet.

## Implementation preferences

Prefer additive changes.

Do not refactor working audio paths unless necessary.

If a fixed-ROM player must be generalized, preserve the existing fixed-ROM behavior and add a separate dynamic/RAM-backed path if safer.

Useful module names:

- `rtl/vgm_load_ram.sv`
- `rtl/vgm_region_player_dynamic.sv`
- `tools/export_mode3_region_bin.py`
- `tb/tb_vgm_load_ram.sv`

Expected loader behavior:

- Use MiSTer `ioctl_download`, `ioctl_wr`, `ioctl_addr`, `ioctl_dout`, and `ioctl_index`.
- Use load index `1` for the first VGM loader.
- Write bytes into internal RAM only when the loader index matches.
- Expose `load_active`, `load_done_pulse`, `loaded_size`, and `load_overflow`.
- Generate `load_done_pulse` when `ioctl_download` falls from 1 to 0.

## Testing expectations

Before reporting completion, run whatever existing tests are available.

At minimum, if relevant files exist, try:

```sh
git status
find . -maxdepth 3 -type f | sort
```

For Verilog/SystemVerilog simulation, prefer existing project commands and testbenches.

If adding `tb/tb_vgm_load_ram.sv`, test:

- bytes written through fake `ioctl_wr` can be read back;
- `load_done_pulse` occurs after download ends;
- overflow is detected.

If Quartus build files are present and the task affects synthesis-visible RTL, attempt a build or clearly state why it was not run.

## Reporting expectations

When done, report:

1. Changed files.
2. What was added.
3. What tests were run.
4. Whether `REGION_MODE=0..4` were preserved.
5. How to test `REGION_MODE=5` on real MiSTer hardware.
6. Any remaining risks or TODOs.

## Style

Be conservative.

Prefer small, reviewable patches.

Keep comments practical and hardware-debug oriented.

Do not remove working debug colors or known-good bring-up paths.

Do not silently change clock assumptions, wait timing, or audio sample timing.
