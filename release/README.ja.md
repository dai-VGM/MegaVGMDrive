# MegaVGMPlayer v2.2 Stage 1 候補

この候補版は、FPGA音源RBFの配布名とEngine A/Bの厳密なhost pathだけを
変更します。Player挙動、transport、classifierの判定、audio RTL、OSD、
standalone Remote UIは変更していません。

## 正式path

```text
/media/fat/_Custom Cores/Cores/MegaVGMDrive_A.rbf
/media/fat/_Custom Cores/Cores/MegaVGMDrive_B.rbf
/media/fat/_Custom Cores/Cores/MegaVGMDrive_C.rbf
```

Engine A/Bはv2.1実機PASS RBFのbyte-identical copyです。Engine Cは実機確認済み
C4 artifactそのものを最終名でstagingします。Stage 1ではPROFILE_C routingや
SID分類を追加せず、production再生は従来どおりA/Bだけをrouteします。

3つのCORENAMEはすべて正確に`MegaVGMDrive`のままです。

## install / upgrade

MegaVGMPlayerをSTOCKへ戻し、Player tabを閉じ、scriptが表示するbackup pathを
保存してください。

```sh
cd /path/to/MegaVGMPlayer-v2.2
sh install.sh
# upgrade.shも同じtransactionを実行します
```

installerはpackage全体を検証し、FAT volume内でstageとbackupを作ってから各targetを
renameで置換します。旧v2.1 RBF（`_Custom Cores/Cores`または`_Utility`）は削除も
変更もしません。Remote、Playlist、Favorites、VGM libraryもpayload外です。

service semanticsは不変なのでv2.1 standalone startup blockを維持します。
checksum不一致、非STOCK、未知/重複startup、symlink、同時installでは安全に拒否します。

install後にrebootし、[HARDWARE_CHECKLIST.md](HARDWARE_CHECKLIST.md)を確認してください。
host testだけを実機FPGA切替PASSとは扱いません。

## runtime / data

- Player: `http://<MiSTer-IP>:8183/megavgm`
- Runtime: `/media/fat/MegaVGMPlayer/`
- RBF: `/media/fat/_Custom Cores/Cores/`
- Helper/importer: `/media/fat/Scripts/megavgm_ctl`, `vgm_md_import.sh`
- Music: `/media/fat/MegaVGMDrive/`
- Favorites/Playlists: `/media/fat/Scripts/.config/megavgm/playlists.json`

## v2.1へrollback

STOCKへ戻してから実行します。

```sh
sh rollback.sh
# または
sh rollback.sh '/media/fat/MegaVGMPlayer/backups-v2.2-YYYYMMDD-HHMMSS-XXXXXX'
```

rollbackはbackupを検証して旧Supervisor/controller等を復元し、v2.2で新規導入した
fileを`backup/retired/`へ回収します。旧名RBFは最初から未変更なので、復元された
v2.1 Supervisorが元のexact pathを使用できます。install後のユーザー編集は上書きせず
拒否します。

## 範囲

今回RBF再合成は行いません。Frontend、daemon、Main、importer、classifier判定、
transport、OSD、音源実装は変更していません。Engine Cの実機結果はstagingしたexact
SHAについてユーザー確認済みですが、Cのproduction routingは次stageです。
