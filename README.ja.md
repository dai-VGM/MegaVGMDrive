# MegaVGMDrive

MiSTer FPGA向けのハードウェアVGMプレイヤーコア

English README: [README.md](README.md)

MegaVGMDriveは、VGM command streamをDDRAMへロードし、FPGA上の音源coreで直接再生します。ゲーム機本体を再現するconsole coreではなく、単体のmusic playerです。公開production buildでは、対応済みのMega Drive系音源とarcade系音源を同時に有効化し、複数音源を含むVGMを1つのbuildで再生できます。

> **Development note:** Almost all of this project was built by OpenAI Codex. I mainly listened to the sound, reported the debug numbers, compiled the FPGA build, and tested it on real hardware.

## 現行リリース

現在の実機確認済みreleaseは、[MegaVGMDrive – YM2203 and SegaPCM Release](https://github.com/dai-VGM/MegaVGMDrive/releases/tag/audio-gold-ym2203-segapcm)です。

| 項目 | 値 |
| --- | --- |
| Tag | `audio-gold-ym2203-segapcm` |
| Source checkpoint | `23763eab487d3eeea7430047d4785c45839c1b56` |
| 実機確認済みRBF | `MegaVGMdrive_MiSTer_20260723.rbf` |
| Build環境 | Windows上のQuartus |

このreleaseでは、YM2203/JT49とSegaPCMをproduction経路へ追加し、YM2612/PSGとの同時動作を復旧しました。Mega Drive familyとarcade familyの公開音量は、familyごとに独立して正規化しています。

## 主な機能

- MODE5 OSDからの非圧縮`.vgm`ロード
- DDRAM-backed VGM storage
- 下記全音源のproduction同時動作
- VGM headerに追従するYM2203／SegaPCM clock
- header clockからのfractional clock-enable生成
- busyを待つYM2203 register transport
- 通常DDR経路を使うSegaPCM再生
- Mega Drive familyとarcade familyの独立audio normalization
- signed拡張した最終加算と16-bit saturation
- `.vgm`、`.vgz`、`.zip`準備用のhost／MiSTer importer

## 対応音源

| 音源 | 実装 | Production状態 |
| --- | --- | --- |
| YM2612 | JT12ベースのFM／DAC経路 | 有効 |
| SN76489 PSG | JT89ベースのPSG経路 | 有効 |
| YM2151 | JT51 | 有効 |
| YM2203 FM | JT12/JT03互換の3-channel構成 | 有効 |
| YM2203 SSG | JT49 | 有効 |
| SegaPCM | 通常DDR経路を使うJT系core | 有効 |

公開releaseでは、上記音源を同時に有効化します。新規chipのbring-up中は開発buildで完成済み音源を一時的に無効化する場合がありますが、release buildではlab専用audio stubを使用しません。

## 実装済みVGM command

Production parserは、次の音源writeを実装しています。

| Command | 処理 |
| --- | --- |
| `0x50 dd` | SN76489 PSG write |
| `0x52 aa dd` | YM2612 port 0 write |
| `0x53 aa dd` | YM2612 port 1 write |
| `0x54 aa dd` | YM2151 write |
| `0x55 aa dd` | YM2203 write |
| `0xC0 ll hh dd` | 16-bit addressへのSegaPCM write |

また、対応済み再生経路で使うwait、end／loop、data block、PCM seek、YM2612 DAC stream commandも実装しています。主な対象は`0x61`–`0x63`、`0x66`、`0x67`、`0x70`–`0x7F`、`0x80`–`0x8F`、`0xE0`です。

YM2203はVGM headerの`0x44`–`0x47`をchip clockとして使います。SegaPCMは`0x38`–`0x3B`のclockと`0x3C`–`0x3F`のinterface fieldを読み取ります。これらのheader値からfractional accumulatorで必要なenableを生成します。YM2203 FMの`/6`とSSGの`/4`はJT12/JT49内部で処理するため、testbenchやtop側では追加分周しません。

## インストールと使い方

1. [現行release](https://github.com/dai-VGM/MegaVGMDrive/releases/tag/audio-gold-ym2203-segapcm)から実機確認済みRBFをdownloadします。
2. RBFを各環境で使用しているMiSTer core folderへコピーします。
3. 非圧縮`.vgm`をMiSTerのfile pickerから参照できる場所へコピーします。
4. MegaVGMDriveを起動し、OSDの**Load VGM**からファイルを選択します。

FPGA loaderは`.vgz`や`.zip`を展開しません。任意の[VGM import helper](scripts/vgm_md_import.sh)を使うと、`.vgm`のcopyと、`.vgz`または対応archive entryの展開を再生前に行えます。

```sh
scripts/vgm_md_import.sh [SRC] [DST_DIR]
```

MiSTer側のdefaultは次のとおりです。

```text
SRC=/media/fat/VGM_MD/inbox
DST_DIR=/media/fat/VGM_MD/vgm_cache
```

出力先は各SD cardのlayoutに合わせて変更できます。

## 公開版OSD

通常のrelease buildで表示する項目は次の4つです。

```text
Load VGM
Audio Gain:     Normal / Boost
SegaPCM Audio:  Normal / PCM Only / FM Only
Reset
```

- **Audio Gain**はMega Drive family（YM2612＋SN76489 PSG）だけに作用します。`Normal`はhistorical levelを維持し、`Boost`は既存のMD family 2倍gainを適用します。
- **SegaPCM Audio**はarcade familyのcontributionを選択します。`Normal`はFMとPCMをmixし、`PCM Only`はFM laneをmute、`FM Only`はSegaPCMをmuteします。
- Release buildでは、非表示のSegaPCM Feedを**Hold**、Polarityを**Normal**（`sample_byte - 128`）へ固定します。
- Bring-up用controlとdebug overlayはdevelopment buildでのみ使用できます。

## Audio構成

Productionの公開出力は、独立して正規化した2つのfamilyから構成します。

```text
YM2612 + SN76489 PSG
  -> historical MD postmix/gain profile
  -> signed MD lane

YM2151/JT51 + YM2203/JT49 + SegaPCM
  -> arcade mixerとsaturation
  -> 既存arcade公開level（arithmetic >>> 2）
  -> signed arcade lane

MD lane + arcade lane
  -> signed拡張加算
  -> 16-bit saturation
  -> public stereo output
```

Mega Drive familyは、従来のPSG balance、no-uprate postmix path、MD専用Audio Gainを含むhistorical audio profileを維持します。Arcade familyも確認済みの公開levelを維持します。YM2203 FMはYM2203 branch内で4倍してからSSGとmixし、他音源を変更せずに実機確認済みのFM／SSG balanceを保ちます。

## 実機検証

Release RBFはWindowsでbuildし、MiSTer-compatible hardwareで確認しています。主な確認内容は次のとおりです。

- YM2612 FM、SN76489 PSG、YM2612 DAC再生
- `Audio Gain`の`Normal`／`Boost`
- YM2151/JT51再生
- YM2203 FMとJT49 SSG再生
- 通常DDR経路のSegaPCM再生
- `Normal`／`FM Only`／`PCM Only`
- Mega Drive familyとarcade familyの同時出力

実機確認にはSpace Harrier、Fantasy Zone、After Burner、OutRun系の素材を含みます。これは確認した経路を示すもので、すべてのVGM ripとの互換性を保証するものではありません。

Release bring-upではIcarus simulationとVerilator lint／regressionを使用しました。macOSではQuartus buildを行っていません。Release添付assetはWindows build・実機確認済みのbinaryです。

## Known Issues

- 新しいRBFをloadした直後、最初の“Maximum Power”再生にbuzzing artifactが乗る場合があります。
- Quartetを含む一部の初期YM2151 VGMは、load条件によって音の差が出る場合があります。現在も調査中です。
- Mega CD / RF5C164は未対応です。
- 32X PWMは未対応です。

## その他の制約

- MegaVGMDriveは単体VGM playerであり、Mega Drive、System 16、System 18本体の完全実装ではありません。
- FPGA内でのnative `.vgz`／`.zip`展開は未実装です。
- 実装範囲外のcommandやdeviceを使うfileは、該当commandがskipされるか、意図どおり再生されない場合があります。

## Build workflow

macOS側checkoutをsource treeとQSFの正本とします。Release workflowは次のとおりです。

1. Sourceとproject fileをmacOS側で変更します。
2. 正本の[`VGM_MD_MiSTer.qsf`](VGM_MD_MiSTer.qsf)を含むprojectをWindows build環境へcopyします。
3. Windows上のQuartusでRBFをcompileします。
4. Windows build RBFをMiSTer-compatible hardwareへcopyし、実機確認します。
5. 実機確認したbuildと一致するbinaryだけを公開します。

Windows側で別系統のQSFを編集・維持せず、macOS Quartus buildをrelease binaryとして使用しません。

## Repository layout

- `rtl/` — synthesis対象RTL、VGM parser/player、DDR backend、audio integration
- `sys/` — MiSTer framework support
- `tb/` — SystemVerilog testbench
- `scripts/` — regression／import helper
- `tools/` — VGM解析／test生成utility
- `testdata/` — synthetic／extracted regression input
- `docs/` — bring-up／実装note

## クレジット

MegaVGMDriveは[MiSTer FPGA platform](https://github.com/MiSTer-devel/Main_MiSTer)向けに開発しています。次のprojectを利用、またはintegrationの基礎としています。

- [Genesis_MiSTer](https://github.com/MiSTer-devel/Genesis_MiSTer)
- José Tejada Gómez（Jotego）による[JT12](https://github.com/jotego/jt12)、[JT49](https://github.com/jotego/jt49)、[JT51](https://github.com/jotego/jt51)および関連JT core
- Jotegoの対応arcade core実装を基にしたJT SegaPCM

固定したsource revisionとlocal integrationについては[Genesis audio provenance](rtl/genesis_audio/README.md)を参照してください。元のcopyright noticeとsource headerは保持しています。

## ライセンス

Third-party componentには各upstream licenseが適用されます。同梱の[JT51 license](third_party/jt51/LICENSE)、[JT cores license](third_party/jtcores/LICENSE)、各component README、個別source headerを確認してください。

このrepositoryには現在、独立したtop-level `LICENSE` fileがありません。すべてのfileへ単一licenseが適用されると推測せず、再配布前に対象componentのlicenseとsource noticeを確認してください。
