# Vendored JTCORES subset

This directory contains a minimal subset of Jotego JTCORES/JTFRAME used for the
MegaVGMDrive YM2151/SegaPCM experimental path.

Source project: https://github.com/jotego/jtcores
Author/Credits: Jose Tejada Gomez, Twitter/GitHub @topapate
License: GPL-3.0-or-later; see `LICENSE` and the headers in each source file.

Vendored files:

- `cores/outrun/hdl/jtoutrun_pcm.v`
  - Upstream path: `cores/outrun/hdl/jtoutrun_pcm.v`
  - Purpose: Sega 315-5218 / OutRun SegaPCM sound core.
- `modules/jtframe/hdl/ram/jtframe_dual_ram.v`
  - Upstream path: `modules/jtframe/hdl/ram/jtframe_dual_ram.v`
  - Purpose: RAM helper required by `jtoutrun_pcm.v`.

Only this subset is used for the temporary LastWave preload-ROM experiment.
The VGM `0x67/0x66/type 0x80` streaming copy path remains disabled/skipped.
