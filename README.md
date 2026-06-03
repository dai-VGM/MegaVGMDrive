# MiSTer VGM Workbench

A personal VGM / YM2612 / JT12 experiment workspace for MiSTer FPGA audio exploration.

This project is focused on testing how VGM command streams can drive a JT12/YM2612-compatible FPGA audio core.

## Purpose

- Explore VGM playback behavior
- Test YM2612 register writes
- Investigate JT12 timing and initialization behavior
- Build small SystemVerilog testbenches
- Keep notes, tools, and experiments in one clean workspace

## Layout

- `docs/` - notes and experiment logs
- `rtl/` - HDL modules and audio/control experiments
- `tb/` - testbenches
- `tools/` - helper scripts for VGM parsing/conversion

This is not a NanoDrive source tree.
