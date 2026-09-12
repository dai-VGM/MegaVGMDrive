# MegaVGMPlayer v2.2 Engine C C5候補

この候補版は、実機確認済みPacked MVGMSID v2 Engine Cを既存A/B production
自動routeへ追加します。同じPhase2A ownerがPROFILE_A/B/Cを選択します。
Player/transport semantics、SID audio RTL、OSD、既存A/B分類判定は変更しません。

## 正式path

```text
/media/fat/_Custom Cores/Cores/MegaVGMDrive_A.rbf
/media/fat/_Custom Cores/Cores/MegaVGMDrive_B.rbf
/media/fat/_Custom Cores/Cores/MegaVGMDrive_C.rbf
```

Engine A/Bはv2.1実機PASS RBFのbyte-identical copyです。Engine Cは実機確認済み
Packed v2 artifact (`0f205de6…`)そのものを最終pathから使用します。C→CはRBFを
reloadせず、A↔C/B↔Cは既存fade/park/switch/rebind transactionを使います。

3つのCORENAMEはすべて正確に`MegaVGMDrive`のままです。

prepared SIDの正式拡張子はv1/v2共通で`.mvgmsid`です。hostは拡張子だけでなく
`MVGMSID\0` magicとEngine Cのstrict header/body contractを検証してからPROFILE_Cを
選択します。raw `.sid`と実験用`.mvgmsid2`はこのstageのlibrary/playback対象外です。
status APIはmodel、PAL/NTSC、subtune、capture-limit、source digestを保持し、Playerは
`SID 6581`または`SID 8580`を表示します。

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

通常reboot直後は`/tmp/megavgm_supervisor.status`とcontrol socketが正当に存在しない
場合があります。`status`が`STATUS_UNAVAILABLE`を返した場合、これを無視したり
`supervisor exit`を呼んだりしません。preflightはlive systemを直接調べ、実行pathが
`/media/fat/MiSTer`、実行中SHA-256が
`7ca3cd2f224b9264d0889f593a0d77aafa5adda61910baba92c5ae401e26fcce`
であるMiSTer processがexactly oneであることを要求します。controller、Supervisor、
modified Main、追加MiSTer process、playlist/session status、FIFO/socket、Phase2A channelが
1つでもあれば拒否します。同じgateをstandalone daemon drain後にも再実行します。

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

今回RBF再合成は行いません。A/B RBF、Main、importer、transport、OSD、音源実装は
変更していません。host/Remote変更はstrict prepared-SID分類、PROFILE_C switching、
persistence、read-only SID metadataに限定しています。A/B/C production統合の実機PASSは
同梱checklistをユーザーが完了するまで報告しません。
