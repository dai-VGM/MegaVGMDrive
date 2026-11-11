# MegaVGMPlayer

MiSTerでゲーム音楽を楽しむプレイヤーです。スマホやPCのブラウザーで選曲でき、曲に合わせて7種類のFPGA音源が自動で切り替わります。お気に入りやプレイリストも作れます。

[English](README.md) · [v2.6 リリースノート](https://github.com/dai-VGM/MegaVGMDrive/releases/tag/v2.6) · [SHA256一覧](https://github.com/dai-VGM/MegaVGMDrive/releases/download/v2.6/SHA256SUMS.txt)

## v2.6のインストール

標準MiSTerとSS1 Console Modeで動作を確認しています。

1. [MegaVGMPlayer-v2.6-Full-Install.zip](https://github.com/dai-VGM/MegaVGMDrive/releases/download/v2.6/MegaVGMPlayer-v2.6-Full-Install.zip) をダウンロードして解凍し、中身をSDカードのルートにコピー。
2. MiSTerの `Scripts → MegaVGMPlayer_Full_Setup` を実行。Setupには少し時間がかかります。`Installing... Please wait.` が出たら、`Full ready` が表示されるまでお待ちください。
3. ブラウザーで [http://mister.local:8183/megavgm](http://mister.local:8183/megavgm) を開きます。つながらない場合は `mister.local` をMiSTerのIPアドレスに置き換えてください。

**v2.5から更新する場合**は、SDカードをバックアップし、通常Menuに戻ってからSetupを実行してください。v2.5のプレイヤーを開いていた場合は一度閉じ、Setup後に同じURLを開き直してください。

Menuに戻るにはプレイヤーの `Full Exit` を選びます。Setupが途中で止まった場合はScriptsから `MegaVGMPlayer_Full_Recovery`、v2.6を削除して元のv2.5に戻す場合は `MegaVGMPlayer_Full_Uninstall` を実行します。

## 再生について

- VGM・VGZ・NSF・NSFe・SIDを再生できます。対応音源やファイル形式には制限があります。
- ブラウザーからお気に入りやプレイリストを使えます。シャッフルやリピートにも対応しています。
- 一部のNES VGM/VGZは未対応です。
- SIDは初回再生時にMiSTer上で事前変換します。曲長情報がない場合やCPU負荷が高い環境では、変換が120秒の制限を超えて再生に失敗することがあります。変換済みキャッシュがあれば再利用します。SIDの曲名はHDMIのOSDに表示されません。
- NAS全般の動作は未検証です。

### 音源エンジン

FM音源にはJotego製のFPGAコアを採用しています。YM2612のJT12やYM2151のJT51が、実チップの音を忠実に再現します。Engine BのYM2610／YM2610Bも、Jotego製のJT10／JT12をベースにしています。

| Engine | 担当する音源・楽曲 | 音源RTLの出典 |
| --- | --- | --- |
| A | メガドライブやアーケード向け。YM2612、SN76489、YM2151、YM2203、SegaPCM、K053260。 | YM2612／YM2203のFMはJotego製の [JT12／JT03](https://github.com/jotego/jt12)、YM2151は [JT51](https://github.com/jotego/jt51)、SSGは [JT49](https://github.com/jotego/jt49)、SN76489は [JT89](https://github.com/jotego/jt89)。 |
| B | ネオジオやアーケード向け。YM2610／YM2610B。 | YM2610／YM2610BはJotego製の [JT10／JT12](https://github.com/jotego/jt12) がベース。SSGには [JT49](https://github.com/jotego/jt49) を使用。 |
| C | Commodore 64のSID楽曲。6581／8580、PAL／NTSCに対応。 | [C64_MiSTer](https://github.com/MiSTer-devel/C64_MiSTer/tree/fe6dfe53c99122e5a088691f2d358d6caba61de1/rtl/sid) のSID RTLを使用。DACとフィルターはDag Lemの [reDIP-SID](https://github.com/daglem/reDIP-SID) がベースで、フィルターはAlexey Melnikovが移植。 |
| D | アーケード向け。ナムコC140やOKI MSM6295のPCM系音源と、YM2151のFM音源。 | YM2151はJotego製の [JT51](https://github.com/jotego/jt51)。C140とMSM6295はMegaVGMPlayer独自実装。 |
| E | ファミコン／NESのAPUと、VRC6・VRC7・FDSなどの拡張音源。NSF・NSFeと一部のNES VGM/VGZに対応。 | NES APUとFDSは [NES_MiSTer](https://github.com/MiSTer-devel/NES_MiSTer/tree/49a0a662e244469ca77b2155746a066df704ffae/rtl) 由来（Kitrinx、FDSはLoopyの調査に基づく）。Sunsoft 5BにはNES_MiSTerとJotego製の [JT49](https://github.com/jotego/jt49) の一部を使用。VRC7はRaki（Sehyeon Kim）の [IKAOPLL](https://github.com/ika-musume/IKAOPLL/tree/15b373be57b52b4e3eb9b99653dabc5095f7a644) がベースで、音色データとデジタル出力の設計はNuke.YKTの [Nuked-SMS-FPGA](https://github.com/nukeykt/Nuked-SMS-FPGA/tree/4d52fb01b15bef693ead7b3b787b55f4202877d5) 由来。 |
| F | PCエンジン／TurboGrafx-16向け。HuC6280 PSG。 | HuC6280 PSGはMegaVGMPlayer独自実装。[MednafenのPCE PSG](https://github.com/libretro/beetle-pce-libretro/blob/b96c11e095b6a40a412d2da02766ae1c3f4fd539/mednafen/hw_sound/pce_psg/pce_psg.cpp) を動作検証に使用。 |
| G | コナミのアーケード向け。YM2151とK053260。 | YM2151はJotego製の [JT51](https://github.com/jotego/jt51)。K053260はMegaVGMPlayer独自実装。 |

[v2.6の対応ソースZIP](https://github.com/dai-VGM/MegaVGMDrive/releases/download/v2.6/MegaVGMPlayer-v2.6-Corresponding-Source.zip) にビルド入力と出典・ライセンス表示を収録しています。

### 画面イメージ

| Browse | Playlists |
| --- | --- |
| ![MegaVGMPlayer v2 Browse画面](docs/images/megavgmplayer-v2-browse.png) | ![MegaVGMPlayer v2 Playlists画面](docs/images/megavgmplayer-v2-playlists.png) |

## ソースと旧バージョン

MegaVGMDriveはMegaVGMPlayerのFPGAコア開発プロジェクトです。[v2.6リリース](https://github.com/dai-VGM/MegaVGMDrive/releases/tag/v2.6) に対応ソース、ビルドに必要なファイル、ライセンス表示を掲載しています。旧版は[リリース一覧](https://github.com/dai-VGM/MegaVGMDrive/releases)から入手できます。

## Development note

このプロジェクトのほぼすべては、プロジェクト所有者の指示のもと、OpenAI CodexおよびGPTによって実装・debugされました。

## Acknowledgements

- [MiSTer-devel/Genesis_MiSTer](https://github.com/MiSTer-devel/Genesis_MiSTer)
- [Jotego jtcores](https://github.com/jotego/jtcores)
- [JTOUTRUN](https://github.com/jotego/jtcores/tree/master/cores/outrun)のSegaPCM実装（旧版と比較試験で使用）
- MiSTer FPGA community、VGM preservation community

## License

MegaVGMDriveにはoriginal codeと、それぞれ固有のlicense条件を持つsource-derived componentが含まれます。詳細はsource headerとrepositoryのprovenance documentを参照してください。
