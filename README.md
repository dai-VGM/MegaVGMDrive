# MegaVGMDrive / MegaVGMPlayer

MegaVGMPlayer is a standalone FPGA VGM player for MiSTer. **MegaVGMDrive** is the repository and FPGA core project; **MegaVGMPlayer** is the on-screen player.

[日本語](README.ja.md) · [YM2151 / SegaPCM v1.0.2 stable release](https://github.com/dai-VGM/MegaVGMDrive/releases/tag/v1.0.2) · [YM2610B Beta release](https://github.com/dai-VGM/MegaVGMDrive/releases/tag/YM2610B-beta1)

> **Development note:** Almost all of this project was implemented and debugged by OpenAI Codex and GPT. I only listened to the sound, ran the Quartus builds, and sent the debug values back to Codex.

## Choose an edition

MegaVGMPlayer is distributed as two independent RBF product lines. It is not an all-in-one build.

| Edition | Status | Main sound paths | Release asset |
| --- | --- | --- | --- |
| YM2151 / SegaPCM | **Stable v1.0.2** | YM2612, SN76489, YM2151, YM2203, SSG, SegaPCM | `MegaVGMDrive_MiSTer_v1.0.2.rbf` |
| YM2610B | **Beta** | YM2610, YM2610B, FM, ADPCM-A, ADPCM-B | `MegaVGMPlayer_YM2610B.rbf` |

Cyclone V resource limits make a practical universal configuration undesirable. Choose the RBF for the systems and music you want to play. Neither edition supersedes the other.

## What makes it different?

VGM register streams are sent directly to synthesizable FPGA sound-core HDL:

```text
VGM data
  -> FPGA VGM parser
  -> FPGA sound-core HDL
  -> FPGA mixer
  -> MiSTer audio output
```

Sound generation and mixing stay inside the FPGA rather than going through a PC software synthesizer or an operating-system audio stack. This provides a short, direct way to listen to FPGA implementations of the supported sound chips in a standalone MiSTer player.

This does not mean that FPGA implementations are automatically more accurate than original silicon or software emulators, nor that they necessarily sound better. The JT cores are hardware implementations, not claims of transistor-level identity with the original chips.

## YM2151 / SegaPCM edition — stable v1.0.2

Download: [MegaVGMPlayer v1.0.2](https://github.com/dai-VGM/MegaVGMDrive/releases/tag/v1.0.2)

This edition enables the following production paths together:

- YM2612 FM and DAC through JT12
- SN76489 PSG through JT89
- YM2151 through JT51
- YM2203 FM with JT49 SSG
- SegaPCM through JTOUTRUN / `jtoutrun_pcm`

The parser handles the corresponding VGM writes (`0x50`, `0x52`, `0x53`, `0x54`, `0x55`, and `0xC0`) plus the waits, loops, data blocks, PCM seek, and YM2612 DAC-stream commands used by these playback paths. YM2203 and SegaPCM clocks are read from the VGM header and converted to fractional chip enables.

### What v1.0.2 fixed

**JT51 / YM2151**

- Fixed the After Burner II “Maximum Power” startup buzz.
- Corrected JT51 reset-time CEN handling and eliminated previous-track JT51 state leakage.
- Fixed Quartet startup, pitch, and state-dependent behavior.
- Fixed Fantasy Zone startup flam/transients caused by large timestamp-zero YM2151 initialization bursts.

**SegaPCM**

- Fixed a speculative-read/raw-skid deadlock at repeat boundaries.
- Fixed the reproducible PCM dropout in `02 Start BGM`.
- Improved PCM playback in affected Strike Fighter tracks. This is not a claim that every Strike Fighter issue had the same proven cause.

**VGM import helper**

- Fixed ZIP-contained VGM/VGZ names containing literal wildcard characters such as `[ ]`, `*`, and `?`.
- Restored missing tracks in packs including Galaxy Force II, Fantasy Zone II DX, and The Ninja Warriors.

See the [v1.0.2 release](https://github.com/dai-VGM/MegaVGMDrive/releases/tag/v1.0.2) for the complete release notes and verified downloads.

### Stable-edition OSD

```text
Load VGM
Audio Gain:     Normal / Boost
SegaPCM Audio:  Normal / PCM Only / FM Only
Reset
```

`Audio Gain` applies to the YM2612/SN76489 Mega Drive family. `SegaPCM Audio` selects the arcade mix or isolates its FM or PCM contribution.

## YM2610B edition — Beta

Download: [MegaVGMPlayer YM2610B Beta 1](https://github.com/dai-VGM/MegaVGMDrive/releases/tag/YM2610B-beta1)

This separate RBF provides:

- YM2610 and YM2610B playback
- YM2610B six-channel FM
- 24-bit ADPCM-A addressing
- 24-bit ADPCM-B addressing
- cache and serialized mapping support for large or sparse PCM ROM layouts
- ongoing Neo Geo VGM compatibility work

Representative real-hardware testing includes Darius II, Gun Frontier, The Ninja Warriors, Night Striker, and Metal Slug material. It remains a Beta: additional game- or VGM-specific compatibility issues may still exist.

## Getting started

1. Download the appropriate RBF from the stable or Beta release above.
2. Copy it to the MiSTer core location used by your setup and load it.
3. Put uncompressed or prepared VGM files somewhere accessible to MiSTer's file picker.
4. Open MegaVGMPlayer's OSD, choose **Load VGM**, and select a file.

An ordinary unmodified `.vgm` can be loaded directly. Use the import helper for `.vgz`, ZIP archives, the standard data layout, or on-screen title metadata.

## VGM import helper

The repository helper is [`scripts/vgm_md_import.sh`](scripts/vgm_md_import.sh). The common MiSTer installation path is:

```text
/media/fat/Scripts/vgm_md_import.sh
```

Its default data layout is:

```text
/media/fat/MegaVGMDrive/inbox/      source files
/media/fat/MegaVGMDrive/vgm_cache/  prepared VGM files
```

The helper accepts:

- raw `.vgm`
- `.vgz`
- ZIP containing VGM
- ZIP containing VGZ

It decompresses inputs where necessary, creates the cache layout, and adds or replaces `MVGMTTL` title metadata without modifying the source files. Repeated preparation does not append duplicate metadata. The current prepared-file limit remains exactly 8 MiB (`8,388,608` bytes), including the 128-byte title trailer.

Version 1.0.2 also makes ZIP entry extraction literal and safe for names containing spaces, parentheses, apostrophes, brackets, `*`, and `?`.

Install and run it on MiSTer with:

```sh
cp vgm_md_import.sh /media/fat/Scripts/vgm_md_import.sh
chmod +x /media/fat/Scripts/vgm_md_import.sh
/media/fat/Scripts/vgm_md_import.sh
```

## Title display

Prepared VGM files can carry a MegaVGMPlayer `MVGMTTL` trailer containing the parent directory and track basename. The on-screen player validates this trailer before displaying the two title lines; files without it remain playable without a title.

See [Prepared VGM metadata](docs/prepared_vgm_metadata.md) for the binary format and validation rules.

## Current limitations and possible future work

- MegaVGMPlayer is a standalone VGM player, not a complete console or arcade machine.
- Commands or devices outside an edition's implemented subset may be skipped or may not play as intended.
- The FPGA does not natively decompress `.vgz` or `.zip`; use the import helper.
- Mega CD / RF5C164 is not supported by either current edition.
- 32X PWM is not supported by either current edition.
- Playlist support, previous/next track, autoplay, pause, and progress display are possible future player features, not current features.

YM2610 and YM2610B are supported through the separate YM2610B Beta RBF; they are not part of the YM2151 / SegaPCM RBF.

## Builds and validation

The macOS repository and QSF are the canonical source. Projects are copied to Windows for Quartus compilation, and only Windows-built RBFs that were then tested on MiSTer hardware are published. Quartus is not run on macOS for release builds.

The stable v1.0.2 validation covered its YM2151/JT51 startup and reload cases, SegaPCM repeat-boundary playback, mixed sound paths, title metadata, and representative game music. The YM2610B Beta has separate hardware and long-run validation described in its release notes. These results are representative checks, not a claim of compatibility with every VGM rip.

## Repository layout

- `rtl/` — synthesizable player, sound integration, DDR backend, title, and video logic
- `sys/` — MiSTer framework support
- `tb/`, `tests/` — simulation and helper regressions
- `scripts/`, `tools/` — import, analysis, and test utilities
- `docs/` — format, provenance, and implementation notes

## Acknowledgements and upstream projects

MegaVGMDrive targets the [MiSTer FPGA platform](https://github.com/MiSTer-devel/Main_MiSTer) and incorporates or derives integration work from:

- [Genesis_MiSTer](https://github.com/MiSTer-devel/Genesis_MiSTer)
- JT12, JT89, JT49, JT51, JT10, and related JT cores by José Tejada Gómez (Jotego)
- SegaPCM through Jotego's JTOUTRUN / `jtoutrun_pcm` implementation

See [Genesis audio provenance](rtl/genesis_audio/README.md) for pinned revisions and local integration notes. Original copyright notices and source headers are preserved.

## License

Third-party components remain under their upstream licenses. See the included [JT51 license](third_party/jt51/LICENSE), [JT cores license](third_party/jtcores/LICENSE), component READMEs, and individual source headers.

This repository has no separate top-level `LICENSE` file. Do not infer one license for every file; review the applicable component license and source notice before redistribution.
