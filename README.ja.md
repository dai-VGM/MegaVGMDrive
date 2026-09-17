# MegaVGMPlayer

MiSTer向け FPGA Music Player

[English](README.md) · [MegaVGMPlayer v2.2](https://github.com/dai-VGM/MegaVGMDrive/releases/tag/v2.2) · [ZIP checksum](https://github.com/dai-VGM/MegaVGMDrive/releases/download/v2.2/MegaVGMPlayer-v2.2.zip.sha256)

MegaVGMDriveはFPGA/core開発プロジェクトのリポジトリ名です。ユーザー向け製品名はMegaVGMPlayerです。

## MegaVGMPlayer v2.2

MegaVGMPlayer v2.2は現在のproduction releaseです。独立したbrowser/PWA player、3種類の自動選択FPGA sound engine、Playlist、Favorites、transport control、raw SIDの統合prepare機能を提供します。

通常のユーザーがA/B/C RBFを手動選択する必要はありません。MegaVGMPlayerが各trackを分類して必要なFPGA sound engineを自動loadし、異なるengineが混在するPlaylist内でも自動切替します。

### Gallery

| Browse | Playlists |
| --- | --- |
| ![MegaVGMPlayer v2 Browse画面](docs/images/megavgmplayer-v2-browse.png) | ![MegaVGMPlayer v2 Playlists画面](docs/images/megavgmplayer-v2-playlists.png) |

## Features

- 独立daemon `megavgm_remote`が提供するRemote/PWA Player
- phone、tablet、desktop browserからMegaVGMDrive libraryをBrowse
- PlaylistsとFavorites
- Previous、Next、Stop
- Repeat OneとRepeat Context
- Shuffleとautomatic next
- track/engine間のtransition fade
- A/B/C RBFの自動切替とmixed-engine Playlist
- Playlist完了時またはPlayer終了時にstock MiSTerを自動復元
- raw `.sid`を直接選択し、自動prepareとcache再利用
- track単位のoptional manual SID loop metadata
- Engine別OSD activity表示と共通PLAY/LOAD/STOP badge

Pauseとseek/progress barは現在未実装です。

## Sound engines

| Engine | Sound hardware | Production RBF |
| --- | --- | --- |
| A | YM2612、SN76489 PSG、YM2151、YM2203、SegaPCM | `MegaVGMDrive_A.rbf` |
| B | YM2610、YM2610B | `MegaVGMDrive_B.rbf` |
| C | SID 6581/8580、PAL/NTSC timing | `MegaVGMDrive_C.rbf` |

3本のRBFはすべて`MegaVGMDrive`というcore identityを公開します。Host classifierとSupervisorが自動的に選択・切替し、ファイル名は別editionではなくdeployment profileを表します。

## SID playback

raw `.sid` fileはMegaVGMPlayerから直接選択できます。ただし、FPGAが元のSID programを直接実行するわけではありません。

再生時にMiSTer側toolingが自動でprepareを行い、SID register-write streamをPacked MVGMSID v2へ変換・検証してSID cacheへ保存します。Engine CはFPGA上で、このprepared event streamを再生します。後続再生ではvalidなcacheを再利用します。

- ユーザーによる事前の手動変換は不要です。
- prepare処理はMegaVGMPlayerのplayback flowへ統合されています。
- standalone SID converterは現在配布していません。
- SID 6581/8580 modelとPAL/NTSC timingに対応します。
- prepared SID dataのproduction capacityは8 MiBです。
- optionalな`MegaVGMPlayer-SID-loop-v1` sidecarで、信頼できるtrack単位manual loopを指定できます。
- loop pointの自動検出は行いません。

SID互換性はsource tune、metadata、選択subtune、timing/model情報、および現在のsingle-SID prepare対応範囲に依存します。

## Installation

次のrelease assetを両方downloadしてください。

- [MegaVGMPlayer-v2.2.zip](https://github.com/dai-VGM/MegaVGMDrive/releases/download/v2.2/MegaVGMPlayer-v2.2.zip)
- [MegaVGMPlayer-v2.2.zip.sha256](https://github.com/dai-VGM/MegaVGMDrive/releases/download/v2.2/MegaVGMPlayer-v2.2.zip.sha256)

final v2.2 ZIPのSHA-256は次の通りです。

```text
cf360d393263444928b6666ed4881760e88551c24d78f7a4a93a2c5723061fdb
```

使用しているcomputerで利用可能なcommandを使い、downloadしたchecksum fileで検証します。

```sh
sha256sum -c MegaVGMPlayer-v2.2.zip.sha256
# macOSの場合
shasum -a 256 -c MegaVGMPlayer-v2.2.zip.sha256
```

1. checksum fileでdownloadしたZIPを検証します。
2. `MegaVGMPlayer-v2.2.zip`を展開します。
3. MegaVGMPlayerをSTOCK modeへ戻し、開いているPlayer browser/PWA tabを閉じます。
4. 展開したpackageをMiSTerへcopyし、`root`で`sh install.sh`を実行します。
5. MiSTerをrebootします。
6. browserで`http://<MiSTer-IP>:8183/megavgm`を開くか、PWAとしてinstallします。

既存installの更新では`upgrade.sh`が同じtransactional installation pathを使用します。`rollback.sh`でupgrade前に退避したfileを復元できます。installerはrollback用に旧v2.1 RBFを保持し、`/media/fat/Scripts/remote.sh`やPlaylist/Favorites dataを変更しません。

standalone playerはMiSTer Remoteと共存します。通常、MiSTer Remoteはport 8182のままで、MegaVGMPlayerはport 8183を使用します。

## Production paths

| 用途 | Path |
| --- | --- |
| Engine A RBF | `/media/fat/_Custom Cores/Cores/MegaVGMDrive_A.rbf` |
| Engine B RBF | `/media/fat/_Custom Cores/Cores/MegaVGMDrive_B.rbf` |
| Engine C RBF | `/media/fat/_Custom Cores/Cores/MegaVGMDrive_C.rbf` |
| Runtime binaryとasset | `/media/fat/MegaVGMPlayer/` |
| MegaVGMPlayer Main | `/media/fat/MegaVGMPlayer/MiSTer.megavgm` |
| Supervisor | `/media/fat/MegaVGMPlayer/megavgm_supervisor` |
| Controller | `/media/fat/MegaVGMPlayer/megavgm_playlist-phase2a` |
| SID preparer | `/media/fat/MegaVGMPlayer/megavgm_sid_prepare` |
| Standalone Remote/PWA daemon | `/media/fat/MegaVGMPlayer/megavgm_remote` |
| Scriptsとimporter | `/media/fat/Scripts/` |
| VGM/SID library root | `/media/fat/MegaVGMDrive/` |
| PlaylistsとFavorites | `/media/fat/Scripts/.config/megavgm/playlists.json` |
| Prepared SID cache | `/media/fat/MegaVGMPlayer/cache/sid/` |

v2.2 Playerは既存の`/media/fat/MegaVGMDrive/` libraryとの互換性を維持しています。

## Musicの追加

### VGM

1. `.vgm`、`.vgz`、`.zip`を`/media/fat/MegaVGMDrive/_inbox/`へcopyします。
2. MiSTer Scripts menuから`Scripts -> vgm_md_import`を実行します。

importerが対応archiveを展開し、library root配下へ整理します。FPGAが`.vgz`や`.zip`を直接展開するわけではありません。

### SID

raw `.sid`を`/media/fat/MegaVGMDrive/`配下、例えば`SID` directoryへ配置します。BrowseまたはPlaylistから通常通り選択してください。必要に応じてMegaVGMPlayerが内部Packed MVGMSID v2 streamをprepareし、cacheします。

## PlayerとPlaylists

次のURLを開きます。

```text
http://<MiSTer-IP>:8183/megavgm
```

Browseにはlibrary root配下の対応VGM/SID contentが表示されます。PlaylistsとFavoritesでは、raw `.sid`を含むユーザーが選んだsource pathをtrack identityとして維持し、内部prepared-cache pathを表示しません。

Previous、Next、Stop、Repeat One、Repeat Context、Shuffle、automatic nextを利用できます。Playlistが異なるsound hardware familyを跨いでも、MegaVGMPlayerがEngine A/B/Cを自動切替します。

## Architecture

```text
Browser / installed PWA (:8183)
    -> megavgm_remote
    -> Supervisor
    -> Phase2A controller
    -> MiSTer.megavgm + 自動選択されたEngine A/B/C RBF
```

MegaVGMPlayerは内部で複数のFPGA sound-engine RBFを使用します。Host classifierが必要profileを選択し、Supervisorが検証済みMain/coreの置換、controller起動、transition policy、stock MiSTerの復元を担当します。通常のユーザーがRBF transitionを管理する必要はありません。

MiSTer Remoteは独立した別serviceであり、このrequest pathの依存先ではありません。

## OSD activity views

v2.2 RBFは、既存engine signalから得た軽量activity indicatorを表示します。audio levelやVU meterではありません。

- **Engine A:** YM2612、PSG、YM2151、SegaPCM、YM2203のsource activity。
- **Engine B:** FM 1–4、SSG A–C、ADPCM-A 1–6、ADPCM-Bの計14 channel activity。
- **Engine C:** SID Voice 1–3とD418 register-write activityの6-frame history、および6581/8580 modelとPAL/NTSC timing。
- **全Engine共通:** 右下のPLAY/LOAD/STOP badge。

## Limitations

- Pauseとseek/progress barは未実装です。
- Mega CD / RF5C164と32X PWMの再生には対応していません。
- Engine Cは現在single SID streamをprepareして再生します。Tune固有metadataや未対応SID構成により再生できない場合があります。
- manual SID loop metadataはoptionalで、信頼できるtrack単位sidecarから与える必要があります。
- MegaVGMPlayerはmusic playerであり、完全なconsole、arcade machine、C64実装ではありません。

## Troubleshooting

- UIが開かない場合は、`megavgm_remote`が稼働しport 8183へ到達できることを確認してください。
- trackをloadできない場合は、必要なA/B/C RBFが上記のexact production pathに存在することを確認してください。
- raw SIDのprepareが必要な場合、初回再生はcache hitより大幅に時間がかかります。後続再生はvalidなprepared cacheを再利用します。
- installが中断された場合はinstallerを再実行するか`rollback.sh`を使用し、異なるreleaseのruntime binaryを手動混在させないでください。

## Older releases

- **v2.1 “Independence Day”** でport 8183のstandalone daemonとA/B自動切替を導入しました。
- **v2.0** はport 8182のmodified MiSTer Remote integrationを使用していました。
- **v1.x** は歴史資料としてのみ残しています: [v1.0.2](https://github.com/dai-VGM/MegaVGMDrive/releases/tag/v1.0.2)、旧[YM2610B beta](https://github.com/dai-VGM/MegaVGMDrive/releases/tag/YM2610B_Beta)。

現在のinstallには[v2.2](https://github.com/dai-VGM/MegaVGMDrive/releases/tag/v2.2)を使用してください。

## Repository

MegaVGMDriveには、MegaVGMPlayerを構成するFPGA/core source、host tooling、player integration、tests、release documentationが含まれます。

source-derived licenseとprovenanceはrepositoryおよびv2.2 release packageに記録されています。binaryや派生sourceを再配布する前に、source headerと同梱provenance documentを確認してください。

## Development note

このプロジェクトのほぼすべては、プロジェクト所有者の指示のもと、OpenAI CodexおよびGPTによって実装・debugされました。

## Acknowledgements

- [MiSTer-devel/Genesis_MiSTer](https://github.com/MiSTer-devel/Genesis_MiSTer)
- [Jotego jtcores](https://github.com/jotego/jtcores)
- [JTOUTRUN](https://github.com/jotego/jtcores/tree/master/cores/outrun) SegaPCM RTL
- MiSTer FPGA community、VGM preservation community

## License

MegaVGMDriveにはoriginal codeと、それぞれ固有のlicense条件を持つsource-derived componentが含まれます。詳細はsource headerとrepositoryのprovenance documentを参照してください。
