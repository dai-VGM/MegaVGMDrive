# MegaVGMPlayer

**MiSTer向け FPGA Music Player**

**MegaVGMPlayer**はMiSTer向けのFPGA VGM音楽プレイヤーです。**MegaVGMDrive**は基盤となるrepository／FPGA core開発projectです。

[English](README.md) · [MegaVGMPlayer v2.1をダウンロード](https://github.com/dai-VGM/MegaVGMDrive/releases/tag/v2.1)

> **開発について:** このプロジェクトの実装とデバッグのほぼすべてはOpenAI CodexとGPTが行いました。私は実際の音を聴き、Quartusでbuildし、MiSTer実機のデバッグ値や聴感結果をCodexへ返す役割を担当しました。ただの聴き専です。

## MegaVGMPlayer v2.1 Remote / PWA

<p align="center">
  <img src="docs/images/megavgmplayer-v2-browse.png" width="45%" alt="曲を再生中のMegaVGMPlayer Browse画面">
  <img src="docs/images/megavgmplayer-v2-playlists.png" width="45%" alt="mini playerを表示したMegaVGMPlayer Playlists画面">
</p>

<p align="center"><em>iPhoneホーム画面PWAのBrowse／Playlists画面。</em></p>

v2.1 “Independence Day”では、PlayerとAPIが専用daemon `megavgm_remote`としてport **8183**で動作します。改造MiSTer Remoteは不要です。通常のMiSTer Remoteは8182で独立して使い続けられます。

```text
http://<MiSTer-IP>:8183/megavgm
```

## 主な機能

- iPhone／iPad／desktop browser向けの独立Remote / PWA Player
- folder Browse、Playlist、Favorites
- Previous、Next、即時Stop、Repeat One、Repeat Context、Shuffle
- automatic nextと曲間transition fade
- YM2612、YM2151、YM2203、SegaPCM、YM2610、YM2610B
- FPGA sound engine／RBFの自動選択・切替とmixed-engine playlist
- daemon restart中もFPGA再生を継続し、UI再接続後に状態復帰
- reboot後のdaemon自動起動
- Playlist完了またはExit後のstock MiSTer自動復帰

通常再生でRBFや内部engineを選ぶ必要はありません。必要なFPGA sound engineをMegaVGMPlayerが自動選択します。必要なPSG／SSG、ADPCM-A／ADPCM-B経路も含まれます。Playerのsound-chip表示は補助情報であり、VGM／package metadataに依存します。

## インストール

1. [MegaVGMPlayer v2.1 Release](https://github.com/dai-VGM/MegaVGMDrive/releases/tag/v2.1)から`MegaVGMPlayer-v2.1.zip`をdownloadして展開します。
2. ZIP内`media/fat/`以下をdirectory構造ごとMiSTerの`/media/fat/`へcopyするか、package全体をMiSTerへcopyして`install.sh`を使います。
3. MiSTerをrebootします。
4. 同じLANのbrowserで`http://<MiSTer-IP>:8183/megavgm`を開きます。

Advanced install／upgradeでは先にSTOCKへ戻します。同梱`install.sh`／`upgrade.sh`はchecksum確認、timestamp backup、`/media/fat/linux/user-startup.sh`へのservice登録を行います。`rollback.sh`はbackupを復元します。実行前にpackage READMEを確認してください。

v2.1 packageは`/media/fat/Scripts/remote.sh`を同梱・上書きしません。Favorites／Playlistsも置換、移行、削除しません。

### v2.0からのupgrade

- Favorites／PlaylistsとVGM libraryはmigration不要です。
- production RBF directoryは変わりません。
- v2.1の正式URLは`http://<MiSTer-IP>:8183/megavgm`です。
- v2.0の8182 MegaVGMPlayer UIとv2.1を同時操作しないでください。
- v2.0ホーム画面shortcutは古いoriginを指します。Safariで8183の新URLを開き、ホーム画面へ追加し直してください。

v2.1は、customizeされている可能性があるv2.0 `remote.sh`を出所不明のupstream版へ自動置換しません。既存Remoteを残してもv2.1は8183で独立動作し、MiSTer Remoteは8182で通常利用できます。

## Production path

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

A/B名は内部実装です。既存Favorites／Playlistsは`/media/fat/Scripts/.config/megavgm/playlists.json`、標準VGM libraryは`/media/fat/MegaVGMDrive/`のままです。

## VGM音楽の追加

`.vgm`、`.vgz`、`.zip`を`/media/fat/MegaVGMDrive/inbox/`へcopyし、次を実行します。

```sh
/media/fat/Scripts/vgm_md_import.sh
```

準備済みVGMは`/media/fat/MegaVGMDrive/vgm_cache/`へ保存されます。Importerが必要な展開と表示metadata付加を行います。FPGAがZIPを直接再生する機能ではありません。

## Remote PlayerとPWA

同じLANから`http://<MiSTer-IP>:8183/megavgm`へ接続します。固定IPは必須ではなく、必要ならrouterのDHCP reservationを使えます。iPhone／iPadではSafariでこの正確なURLを開き、「ホーム画面に追加」を使います。

8182はMiSTer Remote用であり、MegaVGMPlayer v2.1のURLではありません。両serviceは独立して同時LISTENできます。

## Playlist操作

- **Favorites:** starを付けた曲のbuilt-in playlist
- **Repeat One:** 1曲をrepeat
- **Repeat Context:** activeなfolder／Playlist／Favorites snapshotをrepeat
- **Shuffle:** active context内の再生順をshuffle
- **Stop:** 即時停止

Playlist queueはimmutable snapshotとして所有され、Browse中のfolderとは独立します。

## FPGA sound engineの自動切替

Host classifierが必要なsound engineを判定します。Profile境界では現在曲をfadeし、予約済みqueue位置を保持してRBFを切り替え、新sessionで次曲を開始します。同一profileではRBFをreloadしません。Playlist完了またはExitでSTOCKへ戻します。

## Cold startとTroubleshooting

Cold startではFPGA sound engine初期化に数秒かかる場合があります。通常のwarm transitionとは異なります。

- 同じLANから`http://<MiSTer-IP>:8183/megavgm`を開きます。
- TCP 8183の`megavgm_remote`がexactly oneであることを確認します。8182のMiSTer Remoteは別serviceなので正常です。
- package `SHA256SUMS`を確認し、全runtime componentを同じrelease setから使います。
- update失敗時はSTOCKへ戻し、installerが表示したbackupを指定して`rollback.sh`を実行します。

## ArchitectureとMegaVGMDrive

```text
Browser / PWA (:8183)
  -> megavgm_remote
  -> Supervisor
  -> Phase2A controller
  -> MiSTer.megavgm + selected FPGA sound-engine RBF
```

MiSTer Remoteはこの経路に含まれません。MegaVGMDriveはFPGA/core repository、MegaVGMPlayerはユーザー向け統合製品です。VGM register streamはsynthesizable FPGA sound-core HDLへ送られます。FPGA実装はoriginal siliconとのtransistor-level identityやsoftware emulationに対する自動的優位を意味しません。

新sound engineは既存generic transport ABIへ適応し、queue／session／transition semanticsを維持してください。Simulation、Windows Quartus Full Compilation、MiSTer実機の順に確認します。詳細は[AGENTS.md](AGENTS.md)を参照してください。

## 既知事項

- VGM音楽playerであり、console／arcade machine本体の完全実装ではありません。
- 未対応command／deviceは意図どおり再生されない場合があります。
- `.vgz`／`.zip`にはImporterを使います。FPGAはnative展開しません。
- Mega CD / RF5C164、32X PWMはv2.1未対応です。
- Pause、authoritativeなelapsed／remaining progressは未実装です。

## 過去のrelease

- [v2.0](https://github.com/dai-VGM/MegaVGMDrive/releases/tag/v2.0)はport 8182の改造MiSTer Remoteを使用したlegacy architectureです。
- [v1.0.2 — YM2151 / SegaPCM](https://github.com/dai-VGM/MegaVGMDrive/releases/tag/v1.0.2)
- [YM2610B Beta 1](https://github.com/dai-VGM/MegaVGMDrive/releases/tag/YM2610B-beta1)

## Repository、謝辞、license

Repositoryにはsynthesizable RTL、MiSTer framework、simulation／test、import／analysis tool、document、screenshotがあります。[Genesis_MiSTer](https://github.com/MiSTer-devel/Genesis_MiSTer)、José Tejada Gómez（Jotego）のJT core、JTOUTRUN SegaPCMなどを利用またはintegrationの基礎としています。[Genesis audio provenance](rtl/genesis_audio/README.md)も参照してください。

Third-party componentには各upstream licenseが適用されます。Component license、README、source headerを確認してください。全fileに単一licenseが適用されるとは推測しないでください。
