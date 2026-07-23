# MegaVGMDrive

A standalone, hardware VGM player core for MiSTer FPGA.

Japanese README: [README.ja.md](README.ja.md)

MegaVGMDrive loads VGM command streams into DDRAM and plays them directly through FPGA sound cores. It can play VGM music from Sega Mega Drive / Genesis games and supported Sega arcade systems. It is a music player, not a complete game-console implementation. The production build enables the supported Mega Drive and arcade sound devices together, so mixed-device VGM files can use every implemented path in one build.

> **Development note:** Almost all of this project was implemented and debugged by OpenAI Codex and GPT. I only listened to the sound, ran the Quartus builds, and sent the debug values back to Codex.

## Current Release

The current hardware-validated release is [MegaVGMDrive – YM2203 and SegaPCM Release](https://github.com/dai-VGM/MegaVGMDrive/releases/tag/audio-gold-ym2203-segapcm).

| Item | Value |
| --- | --- |
| Tag | `audio-gold-ym2203-segapcm` |
| Source checkpoint | `23763eab487d3eeea7430047d4785c45839c1b56` |
| Hardware-tested RBF | `MegaVGMdrive_MiSTer_20260723.rbf` |
| Build environment | Quartus on Windows |

This release adds production YM2203/JT49 and SegaPCM playback, restores concurrent YM2612/PSG operation, and normalizes the Mega Drive and arcade audio families independently.

## FPGA Build Status

The hardware-validated production build from 2026-07-23 has the following Quartus results:

| Item | Value |
| --- | --- |
| Flow Status | Successful |
| Build time | Thu Jul 23 11:04:36 2026 |
| Quartus Prime Version | 17.0.0 Build 595 04/25/2017 SJ Lite Edition |
| Revision | `VGM_MD_MiSTer` |
| Top-level entity | `sys_top` |
| Family | Cyclone V |
| Device | `5CSEBA6U23I7` |
| Timing Models | Final |
| Logic utilization | 32,614 / 41,910 ALMs (78%) |
| Total registers | 54,435 |
| Total pins | 145 / 314 (46%) |
| Total block memory bits | 372,593 / 5,662,720 (7%) |
| Total DSP Blocks | 37 / 112 (33%) |
| Total PLLs | 3 / 6 (50%) |

Logic utilization is currently the tightest resource; block memory and DSP capacity still have headroom.

## Features

- MODE5 OSD loading of uncompressed `.vgm` files
- DDRAM-backed VGM storage
- Concurrent production support for all sound devices listed below
- VGM header clock tracking for YM2203 and SegaPCM
- Fractional clock-enable generation for header-selected chip rates
- Busy-aware YM2203 register transport
- SegaPCM playback through the normal DDR data path
- Separate Mega Drive-family and arcade-family audio normalization
- Signed widened final mixing with 16-bit saturation
- Host/MiSTer import helper for `.vgm`, `.vgz`, and `.zip` sources

## Supported Sound Devices

| Device | Implementation | Production status |
| --- | --- | --- |
| YM2612 | JT12-based FM and DAC path | Enabled |
| SN76489 PSG | JT89-based PSG path | Enabled |
| YM2151 | JT51 | Enabled |
| YM2203 FM | Compatible three-channel JT12/JT03 configuration | Enabled |
| YM2203 SSG | JT49 | Enabled |
| SegaPCM | JT-based core using the normal DDR path | Enabled |

Production releases enable these devices concurrently. Development or chip bring-up builds may intentionally disable completed devices, but lab-only audio stubs are not used in release builds.

## Implemented VGM Commands

The production parser includes the following device writes:

| Command | Function |
| --- | --- |
| `0x50 dd` | SN76489 PSG write |
| `0x52 aa dd` | YM2612 port 0 write |
| `0x53 aa dd` | YM2612 port 1 write |
| `0x54 aa dd` | YM2151 write |
| `0x55 aa dd` | YM2203 write |
| `0xC0 ll hh dd` | SegaPCM write to a 16-bit address |

The player also implements the wait, end/loop, data-block, PCM-seek, and YM2612 DAC-stream commands used by the supported playback paths, including `0x61`–`0x63`, `0x66`, `0x67`, `0x70`–`0x7F`, `0x80`–`0x8F`, and `0xE0`.

YM2203 uses the VGM header clock at offsets `0x44`–`0x47`. SegaPCM uses the clock at `0x38`–`0x3B` and reads its interface field at `0x3C`–`0x3F`. Fractional accumulators derive the required enables from these header values; the test or top level does not add the YM2203 FM `/6` or SSG `/4` divisions because JT12/JT49 handle them internally.

## Installation and Use

1. Download the hardware-tested RBF from the [current release](https://github.com/dai-VGM/MegaVGMDrive/releases/tag/audio-gold-ym2203-segapcm).
2. Copy the RBF to the MiSTer core location used by your setup.
3. Copy one or more uncompressed `.vgm` files to storage accessible from MiSTer's file picker.
4. Start MegaVGMDrive, open the OSD, choose **Load VGM**, and select a file.

The FPGA loader does not decompress `.vgz` or `.zip` files. The optional [VGM import helper](scripts/vgm_md_import.sh) copies `.vgm` files and expands `.vgz` or supported archive entries before playback:

```sh
scripts/vgm_md_import.sh [SRC] [DST_DIR]
```

Its MiSTer-side defaults are:

```text
SRC=/media/fat/VGM_MD/inbox
DST_DIR=/media/fat/VGM_MD/vgm_cache
```

The destination can be changed to match a local SD-card layout.

## Release OSD

The normal release build presents only:

```text
Load VGM
Audio Gain:     Normal / Boost
SegaPCM Audio:  Normal / PCM Only / FM Only
Reset
```

- **Audio Gain** affects the Mega Drive family only: YM2612 plus SN76489 PSG. `Normal` preserves the historical level and `Boost` applies the established 2× MD-family gain.
- **SegaPCM Audio** selects the arcade-family contributions: `Normal` mixes FM and PCM, `PCM Only` mutes the FM lanes, and `FM Only` mutes SegaPCM.
- Release builds keep the hidden SegaPCM feed at **Hold** and polarity at **Normal** (`sample_byte - 128`).
- Bring-up controls and the debug overlay remain available only in development builds.

## Audio Architecture

The public production output is assembled as two independently normalized families:

```text
YM2612 + SN76489 PSG
  -> historical MD postmix/gain profile
  -> signed MD lane

YM2151/JT51 + YM2203/JT49 + SegaPCM
  -> arcade mixer and saturation
  -> existing arcade public level (arithmetic >>> 2)
  -> signed arcade lane

MD lane + arcade lane
  -> widened signed addition
  -> 16-bit saturation
  -> public stereo output
```

The historical Mega Drive audio profile preserves its established PSG balance, no-uprate postmix path, and MD-only Audio Gain behavior. The arcade family retains its previously validated public level. YM2203 FM is scaled 4× inside the YM2203 branch before its SSG mix, preserving the validated FM/SSG balance without changing the other devices.

## Hardware Validation

The release RBF was built on Windows and tested on MiSTer-compatible hardware. Confirmed release checks include:

- YM2612 FM, SN76489 PSG, and YM2612 DAC playback
- `Audio Gain` in both `Normal` and `Boost`
- YM2151/JT51 playback
- YM2203 FM and JT49 SSG playback
- SegaPCM playback through normal DDR
- `Normal`, `FM Only`, and `PCM Only` selector modes
- Concurrent Mega Drive-family and arcade-family output

Hardware-tested playback examples include:

- After Burner
- Out Run
- Galaxy Force II
- Thunder Blade
- Power Drift
- Space Harrier
- Multiple Sega Mega Drive / Genesis titles

These are hardware-tested examples, not a claim of complete title coverage or compatibility with every VGM rip.

Icarus simulation and Verilator lint/regression work were used throughout the release bring-up. No Quartus build was performed on macOS; the attached release asset is the Windows-built, hardware-tested binary.

## Known Issues

- The first playback of “Maximum Power” immediately after loading a fresh RBF may contain a buzzing artifact.
- Some early YM2151 VGM files, including Quartet, may produce load-dependent sound differences; investigation is ongoing.
- Mega CD / RF5C164 is not supported.
- 32X PWM is not supported.

## Other Limitations

- MegaVGMDrive is a standalone VGM player, not a full Mega Drive, System 16, or System 18 implementation.
- Native FPGA-side `.vgz`/`.zip` decompression is not implemented.
- Files using commands or devices outside the implemented subset may be skipped or may not play as intended.

## Build Workflow

The macOS checkout is the canonical source tree and QSF. The release workflow is:

1. Make source and project-file changes on macOS.
2. Copy the project, including the canonical [`VGM_MD_MiSTer.qsf`](VGM_MD_MiSTer.qsf), to the Windows build environment.
3. Compile the RBF with Quartus on Windows.
4. Copy the Windows-built RBF to MiSTer-compatible hardware and validate it there.
5. Publish only a binary that matches the hardware-tested build.

Do not maintain a separate edited QSF on Windows, and do not use a macOS Quartus build as the release binary.

## Repository Layout

- `rtl/` — synthesis-visible RTL, VGM parser/player, DDR backend, and audio integration
- `sys/` — MiSTer framework support
- `tb/` — SystemVerilog testbenches
- `scripts/` — regression and import helpers
- `tools/` — VGM analysis and generated-test utilities
- `testdata/` — synthetic and extracted regression inputs
- `docs/` — bring-up and implementation notes

## Credits

MegaVGMDrive is built for the [MiSTer FPGA platform](https://github.com/MiSTer-devel/Main_MiSTer) and incorporates or derives integration work from these projects:

- [Genesis_MiSTer](https://github.com/MiSTer-devel/Genesis_MiSTer)
- [JT12](https://github.com/jotego/jt12), [JT49](https://github.com/jotego/jt49), [JT51](https://github.com/jotego/jt51), and related JT cores by José Tejada Gómez (Jotego)
- JT SegaPCM work derived from the corresponding Jotego arcade-core implementation

See [Genesis audio provenance](rtl/genesis_audio/README.md) for the pinned source revisions and local integration notes. Original copyright notices and source headers are preserved.

## License

Third-party components remain under their upstream licenses. See the included [JT51 license](third_party/jt51/LICENSE), [JT cores license](third_party/jtcores/LICENSE), component READMEs, and individual source headers.

This repository currently has no separate top-level `LICENSE` file. Do not infer a single license for every file; review the applicable component license and source notice before redistribution.
