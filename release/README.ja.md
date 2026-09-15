# MegaVGMPlayer v2.2 Engine C C7.2実機検証候補

> **これはlab用実機検証packageです。公開版・最終v2.2 RCではありません。**

Engine C RBF、SID preparer、Controller、Supervisorのみをstrict C7.2
manual-loop lineageへ差し替えます。オリジナルのPAL/6581 synthetic SIDと
sidecarは`/media/fat/MegaVGMDrive/C7_2_Hardware_Test/`へ配置されます。
`HARDWARE_CHECKLIST.md`に従い、Commando/Volfiedのloop pointはまだ作成しないでください。

この候補版は、実機確認済みC5 A/B/C routeへraw SIDの自動prepareを追加します。
`.sid`を`/media/fat/MegaVGMDrive/`へ置いてBrowseから選ぶと、HPSがPacked MVGMSID v2
cacheを生成してから既存PROFILE_C pathを使用します。queue/Favorites/statusでは元SIDの
identityを保持し、cache fileはBrowseへ表示しません。

## 正式path

```text
/media/fat/_Custom Cores/Cores/MegaVGMDrive_A.rbf
/media/fat/_Custom Cores/Cores/MegaVGMDrive_B.rbf
/media/fat/_Custom Cores/Cores/MegaVGMDrive_C.rbf
```

Engine A/Bはv2.1実機PASS RBFのbyte-identical copyです。Engine Cは8 MiB Packed-v2
RTL authorityからWindows QuartusでFull Compilationしたartifact (`efb29a23…`)を
最終pathから使用します。拡張容量は実機未確認です。C→CはRBFをreloadせず、
A↔C/B↔Cは既存fade/park/switch/rebind transactionを使います。

3つのCORENAMEはすべて正確に`MegaVGMDrive`のままです。

raw `.sid`をFPGAへ直接送ったり、playable PROFILE_C payloadとして分類したりしません。
HPS preparerが固定libsidplayfpでstart subtuneを実行し、native-cycle SID bus WRITEを
直接捕捉してPacked v2を生成します。strict validation後に
`/media/fat/MegaVGMPlayer/cache/sid/`へatomic publishし、そのcacheだけを既存C5
classifier/index-1経路へ渡します。cache miss中は`Preparing SID…`を表示します。

初期C6はsingle SIDとPSID/RSIDのstart subtuneに対応します。headerでexactな
6581/8580・PAL/NTSCを使用し、unknown/anyは勝手にdefaultせず、exact SHA/subtune
`.sid.megavgm` sidecarが必要です。BASIC-ROM互換曲とmulti-SIDはrejectします。
C64 ROMや著作権SID曲は同梱しません。

durationはoptional `MegaVGMPlayer/sid/Songlengths.md5`のcontent-MD5+subtune照合、
exact sidecar、300秒capture limitの順です。basename照合やloop推測はしません。

prepared file上限はexact 8 MiBです。Packed MVGMSID v2のformat/versionは変更しません。
cache keyには`capacity_bytes=8388608`を含めるため、旧4 MiB cacheはdiskに残りますが
このbuildのcache hitにはなりません。

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

transaction完了前に、installerは全production targetをpackage payloadとSHA-256で
再照合し、standalone Remoteを再起動します。その後、package、installed Remote、
runtime `/tmp/megavgm_remote`、serviceが報告するSHA、`/proc/<pid>/exe`の実行identityが
すべて一致することを要求します。不一致時はtransactionを`COMPLETE`にせず、stageや
置換済みfileが存在するだけではinstall成功と扱いません。

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
- SID cache: `/media/fat/MegaVGMPlayer/cache/sid/`
- optional duration DB: `/media/fat/MegaVGMPlayer/sid/Songlengths.md5`

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

8 MiB storage/parser上限のためEngine Cだけを再compileしました。A/B RBF、Main、Remote、
Frontend、importer、transport、OSD、音源実装は変更していません。C6 production統合の
実機PASSは同梱checklistをユーザーが完了するまで報告しません。
