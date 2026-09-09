# MegaVGMPlayer

**FPGA Music Player for MiSTer**

MegaVGMPlayer is an integrated FPGA VGM music player for MiSTer. **MegaVGMDrive** is the underlying repository and FPGA/core development project.

[日本語](README.ja.md) · [Download MegaVGMPlayer v2.0](https://github.com/dai-VGM/MegaVGMDrive/releases/tag/v2.0)

> **Development note:** Almost all of this project was implemented and debugged by OpenAI Codex and GPT. I only listened to the sound, ran the Quartus builds, and sent the debug values back to Codex.

## MegaVGMPlayer v2.0 Remote / PWA

<p align="center">
  <img src="docs/images/megavgmplayer-v2-browse.png" width="45%" alt="MegaVGMPlayer v2.0 Browse view with a track playing">
  <img src="docs/images/megavgmplayer-v2-playlists.png" width="45%" alt="MegaVGMPlayer v2.0 Playlists view with the mini player">
</p>

<p align="center"><em>Browse and Playlists views in the iPhone Home Screen PWA.</em></p>

## Features

- Remote / PWA Player for iPhone, iPad, and desktop browsers
- Folder browsing, Playlists, and Favorites
- Previous, Next, and immediate Stop controls
- Repeat One, Repeat Context, and Shuffle
- Automatic next-track playback and transition fades
- YM2612, YM2151, YM2203, SegaPCM, YM2610, and YM2610B playback
- Automatic FPGA sound-engine / RBF switching
- Mixed-engine playlists
- Automatic restoration to stock MiSTer after playlist completion or Exit

MegaVGMPlayer automatically selects the required FPGA sound engine. Normal playback does not require the user to choose an internal engine or RBF.

## Supported sound hardware

The v2.0 playback paths cover:

- YM2612
- YM2151
- YM2203
- SegaPCM
- YM2610
- YM2610B
- Supporting PSG/SSG and ADPCM-A/ADPCM-B paths used by those profiles

Sound-chip labels in the Remote Player are informational. They may be incomplete when the source VGM or package does not provide sufficiently precise metadata.

## Installation

1. Download and extract [`MegaVGMPlayer_v2.0.zip`](https://github.com/dai-VGM/MegaVGMDrive/releases/tag/v2.0).
2. Copy the contents of the ZIP's `media/fat/` directory into `/media/fat/` on MiSTer, preserving the directory structure.
3. Reboot MiSTer.
4. From a browser on the same LAN, open:

```text
http://<MiSTer-IP>:8182/megavgm
```

If you already use `/media/fat/Scripts/remote.sh`, back it up before copying the release manually.

For advanced installation, the package includes `install.sh`, which verifies checksums and creates a timestamped backup. The included `rollback.sh` restores that backup. Return MegaVGMPlayer to STOCK before running either operation.

## Runtime paths

FPGA sound-engine files:

```text
/media/fat/_Custom Cores/Cores/
```

Runtime components:

```text
/media/fat/MegaVGMPlayer/
```

Remote and importer scripts:

```text
/media/fat/Scripts/
```

VGM library:

```text
/media/fat/MegaVGMDrive/
```

The v2.0 release keeps compatibility with existing libraries under `/media/fat/MegaVGMDrive/`.

## Adding VGM music

Copy `.vgm`, `.vgz`, or `.zip` inputs into:

```text
/media/fat/MegaVGMDrive/inbox/
```

Then run:

```sh
/media/fat/Scripts/vgm_md_import.sh
```

Prepared VGM files are written under:

```text
/media/fat/MegaVGMDrive/vgm_cache/
```

The importer decompresses inputs when needed and adds display-title and sound-chip metadata. This prepares compressed collections; the FPGA does not play ZIP files directly.

## Remote Player access

Connect from a browser on the same LAN:

```text
http://<MiSTer-IP>:8182/megavgm
```

A fixed IP is not required. A router DHCP reservation is useful if the MiSTer address changes. On iPhone or iPad, open the page in Safari and use **Add to Home Screen** for the standalone PWA.

## Playlist, Favorites, Repeat, and Shuffle

- **Favorites** is the built-in playlist for starred tracks.
- **Repeat One** repeats the current track.
- **Repeat Context** repeats the current folder, Playlist, or Favorites snapshot.
- **Shuffle** changes traversal order within the active playback context.
- **Stop** ends playback immediately.

A queue started from a Playlist remains owned by that immutable Playlist snapshot rather than being rebuilt from the folder currently visible in Browse.

## Automatic FPGA sound-engine switching

The host classifier determines which sound engine each VGM requires. When the next track needs another engine, MegaVGMPlayer fades the current track, preserves the reserved playlist position, switches the RBF, and starts the next track in a fresh session.

Same-profile transitions do not reload the RBF. Playlists containing tracks for different sound engines continue without requiring manual core selection.

## Cold start note

Cold start may take a few seconds while MegaVGMPlayer initializes the FPGA sound engine. This one-time initialization is distinct from normal warm track transitions.

## Troubleshooting

- Confirm the browser is on the same LAN and uses `http://<MiSTer-IP>:8182/megavgm`.
- Confirm that only one Remote process owns TCP port 8182.
- Verify installed files against the package's `SHA256SUMS`.
- Keep Main, Supervisor, controller, Remote, and both RBFs from the same release set.
- If an update fails, return to STOCK and run `rollback.sh` with the backup directory reported by the installer.

## Architecture and the MegaVGMDrive project

MegaVGMDrive is the FPGA/core development repository. MegaVGMPlayer is the user-facing product integrating the FPGA sound engines, modified MiSTer Main, Supervisor, playlist controller, Remote/PWA, and importer.

VGM register streams are sent directly to synthesizable FPGA sound-core HDL:

```text
VGM data
  -> FPGA VGM parser
  -> FPGA sound-core HDL
  -> FPGA mixer
  -> MiSTer audio output
```

MegaVGMPlayer uses multiple FPGA sound-engine RBFs internally. The host classifier and Supervisor select and switch them automatically; this internal split is not part of normal user operation.

FPGA implementation does not automatically imply greater accuracy than original silicon or software emulators. The JT cores are hardware implementations, not claims of transistor-level identity with the original chips.

## Adding a sound engine

Contributors should adapt a new profile to the existing generic transport ABI: index-1 load lifecycle, index-2 policy/transition isolation, session/busy/done/loop status, the common fade owner, FADE_ONLY-to-ENDED behavior, and safe new-session audio qualification.

Extend host classification/profile mapping without changing queue ownership or Main-visible transport semantics. Validate simulation first, then Windows Quartus Full Compilation, and finally real MiSTer hardware. See [AGENTS.md](AGENTS.md) for the protected Golden Player Shell and stage-gated development rules.

## Current limitations

- MegaVGMPlayer is a standalone VGM music player, not a complete console or arcade machine.
- Commands or devices outside the implemented profiles may not play as intended.
- The FPGA does not natively decompress `.vgz` or `.zip`; use the included importer.
- Mega CD / RF5C164 and 32X PWM are not supported in v2.0.
- Pause and authoritative elapsed/remaining progress display are not included in v2.0.

## Historical releases and legacy manual core usage

The following releases remain available for older installations and manual single-core workflows. They are not the recommended entry point for new v2.0 users.

- [MegaVGMPlayer v1.0.2 — YM2151 / SegaPCM stable release](https://github.com/dai-VGM/MegaVGMDrive/releases/tag/v1.0.2)
- [MegaVGMPlayer YM2610B Beta 1](https://github.com/dai-VGM/MegaVGMDrive/releases/tag/YM2610B-beta1)

In v2.0 normal operation, users no longer select between these legacy editions manually.

## Repository layout

- `rtl/` — synthesizable player and sound integration
- `sys/` — MiSTer framework support
- `tb/`, `tests/` — simulation and regression fixtures
- `scripts/`, `tools/` — import, analysis, and test utilities
- `docs/` — formats, provenance, implementation notes, and screenshots

## Acknowledgements and upstream projects

MegaVGMDrive targets the [MiSTer FPGA platform](https://github.com/MiSTer-devel/Main_MiSTer) and incorporates or derives integration work from:

- [Genesis_MiSTer](https://github.com/MiSTer-devel/Genesis_MiSTer)
- JT12, JT89, JT49, JT51, JT10, and related JT cores by José Tejada Gómez (Jotego)
- SegaPCM through Jotego's JTOUTRUN / `jtoutrun_pcm` implementation

See [Genesis audio provenance](rtl/genesis_audio/README.md) for pinned revisions and local integration notes. Original copyright notices and source headers are preserved.

## License

Third-party components remain under their upstream licenses. See the included [JT51 license](third_party/jt51/LICENSE), [JT cores license](third_party/jtcores/LICENSE), component READMEs, and individual source headers.

This repository has no separate top-level `LICENSE` file. Do not infer one license for every file; review the applicable component license and source notice before redistribution.
