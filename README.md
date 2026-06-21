# MegaVGMDrive

A standalone VGM player core for MiSTer FPGA

Japanese README: [README.ja.md](README.ja.md)

MegaVGMDrive is an experimental MiSTer FPGA core for playing VGM command streams directly on hardware. The current focus is Mega Drive / Genesis style VGM playback using a JT12/YM2612-compatible FM path together with PSG output.

The core is not a full game console implementation. It loads VGM data, replays register writes and waits, and drives the sound hardware as a standalone VGM player.

## Project Overview

- MiSTer FPGA VGM playback core
- YM2612/JT12 FM plus PSG audio
- MODE5 OSD file loading path
- DDRAM-backed VGM storage
- Plain `.vgm` playback target
- Import helper for `.zip` / `.vgz` / `.vgm` file preparation

## Current Status

The current gold state uses the MODE5 loader with a DDRAM backend.

- DDRAM backend stable
- 4 MiB+ VGM playback verified
- 1.1 MB, 3.9 MB, and 4.3 MB VGM playback verified on MiSTer hardware
- MODE5 file loading through the MiSTer OSD
- Importer available for preparing cached `.vgm` files
- `ioctl_wait` / `play_ready` load-complete gating implemented
- DDRAM address window follows the MiSTer-style `0x30000000` range
- PSG clock set to the Mega Drive rate, 3.579545 MHz

## Audio Gold

Current preferred audio configuration:

- `audio-gold-no-uprate-psgfix`
- FM/PCM bypass of the `jt12_fm_uprate` interpolation chain
- PSG preserved
- PSG level 0.75
- LPF disabled by default

This configuration keeps the PSG path active while avoiding the Genesis-oriented FM/PCM interpolation chain for the VGM player path. Current testing indicates that this path is cleaner for the verified VGM playback cases.

Validation examples:

- Hang-On
- Thunder Force IV
- Streets of Rage
- Gunstar Heroes

## VGM Import Workflow

The core loads uncompressed `.vgm` files. `.vgz` and `.zip` files should be prepared outside the FPGA before playback.

`scripts/vgm_md_import.sh` prepares playback-ready `.vgm` files for the MODE5 OSD loader. It copies plain `.vgm` files, expands `.vgz` files with `gzip`, and extracts `.vgm` / `.vgz` entries from `.zip` archives.

```sh
scripts/vgm_md_import.sh [SRC] [DST_DIR]
```

Example runs:

```sh
scripts/vgm_md_import.sh /path/Hang-On ./vgm_cache
scripts/vgm_md_import.sh "/path/Thunder Force IV.zip" ./vgm_cache
scripts/vgm_md_import.sh /path/song.vgm ./vgm_cache
```

Default MiSTer-side paths:

```text
SRC=/media/fat/games/MegaVGMDrive/inbox
DST_DIR=/media/fat/games/MegaVGMDrive/vgm_cache
```

Typical Samba workflow:

```text
\\mister\sdcard\games\MegaVGMDrive\inbox
\\mister\sdcard\games\MegaVGMDrive\vgm_cache
```

The importer writes cache output into collection subdirectories instead of placing all files directly under `vgm_cache`.

Input and output examples:

```text
Input:  /path/Hang-On/
Output: vgm_cache/Hang-On/*.vgm

Input:  /path/Thunder Force IV.zip
Output: vgm_cache/Thunder Force IV/*.vgm

Input:  /path/song.vgm
Output: vgm_cache/song/song.vgm
```

After importing, copy the resulting `vgm_cache/<collection>/...` directories to the MiSTer SD card, for example under `/media/fat/games/MegaVGMDrive/vgm_cache`. Start MegaVGMDrive on MiSTer, open the OSD, choose `Load VGM`, and select one of the imported `.vgm` files.

## MiSTer Usage

Place the MegaVGMDrive RBF in `/media/fat/_Computer/` or the MiSTer core folder used by your local setup.

Place VGM files under:

```text
/media/fat/games/MegaVGMDrive/
```

Example:

```text
/media/fat/games/MegaVGMDrive/YM2151_SMOKE.VGM
```

The current safe OSD loader entry is `F1,VGM,Load VGM;`. If your MiSTer setup filters file names case-sensitively, use uppercase `.VGM` file extensions.

### YM2151/JT51 Smoke Test

YM2151/JT51 playback is experimental. Build a YM2151 test RBF with:

```tcl
set_global_assignment -name VERILOG_MACRO "MEGAVGMDRIVE_YM2151_MODE_TEST=1"
```

Generate the synthetic non-commercial smoke VGM:

```sh
python3 tools/generate_ym2151_smoke_vgm.py
```

By default this writes:

```text
testdata/YM2151_SMOKE.VGM
```

Copy it to the MiSTer SD card as:

```text
/media/fat/games/MegaVGMDrive/YM2151_SMOKE.VGM
```

In the YM2151 test build, load it from the OSD with `Load VGM`. The expected hardware result is a looping `pi-po` smoke tone.

## Repository Layout

- `rtl/` - synthesis-visible core RTL, VGM loader/player logic, DDRAM backend, audio integration
- `sys/` - MiSTer framework support modules
- `tb/` - SystemVerilog testbenches for loader, player, timing, and mode behavior
- `tools/` - VGM generation/extraction helpers used for test and bring-up data
- `scripts/` - MiSTer-side and host-side utility scripts
- `docs/` - bring-up notes, audio notes, and backend planning notes
- `testdata/` - small VGM probes and generated test inputs

## Notes

- The main target is currently Mega Drive / Genesis style VGM data.
- YM2151/JT51 playback is experimental and is enabled only in debug builds with `MEGAVGMDRIVE_YM2151_MODE_TEST=1`.
- Native FPGA-side `.vgz` gzip decompression is not implemented.
- Large VGM playback uses the DDRAM-backed MODE5 path.
- Quartus builds are expected to be performed on Windows.
- Quartus compile and TimeQuest checks are not normally run on macOS for this project.

## Gold Checkpoint

```text
tag: audio-gold-no-uprate-psgfix
commit: 91193848fa85e8f2e7964628a5f792890dac4300
```

This checkpoint preserves the FM/PCM `jt12_fm_uprate` bypass path with PSG restored.

## Credits

This project is built for the MiSTer FPGA platform.

Third-party open-source components and references used by this project include:

- MiSTer FPGA project
- Genesis_MiSTer project
- JT12 FM core by Jose Tejada Gomez (Jotego)
- JT51 FM core by Jose Tejada Gomez (Jotego)

JT12 and JT51 are used under their original open-source licenses. Original copyright notices and license headers for third-party code are preserved.

This repository contains original work together with modifications and integrations based on the above projects.

Links:
- https://github.com/MiSTer-devel/Main_MiSTer
- https://github.com/MiSTer-devel/Genesis_MiSTer
- https://github.com/jotego/jt12
- https://github.com/jotego/jt51
