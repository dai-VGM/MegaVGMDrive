# AGENTS.md

## Project

This repository is the MegaVGMDrive MiSTer core project.

The authoritative working directory is:

`~/Projects/mister-vgm-golden`

Do not modify:

- `~/Projects/mister-vgm-work` — historical/reference workspace only
- `~/Downloads/NanoDrive6-2.3.0` — historical reference only

## Repository workflow

The Mac repository and QSF are authoritative.

- Edit RTL, scripts, tests, and QSF on the Mac side.
- Do not edit QSF on Windows.
- Copy the complete Mac working tree/QSF to Windows when a Quartus build is required.
- Quartus compilation and hardware fitting are performed on Windows only.
- Do not search for, install, or run Quartus on macOS.

Current stable branch:

`main`

Current stable release baseline:

- MegaVGMPlayer v1.0.1
- HEAD: `5ecce555edb80bdcb010a322ee46ba8837a6ee27`

Create feature branches from `main` unless explicitly instructed otherwise.

Do not push, tag, merge to main, or modify a GitHub Release unless explicitly requested.

## Project naming

- Repository / FPGA core: `MegaVGMDrive`
- On-screen standalone player: `MegaVGMPlayer`

Preserve exact capitalization.

## Stable production functionality

The following production paths are stable and must be treated as regression-sensitive:

- YM2612 — Jotego JT12
- SN76489 / PSG — Jotego JT89
- YM2151 — Jotego JT51
- YM2203 — JT12 OPN FM + JT49 SSG
- SegaPCM — Jotego JTOUTRUN / `jtoutrun_pcm`
- OSD-loaded VGM playback
- 23-bit DDR VGM backend
- VGM files up to exactly 8 MiB physical size
- Ordinary raw `.vgm` compatibility
- Optional 128-byte `MVGMTTL` metadata trailer
- Parent-directory and basename display
- MiSTer Template-compliant 15 kHz native video
- HDMI, Analog RGB, YPbPr, CRT, and Direct Video output

Mega CD / RF5C164, 32X PWM, and YM2610/YM2610B are not currently implemented.

## Stable contracts

Do not casually alter:

- VGM parser PC, wait, loop, and `0x66` behavior
- DDR loader/backend and 23-bit address contract
- Audio sample-valid cadence
- JT12, JT89, JT51, JT49 internal RTL
- SegaPCM normal-DDR adapter, prefetch, cache, hold, ownership, or reset contract
- SegaPCM `.reset(reset)` connection
- Production audio gain, routing, saturation, and selector behavior
- Native video timing
- `MVGMTTL` receiver validation and atomic publication
- Ordinary unmodified VGM playback

VGM header loops are intentionally followed indefinitely by the current FPGA player. Finite loop count, fade, playlists, and next-track policy belong to a future host/Web player layer.

## Production and diagnostic separation

Diagnostic and laboratory RTL must be compile-time separated from production features.

Use dedicated lab/diagnostic macros. Do not hide functional production logic under macros whose names imply debug-only behavior.

When a new sound device is brought up, existing devices may be compile-time disabled in a dedicated lab profile to reduce build time and simplify debugging.

Before production reintegration, explicitly verify:

- all previously completed devices re-enabled
- parser opcode regression
- raw audio regression
- final routing regression
- sample-valid regression
- ordinary VGM compatibility
- `MVGMTTL` prepared VGM compatibility
- reload and loop behavior
- X/Z, clipping, drops, underflow, and stale responses

## Current next target

The next development target is the YM2610 family.

Recommended sequence:

1. Restore a standalone standard JT10 environment using only ADPCM source files matching JT12 commit:
   `6d51e0b6f64728c73408079b2f5ffe911bfd88a9`
2. Do not update the complete JT12 tree to current upstream.
3. Bring up standard YM2610:
   - FM 4ch
   - JT49 SSG
   - ADPCM-A
   - ADPCM-B / Delta-T
4. Add YM2610B support:
   - retain all 6 FM channels
   - add ADPCM-A/B as separate mixer lanes
   - implement a dedicated B-compatible accumulator/mixer
5. Use a dedicated lab build first.
6. The likely production design is a compile-time sound profile where SegaPCM and YM2610B are mutually exclusive.

Initial real-content goals:

- standard YM2610: The Ninja Warriors
- YM2610B: Night Striker

## YM2610 Phase 0 boundary

Phase 0 must remain standalone.

Allowed:

- Add pinned JT10/ADPCM dependencies matching the existing JT12 generation
- Add standalone testbenches and test-only manifests/runners
- Compile, elaborate, and inspect reset/interface behavior

Not allowed during Phase 0:

- production parser changes
- `0x58` / `0x59` integration
- data-block `0x82` / `0x83` integration
- DDR ROM mapping
- production mixer/top integration
- QSF or production `files.qip` changes
- YM2610B accumulator implementation
- Quartus build

## Testing

Before reporting completion:

- record branch, HEAD, working-tree state, and untracked files
- run `git diff --check`
- run relevant Icarus simulations
- run relevant Verilator lint/elaboration
- verify undefined and duplicate modules
- preserve vendor source provenance and licenses
- compare regression hashes when production-visible logic changes
- never claim hardware or Quartus success without an actual Windows build/test

Do not modify the pre-existing untracked file:

`tb/tb_jt49_audio_compare.sv`

Record its SHA-256, size, mtime, and inode before and after work when requested.

## Reporting

Report:

1. Branch, base HEAD, and final HEAD
2. Changed files
3. Source provenance and pinned commits
4. Implemented behavior
5. Tests and exact results
6. Warning/error counts
7. Production paths confirmed unchanged
8. Working-tree state
9. Untracked-file preservation
10. Remaining risks and the single next recommended step