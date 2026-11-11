# MegaVGMPlayer

Play game music on your MiSTer from a phone, tablet, or computer. MegaVGMPlayer automatically switches between seven FPGA sound engines as you play. Browse your library, save favorites, and build playlists in your browser.

[日本語](README.ja.md) · [v2.6 release notes](https://github.com/dai-VGM/MegaVGMDrive/releases/tag/v2.6) · [SHA256 checksums](https://github.com/dai-VGM/MegaVGMDrive/releases/download/v2.6/SHA256SUMS.txt)

## Install v2.6

Tested on standard MiSTer and SS1 Console Mode.

1. Download and unzip [MegaVGMPlayer-v2.6-Full-Install.zip](https://github.com/dai-VGM/MegaVGMDrive/releases/download/v2.6/MegaVGMPlayer-v2.6-Full-Install.zip). Copy the extracted contents to the root of your MiSTer SD card.
2. On MiSTer, run `Scripts → MegaVGMPlayer_Full_Setup`. Setup takes a little while. When you see `Installing... Please wait.`, wait for `Full ready`.
3. Open [http://mister.local:8183/megavgm](http://mister.local:8183/megavgm) in your browser. If it doesn’t connect, replace `mister.local` with your MiSTer’s IP address.

**Upgrading from v2.5?** Back up your SD card and return to the regular Menu before running Setup. Close the v2.5 player tab and reopen the same URL after setup.

Use `Full Exit` in the player to return to the MiSTer Menu. If setup was interrupted, run `MegaVGMPlayer_Full_Recovery` from Scripts. To remove v2.6 and restore a previous v2.5 installation, run `MegaVGMPlayer_Full_Uninstall`.

## Playback

- Supports VGM, VGZ, NSF, NSFe, and SID within the supported sound hardware and formats.
- Favorites, playlists, shuffle, and repeat work from the browser player.
- Some NES VGM/VGZ files are unsupported.
- SID files are converted on the MiSTer before first playback. If song length information is missing or the CPU is busy, conversion can exceed the 120-second limit and playback may fail. Later plays reuse a valid cached conversion. SID titles aren’t shown on the HDMI OSD.
- General NAS compatibility is untested.

### Sound engines

MegaVGMPlayer uses Jotego’s FPGA FM cores, including JT12 for the YM2612 and JT51 for the YM2151, for faithful reproduction of the original chips. Engine B’s YM2610 and YM2610B support is based on Jotego’s JT10/JT12 design.

| Engine | What it plays |
| --- | --- |
| A | Mega Drive and arcade music using YM2612, SN76489, YM2151, YM2203, SegaPCM, and K053260. |
| B | Arcade and Neo Geo music using YM2610 or YM2610B. |
| C | Commodore 64 SID music for the 6581 and 8580, with PAL and NTSC timing. |
| D | Arcade music using Namco C140 or OKI MSM6295, with YM2151 for FM. |
| E | Famicom/NES APU and expansion audio such as VRC6, VRC7, and FDS. Plays NSF/NSFe and supported NES VGM/VGZ tracks. |
| F | PC Engine/TurboGrafx-16 music using the HuC6280 PSG. |
| G | Konami arcade music using YM2151 and K053260. |

### Gallery

| Browse | Playlists |
| --- | --- |
| ![MegaVGMPlayer v2 Browse view](docs/images/megavgmplayer-v2-browse.png) | ![MegaVGMPlayer v2 Playlists view](docs/images/megavgmplayer-v2-playlists.png) |

## Source and older releases

MegaVGMDrive is the FPGA/core project behind MegaVGMPlayer. The [v2.6 release](https://github.com/dai-VGM/MegaVGMDrive/releases/tag/v2.6) includes the corresponding source, build inputs, and license notices. Earlier versions are in the [release archive](https://github.com/dai-VGM/MegaVGMDrive/releases).

## Development note

Almost all of this project was implemented and debugged by OpenAI Codex and GPT, guided by the project owner.

## Acknowledgements

- [MiSTer-devel/Genesis_MiSTer](https://github.com/MiSTer-devel/Genesis_MiSTer)
- [Jotego jtcores](https://github.com/jotego/jtcores)
- [JTOUTRUN](https://github.com/jotego/jtcores/tree/master/cores/outrun) SegaPCM RTL
- The MiSTer FPGA community and VGM preservation community

## License

MegaVGMDrive contains original code and source-derived components with their own license terms. Refer to source headers and repository provenance documents for details.
