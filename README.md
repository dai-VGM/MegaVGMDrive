# MegaVGMPlayer

FPGA Music Player for MiSTer

[日本語](README.ja.md) · [MegaVGMPlayer v2.2](https://github.com/dai-VGM/MegaVGMDrive/releases/tag/v2.2) · [ZIP checksum](https://github.com/dai-VGM/MegaVGMDrive/releases/download/v2.2/MegaVGMPlayer-v2.2.zip.sha256)

MegaVGMDrive is the underlying FPGA/core development project. MegaVGMPlayer is the user-facing player distributed from this repository.

## MegaVGMPlayer v2.2

MegaVGMPlayer v2.2 is the current production release. It provides a standalone browser/PWA player, three automatically selected FPGA sound engines, playlists, favorites, transport controls, and integrated raw SID preparation.

Users normally do not select an A/B/C RBF manually. MegaVGMPlayer classifies each track and automatically loads the required FPGA sound engine, including transitions inside mixed-engine playlists.

### Gallery

| Browse | Playlists |
| --- | --- |
| ![MegaVGMPlayer v2 Browse view](docs/images/megavgmplayer-v2-browse.png) | ![MegaVGMPlayer v2 Playlists view](docs/images/megavgmplayer-v2-playlists.png) |

## Features

- Remote/PWA player served directly by the standalone `megavgm_remote` daemon
- Browse the MegaVGMDrive library from a phone, tablet, or desktop browser
- Playlists and favorites
- Previous, Next, and Stop controls
- Repeat One and Repeat Context
- Shuffle and automatic next-track playback
- Transition fade between tracks and engines
- Mixed-engine playlists with automatic A/B/C RBF switching
- Automatic restoration of stock MiSTer after playlist completion or player exit
- Direct selection of raw `.sid` files with automatic preparation and cache reuse
- Optional per-track manual SID loop metadata
- Engine-specific OSD activity views and a common PLAY/LOAD/STOP badge

Pause and seek/progress-bar controls are not currently implemented.

## Sound engines

| Engine | Sound hardware | Production RBF |
| --- | --- | --- |
| A | YM2612, SN76489 PSG, YM2151, YM2203, SegaPCM | `MegaVGMDrive_A.rbf` |
| B | YM2610 and YM2610B | `MegaVGMDrive_B.rbf` |
| C | SID 6581/8580 with PAL and NTSC timing | `MegaVGMDrive_C.rbf` |

All three RBFs publish the `MegaVGMDrive` core identity. The host classifier and Supervisor choose and switch them automatically; the filenames identify deployment profiles, not separate user editions.

## SID playback

Raw `.sid` files can be selected directly in MegaVGMPlayer. The FPGA does **not** execute the original SID program.

During playback, MiSTer-side tooling automatically runs the preparation step, converts the SID register-write stream to Packed MVGMSID v2, validates it, and stores it in the SID cache. Engine C then replays that prepared event stream on the FPGA. A valid cached result is reused on later plays.

- No manual pre-conversion is required.
- Preparation is integrated into the MegaVGMPlayer playback flow.
- A standalone SID converter is not currently distributed.
- SID 6581 and 8580 models are supported with PAL and NTSC timing.
- Prepared SID data has an 8 MiB production capacity.
- Optional `MegaVGMPlayer-SID-loop-v1` sidecars can define a trusted per-track manual loop.
- Loop points are not detected automatically.

SID compatibility depends on the source tune, metadata, selected subtune, timing/model information, and current single-SID preparation support.

## Installation

Download both release assets:

- [MegaVGMPlayer-v2.2.zip](https://github.com/dai-VGM/MegaVGMDrive/releases/download/v2.2/MegaVGMPlayer-v2.2.zip)
- [MegaVGMPlayer-v2.2.zip.sha256](https://github.com/dai-VGM/MegaVGMDrive/releases/download/v2.2/MegaVGMPlayer-v2.2.zip.sha256)

The final v2.2 ZIP SHA-256 is:

```text
cf360d393263444928b6666ed4881760e88551c24d78f7a4a93a2c5723061fdb
```

Verify it with the downloaded checksum file, using the command available on your computer:

```sh
sha256sum -c MegaVGMPlayer-v2.2.zip.sha256
# or on macOS
shasum -a 256 -c MegaVGMPlayer-v2.2.zip.sha256
```

1. Verify the downloaded ZIP against the checksum file.
2. Extract `MegaVGMPlayer-v2.2.zip`.
3. Return MegaVGMPlayer to STOCK mode and close open Player browser/PWA tabs.
4. Copy the extracted package to the MiSTer and run `sh install.sh` as `root`.
5. Reboot the MiSTer.
6. Open `http://<MiSTer-IP>:8183/megavgm` in a browser, or install it as a PWA.

For an existing installation, `upgrade.sh` uses the same transactional installation path. `rollback.sh` restores the captured pre-upgrade files. The installer preserves old v2.1 RBFs for rollback and does not replace `/media/fat/Scripts/remote.sh` or modify playlist/favorites data.

The standalone player coexists with MiSTer Remote. MiSTer Remote normally remains on port 8182; MegaVGMPlayer uses port 8183.

## Production paths

| Purpose | Path |
| --- | --- |
| Engine A RBF | `/media/fat/_Custom Cores/Cores/MegaVGMDrive_A.rbf` |
| Engine B RBF | `/media/fat/_Custom Cores/Cores/MegaVGMDrive_B.rbf` |
| Engine C RBF | `/media/fat/_Custom Cores/Cores/MegaVGMDrive_C.rbf` |
| Runtime binaries and assets | `/media/fat/MegaVGMPlayer/` |
| MegaVGMPlayer Main | `/media/fat/MegaVGMPlayer/MiSTer.megavgm` |
| Supervisor | `/media/fat/MegaVGMPlayer/megavgm_supervisor` |
| Controller | `/media/fat/MegaVGMPlayer/megavgm_playlist-phase2a` |
| SID preparer | `/media/fat/MegaVGMPlayer/megavgm_sid_prepare` |
| Standalone Remote/PWA daemon | `/media/fat/MegaVGMPlayer/megavgm_remote` |
| Scripts and importer | `/media/fat/Scripts/` |
| VGM/SID library root | `/media/fat/MegaVGMDrive/` |
| Playlists and favorites | `/media/fat/Scripts/.config/megavgm/playlists.json` |
| Prepared SID cache | `/media/fat/MegaVGMPlayer/cache/sid/` |

The v2.2 player remains compatible with existing libraries under `/media/fat/MegaVGMDrive/`.

## Adding music

### VGM

1. Copy `.vgm`, `.vgz`, or `.zip` files into `/media/fat/MegaVGMDrive/_inbox/`.
2. Run `Scripts -> vgm_md_import` from the MiSTer Scripts menu.

The importer decompresses supported archives and organizes files below the library root. The FPGA does not decompress `.vgz` or `.zip` files directly.

### SID

Place raw `.sid` files below `/media/fat/MegaVGMDrive/`, for example in a `SID` directory. Select them normally from Browse or a playlist. MegaVGMPlayer prepares and caches the internal Packed MVGMSID v2 stream when needed.

## Player and playlists

Open:

```text
http://<MiSTer-IP>:8183/megavgm
```

Browse shows supported VGM and SID content under the library root. Playlists and favorites keep the user-visible source path, including the original raw `.sid` path; internal prepared-cache paths are not exposed as track identity.

Available playback controls include Previous, Next, Stop, Repeat One, Repeat Context, Shuffle, and automatic next. MegaVGMPlayer can switch Engine A, B, and C automatically as a playlist crosses sound-hardware families.

## Architecture

```text
Browser / installed PWA (:8183)
    -> megavgm_remote
    -> Supervisor
    -> Phase2A controller
    -> MiSTer.megavgm + automatically selected Engine A/B/C RBF
```

MegaVGMPlayer uses multiple FPGA sound-engine RBFs internally. The host classifier selects the required profile, and the Supervisor owns verified Main/core replacement, controller launch, transition policy, and restoration of stock MiSTer. Normal users do not manage those RBF transitions.

MiSTer Remote is a separate service and is not part of this request path.

## OSD activity views

The v2.2 RBFs show lightweight activity indicators derived from existing engine signals. They are activity displays, not audio-level or VU meters.

- **Engine A:** source activity for YM2612, PSG, YM2151, SegaPCM, and YM2203.
- **Engine B:** 14 channel indicators: FM 1–4, SSG A–C, ADPCM-A 1–6, and ADPCM-B.
- **Engine C:** SID Voice 1–3 and D418 register-write activity with a six-frame history, plus the active 6581/8580 model and PAL/NTSC timing.
- **All engines:** a common right-bottom PLAY/LOAD/STOP badge.

## Limitations

- Pause and seek/progress-bar controls are not implemented.
- Mega CD / RF5C164 and 32X PWM playback are not supported.
- Engine C currently prepares and replays a single SID stream; tune-specific metadata or unsupported SID arrangements may prevent playback.
- Manual SID loop metadata is optional and must come from a trusted per-track sidecar.
- MegaVGMPlayer is a music player, not a complete console, arcade-machine, or C64 implementation.

## Troubleshooting

- If the UI does not open, confirm that `megavgm_remote` is running and that port 8183 is reachable.
- If a track fails to load, confirm that the required A/B/C RBF exists at the exact production path above.
- If a raw SID needs preparation, the first play can take substantially longer than a cache hit. Later plays reuse a valid prepared cache entry.
- If installation is interrupted, rerun the installer or use `rollback.sh`; do not manually mix runtime binaries from different releases.

## Older releases

- **v2.1 “Independence Day”** introduced the standalone daemon on port 8183 and automatic A/B switching.
- **v2.0** used a modified MiSTer Remote integration on port 8182.
- **v1.x** is retained for historical reference only: [v1.0.2](https://github.com/dai-VGM/MegaVGMDrive/releases/tag/v1.0.2) and the older [YM2610B beta](https://github.com/dai-VGM/MegaVGMDrive/releases/tag/YM2610B_Beta).

Use [v2.2](https://github.com/dai-VGM/MegaVGMDrive/releases/tag/v2.2) for current installations.

## Repository

MegaVGMDrive contains the FPGA/core sources, host tooling, player integration, tests, and release documentation used to build MegaVGMPlayer.

Source-derived licensing and provenance are documented in the repository and the v2.2 release package. See source headers and included provenance documents before redistributing binaries or derived source.

## Development note

Almost all of this project was implemented and debugged by OpenAI Codex and GPT, guided by the project owner.

## Acknowledgements

- [MiSTer-devel/Genesis_MiSTer](https://github.com/MiSTer-devel/Genesis_MiSTer)
- [Jotego jtcores](https://github.com/jotego/jtcores)
- [JTOUTRUN](https://github.com/jotego/jtcores/tree/master/cores/outrun) SegaPCM RTL
- The MiSTer FPGA community and VGM preservation community

## License

MegaVGMDrive contains original code and source-derived components with their own license terms. Refer to source headers and repository provenance documents for details.
