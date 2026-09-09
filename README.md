# MegaVGMPlayer

**FPGA Music Player for MiSTer**

MegaVGMPlayer is an integrated FPGA VGM music player for MiSTer. **MegaVGMDrive** is the underlying repository and FPGA/core development project.

[日本語](README.ja.md) · [Download MegaVGMPlayer v2.1](https://github.com/dai-VGM/MegaVGMDrive/releases/tag/v2.1)

> **Development note:** Almost all of this project was implemented and debugged by OpenAI Codex and GPT. I only listened to the sound, ran the Quartus builds, and sent the debug values back to Codex.

## MegaVGMPlayer v2.1 Remote / PWA

<p align="center">
  <img src="docs/images/megavgmplayer-v2-browse.png" width="45%" alt="MegaVGMPlayer Browse view with a track playing">
  <img src="docs/images/megavgmplayer-v2-playlists.png" width="45%" alt="MegaVGMPlayer Playlists view with the mini player">
</p>

<p align="center"><em>Browse and Playlists views in the iPhone Home Screen PWA.</em></p>

Version 2.1, “Independence Day,” runs the Player and API in the dedicated `megavgm_remote` daemon on port **8183**. It no longer requires a modified MiSTer Remote. The normal MiSTer Remote can continue independently on port 8182.

```text
http://<MiSTer-IP>:8183/megavgm
```

## Features

- Independent Remote / PWA Player for iPhone, iPad, and desktop browsers
- Folder browsing, Playlists, and Favorites
- Previous, Next, immediate Stop, Repeat One, Repeat Context, and Shuffle
- Automatic next-track playback and transition fades
- YM2612, YM2151, YM2203, SegaPCM, YM2610, and YM2610B playback
- Automatic FPGA sound-engine / RBF switching and mixed-engine playlists
- Daemon restart without stopping FPGA playback, followed by status reconnection
- Automatic daemon startup after reboot
- Automatic restoration to stock MiSTer after playlist completion or Exit

MegaVGMPlayer automatically selects the required FPGA sound engine. Normal playback does not require manual engine or RBF selection. Supporting PSG/SSG and ADPCM-A/ADPCM-B paths are included where required. Player sound-chip labels are informational and depend on available VGM/package metadata.

## Installation

1. Download and extract [`MegaVGMPlayer-v2.1.zip`](https://github.com/dai-VGM/MegaVGMDrive/releases/tag/v2.1).
2. Copy the ZIP's `media/fat/` contents into `/media/fat/` on MiSTer while preserving the directory structure, or copy the whole package to MiSTer and use `install.sh`.
3. Reboot MiSTer.
4. From a browser on the same LAN, open `http://<MiSTer-IP>:8183/megavgm`.

For advanced installation or upgrade, return MegaVGMPlayer to STOCK first. The included `install.sh` / `upgrade.sh` verifies checksums, makes a timestamped backup, and registers the standalone service in `/media/fat/linux/user-startup.sh`. `rollback.sh` restores the backup. Read the package README before running these scripts.

The v2.1 package does **not** contain or overwrite `/media/fat/Scripts/remote.sh`. It does not replace, migrate, or delete the existing Favorites/Playlists file.

### Upgrading from v2.0

- Favorites/Playlists and the VGM library require no migration.
- The production RBF directory remains unchanged.
- The official v2.1 URL is `http://<MiSTer-IP>:8183/megavgm`.
- Do not operate the old v2.0 MegaVGMPlayer UI on port 8182 concurrently with v2.1.
- A v2.0 Home Screen shortcut points to the old origin. Open the new 8183 URL in Safari and add it to the Home Screen again.

v2.1 does not replace a possibly customized v2.0 `remote.sh` with an unknown upstream version. Leaving it installed does not prevent v2.1 from running on 8183. MiSTer Remote itself remains available normally on 8182.

## Production paths

```text
/media/fat/_Custom Cores/Cores/
  MegaVGMPlayer_Transport13FadeOnly_A_MiSTer.rbf
  MegaVGMPlayer_Transport13FadeOnly_B_MiSTer.rbf

/media/fat/MegaVGMPlayer/
  MiSTer.megavgm
  megavgm_supervisor
  megavgm_playlist-phase2a
  megavgm_remote

/media/fat/Scripts/
  megavgm_ctl
  vgm_md_import.sh
```

The internal engine names are implementation details. Existing Favorites and Playlists remain at `/media/fat/Scripts/.config/megavgm/playlists.json`. The standard VGM library remains `/media/fat/MegaVGMDrive/`.

## Adding VGM music

Copy `.vgm`, `.vgz`, or `.zip` inputs into `/media/fat/MegaVGMDrive/inbox/`, then run:

```sh
/media/fat/Scripts/vgm_md_import.sh
```

Prepared files are written below `/media/fat/MegaVGMDrive/vgm_cache/`. The importer decompresses inputs and adds display metadata where needed; the FPGA does not play ZIP files directly.

## Remote Player and PWA

Use `http://<MiSTer-IP>:8183/megavgm` from the same LAN. A fixed IP is not required; a router DHCP reservation is useful if the address changes. On iPhone/iPad, open this exact URL in Safari and choose **Add to Home Screen**.

Port 8182 belongs to MiSTer Remote and is not the MegaVGMPlayer v2.1 URL. Both services can listen simultaneously and operate independently.

## Playlist controls

- **Favorites** is the built-in playlist for starred tracks.
- **Repeat One** repeats one track; **Repeat Context** repeats the active folder, Playlist, or Favorites snapshot.
- **Shuffle** changes traversal order inside the active context.
- **Stop** ends playback immediately.

A Playlist queue remains owned by its immutable snapshot rather than the folder currently visible in Browse.

## Automatic FPGA sound-engine switching

The host classifier determines the required sound engine. At a profile boundary, MegaVGMPlayer fades the current track, preserves the reserved queue position, switches the RBF, and begins the next track in a fresh session. Same-profile transitions do not reload the RBF. Playlist completion or Exit restores STOCK.

## Cold start and troubleshooting

Cold start may take a few seconds while MegaVGMPlayer initializes the FPGA sound engine. This is distinct from normal warm transitions.

- Confirm the browser uses `http://<MiSTer-IP>:8183/megavgm` on the same LAN.
- Confirm exactly one `megavgm_remote` owns TCP 8183; MiSTer Remote on 8182 is separate and expected.
- Verify files using the package `SHA256SUMS`, and keep all runtime components from one release set.
- If an update fails, return to STOCK and run `rollback.sh` with the installer-reported backup.

## Architecture and MegaVGMDrive

```text
Browser / PWA (:8183)
  -> megavgm_remote
  -> Supervisor
  -> Phase2A controller
  -> MiSTer.megavgm + selected FPGA sound-engine RBF
```

MiSTer Remote is not in this path. MegaVGMDrive is the FPGA/core repository; MegaVGMPlayer is the user-facing integration. VGM register streams are sent to synthesizable FPGA sound-core HDL. FPGA implementation does not imply transistor-level identity or automatic superiority to original silicon or software emulation.

Contributors adding an engine should adapt it to the existing generic transport ABI and preserve queue/session/transition semantics. Validate simulation, Windows Quartus Full Compilation, then real MiSTer hardware. See [AGENTS.md](AGENTS.md).

## Current limitations

- This is a VGM music player, not a complete console or arcade machine.
- Unsupported commands/devices may not play as intended.
- Use the importer for `.vgz`/`.zip`; the FPGA does not decompress them.
- Mega CD / RF5C164 and 32X PWM are not supported in v2.1.
- Pause and authoritative elapsed/remaining progress are not included.

## Historical releases

- [v2.0](https://github.com/dai-VGM/MegaVGMDrive/releases/tag/v2.0) used a modified MiSTer Remote on port 8182; this is legacy architecture.
- [v1.0.2 — YM2151 / SegaPCM](https://github.com/dai-VGM/MegaVGMDrive/releases/tag/v1.0.2)
- [YM2610B Beta 1](https://github.com/dai-VGM/MegaVGMDrive/releases/tag/YM2610B-beta1)

## Repository, acknowledgements, and license

The repository contains synthesizable RTL, MiSTer framework support, simulations/tests, import and analysis tools, documentation, and screenshots. It incorporates or derives integration work from [Genesis_MiSTer](https://github.com/MiSTer-devel/Genesis_MiSTer), José Tejada Gómez's JT cores, and JTOUTRUN SegaPCM. See [Genesis audio provenance](rtl/genesis_audio/README.md).

Third-party components remain under their upstream licenses. Review component licenses, READMEs, and source headers; there is no single inferred top-level license for every file.
