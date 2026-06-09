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
- `testdata/` - small tracked VGM probes for simulation and MiSTer checks

This is not a NanoDrive source tree.

## Mode5 PCM Probe

`testdata/mode5_pcm_probe.vgm` is a tiny uncompressed YM2612 DAC-stream VGM
for real MiSTer `REGION_MODE=5` BRAM-loaded playback checks. It contains a
valid VGM header, YM2612 DAC enable (`52 2B 80`), one type-0 PCM data block,
`E0` seek-to-zero, many `0x80..0x8f` DAC stream commands, and `66` end.

`testdata/test_pcm_excerpt.vgm` is a short real-PCM excerpt generated from the
larger `/Users/daizo/Downloads/test.vgm` source with:

```sh
python3 tools/extract_mode5_pcm_excerpt_vgm.py
```

The extractor prints the output size, PCM bank size, first source/output `E0`
positions, DAC stream count, total wait samples, and whether the result is below
the current 256 KiB limit.

`testdata/test_stable_demo.vgm` is the preferred small mode5 hardware demo VGM.
It is generated from `/Users/daizo/Downloads/test.vgm` starting from the song
head: the original type-0 PCM data block is kept, then the following FM, PSG,
wait, `E0`, and `0x80..0x8f` DAC stream commands are copied in their original
order and timing. It avoids zero-time bulk setup writes and ends with `66`.

```sh
python3 tools/extract_mode5_stable_demo_vgm.py
```

The default output is about 20 seconds and remains well below the current
256 KiB mode5 BRAM limit.

Current mode5 VGM RAM is BRAM-backed with `ADDR_WIDTH=18`, so the loaded file
capacity is 256 KiB. Full 1 MiB+ PCM VGM files exceed this path and are expected
to hit loader overflow/error until a later SDRAM/DDR/streaming loader exists.
