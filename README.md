# MegaVGMDrive

A standalone, hardware VGM player core for MiSTer FPGA.

Japanese README: [README.ja.md](README.ja.md)

MegaVGMDrive loads VGM command streams into DDRAM and plays them directly through FPGA sound cores. It can play VGM music from Sega Mega Drive / Genesis games and supported Sega arcade systems. It is a music player, not a complete game-console implementation. The production build enables the supported Mega Drive and arcade sound devices together, so mixed-device VGM files can use every implemented path in one build.

> **Development note:** Almost all of this project was implemented and debugged by OpenAI Codex and GPT. I only listened to the sound, ran the Quartus builds, and sent the debug values back to Codex.

## MegaVGMPlayer v1.0

**MegaVGMDrive** is the repository and MiSTer FPGA core project. **MegaVGMPlayer** is its standalone on-screen VGM player. Version **v1.0** is the first stable production release.

| Item | Value |
| --- | --- |
| Tag | `v1.0` |
| Release RTL checkpoint | `85d1cac1aa5781e5169762f3858099e65b2c8767` |
| Hardware-tested RBF | `MegaVGMDrive_MiSTer_v1.0.rbf` |
| Build environment | Quartus on Windows |

This release combines the hardware-tested audio paths, MiSTer Template-compliant native video, and prepared-file title display. Ordinary unmodified `.vgm` files remain playable; the title lines appear only when a valid MegaVGMDrive metadata trailer is present.

## Reference FPGA Build Status

The hardware-validated production build from 2026-07-23 had the following Quartus results:

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

The subsequent v1.0 production build removes audio-only diagnostic accumulators and kept counters from normal synthesis, reducing measured Quartus ALM use by approximately one percentage point. The v1.0 asset is the later Windows-built, hardware-tested RBF; macOS was not used to run Quartus.

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
- MiSTer Template-compliant native video for HDMI, analog, and Direct Video paths
- Parent-directory and basename display from validated `MVGMTTL` metadata
- Host/MiSTer import helper for raw `.vgm`, `.vgz`, ZIP-contained VGM, and ZIP-contained VGZ sources

## Supported Sound Chips and JT Cores

| Sound chip | Production implementation | Status |
| --- | --- | --- |
| YM2612 | Jotego JT12 FM and DAC path | Enabled |
| SN76489 / PSG | Jotego JT89 | Enabled |
| YM2151 | Jotego JT51 | Enabled |
| YM2203 | Jotego JT12 OPN FM + JT49 SSG | Enabled |
| SegaPCM | Jotego JTOUTRUN / `jtoutrun_pcm`, using the normal DDR path | Enabled |

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

1. Download the hardware-tested RBF from the [v1.0 release](https://github.com/dai-VGM/MegaVGMDrive/releases/tag/v1.0).
2. Copy the RBF to the MiSTer core location used by your setup.
3. Copy one or more uncompressed `.vgm` files to storage accessible from MiSTer's file picker.
4. Start MegaVGMDrive, open the MegaVGMPlayer OSD, choose **Load VGM**, and select a file.

An ordinary unmodified `.vgm` remains directly playable. It does not need the helper unless you want the on-screen directory and basename display.

## Installing `vgm_md_import.sh`

The script and VGM data use separate directories. Copy the release helper to MiSTer's standard Scripts directory:

```sh
cp vgm_md_import.sh /media/fat/Scripts/vgm_md_import.sh
chmod +x /media/fat/Scripts/vgm_md_import.sh
```

The complete default layout is:

```text
/media/fat/
├── Scripts/
│   └── vgm_md_import.sh
└── MegaVGMDrive/
    ├── inbox/
    └── vgm_cache/
```

The helper keeps these data-directory defaults:

```sh
ROOT=/media/fat/MegaVGMDrive
SRC="$ROOT/inbox"
DST_DIR="$ROOT/vgm_cache"
```

Place VGM files or album directories in `/media/fat/MegaVGMDrive/inbox/`. Run `vgm_md_import` from MiSTer's Scripts menu, or execute it directly:

```sh
/media/fat/Scripts/vgm_md_import.sh
```

Prepared files are written below `/media/fat/MegaVGMDrive/vgm_cache/`. Load them from MegaVGMPlayer's OSD.

## Preparing VGM Files

The FPGA loader itself does not decompress `.vgz` or `.zip`. The helper accepts:

- an already-uncompressed raw `.vgm`;
- a `.vgz`;
- a ZIP containing VGM files;
- a ZIP containing VGZ files.

A raw `.vgm` can be placed in `inbox` directly; do not recompress it as VGZ or ZIP. For example:

```text
/media/fat/MegaVGMDrive/inbox/
└── Super Hang-On/
    └── 03 - Sprinter.vgm
```

The helper creates:

```text
/media/fat/MegaVGMDrive/vgm_cache/
└── Super Hang-On/
    └── 03 - Sprinter.vgm
```

MegaVGMPlayer then displays:

```text
Super Hang-On
03 - Sprinter
```

The immediate parent directory becomes the upper line and the VGM basename without its final extension becomes the lower line. Spaces and underscores are preserved. The source under `inbox` is not modified; the helper creates a prepared copy under `vgm_cache` and creates destination directories as required. Repeated conversion does not append duplicate metadata. A valid existing trailer is replaced safely with current metadata.

## Track Title Display and `MVGMTTL`

Prepared VGM files end with a MegaVGMDrive-specific 128-byte `MVGMTTL` trailer. The trailer holds a directory field of up to 32 characters and a basename field of up to 48 characters.

The helper supports VGM bodies larger than 4 MiB. Under the current MegaVGMDrive production 23-bit byte-address contract, the maximum prepared physical file is exactly 8 MiB (`8,388,608` bytes), including the 128-byte `MVGMTTL` trailer. The maximum original VGM body accepted by the helper is therefore `8,388,480` bytes. Ordinary unmodified VGM playback compatibility is unchanged.

The helper preserves printable ASCII `0x20`–`0x7E`, converts each valid non-ASCII UTF-8 code point to one `?`, converts malformed UTF-8 bytes safely to `?`, and truncates the converted directory and basename to their fixed field limits. The FPGA font supports printable ASCII only; arbitrary Unicode text is not displayed directly.

During an `ioctl_index=1` VGM download, the FPGA receiver passively observes the transfer without stalling playback, DDR, or the parser. It validates the final 128 bytes, including the `MVGMTTL` magic, version, flags, trailer and original sizes, string lengths, and reserved fields. Metadata is published atomically only after complete validation. A new load clears the previous title. Missing, malformed, or interrupted metadata displays no directory or basename, while the ordinary VGM data remains playable.

The two metadata lines are drawn on the centered 320×240 navy player surface (`RGB 24'h000818`). The fixed `MegaVGMPlayer` heading, blue borders, and outlines are not drawn.

## 15kHz / Native Video

MegaVGMPlayer v1.0 uses MiSTer Template-compliant native timing. Its raw video runs from the existing 20 MHz system clock with a 10 MHz pixel-enable cadence, producing approximately 15.674 kHz horizontal and 59.824 Hz vertical timing.

The same native RGB picture feeds MiSTer's HDMI, Analog RGB, YPbPr, CRT, and Direct Video paths. The 320×240 navy player surface is centered in the Template active area and contains only the directory and basename lines. External testing has confirmed operation on a 15kHz CRT, but this is not a guarantee of compatibility with every CRT or display.

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
- Prepared `MVGMTTL` directory and basename display
- HDMI display and externally tested 15kHz CRT output

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

- **After Burner II — Maximum Power:** noise may occur under specific conditions, including the first playback after starting a freshly loaded RBF.
- **Quartet:** a known playback compatibility issue remains.

## Other Limitations

- MegaVGMDrive is a standalone VGM player, not a full Mega Drive, System 16, or System 18 implementation.
- Native FPGA-side `.vgz`/`.zip` decompression is not implemented.
- Files using commands or devices outside the implemented subset may be skipped or may not play as intended.
- Mega CD / RF5C164, 32X PWM, and YM2610B are not supported.
- `.mvgmpack`, next/previous track selection, autoplay, pause, and progress display are not implemented in v1.0.

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
- [JT12](https://github.com/jotego/jt12), JT89, [JT49](https://github.com/jotego/jt49), [JT51](https://github.com/jotego/jt51), and related JT cores by José Tejada Gómez (Jotego)
- SegaPCM through Jotego's JTOUTRUN / `jtoutrun_pcm` implementation

See [Genesis audio provenance](rtl/genesis_audio/README.md) for the pinned source revisions and local integration notes. Original copyright notices and source headers are preserved.

## License

Third-party components remain under their upstream licenses. See the included [JT51 license](third_party/jt51/LICENSE), [JT cores license](third_party/jtcores/LICENSE), component READMEs, and individual source headers.

This repository currently has no separate top-level `LICENSE` file. Do not infer a single license for every file; review the applicable component license and source notice before redistribution.
