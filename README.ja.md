# MegaVGMDrive

MiSTer FPGA向けのハードウェアVGMプレイヤーコア

English README: [README.md](README.md)

MegaVGMDriveは、VGM command streamをDDRAMへロードし、FPGA上の音源coreで直接再生します。Sega Mega Drive / Genesisのゲームや、対応済みSega arcade systemのVGMを再生できます。ゲーム機本体を再現するconsole coreではなく、単体のmusic playerです。公開production buildでは、対応済みのMega Drive系音源とarcade系音源を同時に有効化し、複数音源を含むVGMを1つのbuildで再生できます。

> **開発メモ:** このプロジェクトの実装とデバッグは、ほぼすべてOpenAI CodexとGPTが行いました。私は音を聴き、Quartusでビルドし、デバッグ値をCodexへ返しただけです。

## MegaVGMPlayer v1.0

**MegaVGMDrive**はrepositoryおよびMiSTer FPGA core projectの名称です。**MegaVGMPlayer**は画面上で動作するstandalone VGM playerの名称です。**v1.0**を最初のstable production releaseとします。

| 項目 | 値 |
| --- | --- |
| Tag | `v1.0` |
| Release RTL checkpoint | `85d1cac1aa5781e5169762f3858099e65b2c8767` |
| 実機確認済みRBF | `MegaVGMDrive_MiSTer_v1.0.rbf` |
| Build環境 | Windows上のQuartus |

このreleaseは、実機確認済みaudio経路、MiSTer Template準拠native video、prepared fileの曲名表示を統合します。通常の未加工`.vgm`も従来どおり再生でき、有効なMegaVGMDrive metadata trailerがある場合だけ曲情報を表示します。

## 参考FPGA build status

2026-07-23の実機確認済みproduction buildにおけるQuartus結果は次のとおりでした。

| 項目 | 値 |
| --- | --- |
| Flow Status | Successful |
| Build time | Thu Jul 23 11:04:36 2026 |
| Quartus Prime Version | 17.0.0 Build 595 04/25/2017 SJ Lite Edition |
| Revision | `VGM_MD_MiSTer` |
| Top-level entity | `sys_top` |
| Family | Cyclone V |
| Device | `5CSEBA6U23I7` |
| Timing Models | Final |
| Logic utilization | 32,614 / 41,910 ALMs (78%) |
| Total registers | 54,435 |
| Total pins | 145 / 314 (46%) |
| Total block memory bits | 372,593 / 5,662,720 (7%) |
| Total DSP Blocks | 37 / 112 (33%) |
| Total PLLs | 3 / 6 (50%) |

現在もっとも厳しいresourceはlogic utilizationであり、block memoryとDSPにはまだ余裕があります。

その後のv1.0 production buildでは、通常合成からaudio観測専用accumulatorとkeep付きcounterを除外し、Quartusで測定したALM使用率を約1 percentage point削減しました。v1.0 assetは、その後Windowsでbuildして実機確認したRBFです。macOSではQuartusを実行していません。

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
- HDMI、analog、Direct Video経路へ渡すMiSTer Template準拠native video
- 検証済み`MVGMTTL` metadataからの親directory名＋basename表示
- raw `.vgm`、`.vgz`、ZIP内VGM、ZIP内VGZに対応するhost／MiSTer importer

## 対応音源とJT core

| 音源 | Production実装 | 状態 |
| --- | --- | --- |
| YM2612 | Jotego JT12 FM／DAC経路 | 有効 |
| SN76489 / PSG | Jotego JT89 | 有効 |
| YM2151 | Jotego JT51 | 有効 |
| YM2203 | Jotego JT12 OPN FM＋JT49 SSG | 有効 |
| SegaPCM | Jotego JTOUTRUN / `jtoutrun_pcm`、通常DDR経路 | 有効 |

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

1. [v1.0 release](https://github.com/dai-VGM/MegaVGMDrive/releases/tag/v1.0)から実機確認済みRBFをdownloadします。
2. RBFを各環境で使用しているMiSTer core folderへコピーします。
3. 非圧縮`.vgm`をMiSTerのfile pickerから参照できる場所へコピーします。
4. MegaVGMDriveを起動し、MegaVGMPlayerのOSDで**Load VGM**からfileを選択します。

通常の未加工`.vgm`はそのまま再生できます。画面へdirectory名とbasenameを表示したい場合だけhelperでprepared copyを生成してください。

## `vgm_md_import.sh`の設置

Script本体とVGM dataは別directoryへ置きます。Releaseに含まれるhelperをMiSTer標準のScripts directoryへcopyします。

```sh
cp vgm_md_import.sh /media/fat/Scripts/vgm_md_import.sh
chmod +x /media/fat/Scripts/vgm_md_import.sh
```

既定の全体構成は次のとおりです。

```text
/media/fat/
├── Scripts/
│   └── vgm_md_import.sh
└── MegaVGMDrive/
    ├── inbox/
    └── vgm_cache/
```

Helper内部では次のdata directoryを既定値として使います。

```sh
ROOT=/media/fat/MegaVGMDrive
SRC="$ROOT/inbox"
DST_DIR="$ROOT/vgm_cache"
```

VGM fileまたはalbum directoryを`/media/fat/MegaVGMDrive/inbox/`へ置き、MiSTerのScripts menuから`vgm_md_import`を実行します。Shellから直接実行する場合は次を使用します。

```sh
/media/fat/Scripts/vgm_md_import.sh
```

Prepared VGMは`/media/fat/MegaVGMDrive/vgm_cache/`以下へ生成されます。MegaVGMPlayerのOSDからこのfileをloadしてください。

## VGM fileの準備

FPGA loader自体は`.vgz`や`.zip`を展開しません。Helperは次のinputを処理できます。

- 解凍済みraw `.vgm`
- `.vgz`
- VGMを含むZIP
- VGZを含むZIP

Raw `.vgm`はVGZやZIPへ再圧縮せず、そのまま`inbox`へ置けます。例:

```text
/media/fat/MegaVGMDrive/inbox/
└── Super Hang-On/
    └── 03 - Sprinter.vgm
```

Helperは次を生成します。

```text
/media/fat/MegaVGMDrive/vgm_cache/
└── Super Hang-On/
    └── 03 - Sprinter.vgm
```

MegaVGMPlayerの表示:

```text
Super Hang-On
03 - Sprinter
```

直上の親directory名を上段、最後の拡張子を除いたVGM basenameを下段へ表示します。Spaceとunderscoreは保持します。`inbox`側のsourceは変更せず、`vgm_cache`へprepared copyを作成し、必要なdestination directoryも自動作成します。二重実行してもmetadataを重複追加しません。既存の有効なtrailerは、現在のmetadataへ安全に置換します。

## 曲名表示と`MVGMTTL`

Prepared VGMの物理末尾には、MegaVGMDrive専用128-byte `MVGMTTL` trailerを追加します。Directory fieldは最大32文字、basename fieldは最大48文字です。

Helperは4 MiBを超えるVGM bodyにも対応します。現在のMegaVGMDrive production 23-bit byte-address契約では、prepared physical fileの最大値は128-byte `MVGMTTL` trailerを含むexactly 8 MiB（`8,388,608` bytes）です。したがってhelperが受け付けるoriginal VGM bodyの最大値は`8,388,480` bytesです。通常の未加工VGM再生との互換性は変わりません。

Helperはprintable ASCII `0x20`–`0x7E`を保持し、有効な非ASCII UTF-8 code point 1個を`?` 1個へ変換します。不正UTF-8 byteも安全に`?`へ変換し、変換後のdirectory／basenameを固定field長でtruncateします。FPGA fontが対応するのはprintable ASCIIだけで、任意のUnicode文字をそのまま表示することはできません。

FPGA receiverは`ioctl_index=1`のVGM downloadを受動監視し、playback、DDR、parserをstallしません。末尾128 bytesの`MVGMTTL` magic、version、flags、trailer／original size、文字列長、reserved fieldを検証し、全検証完了後だけmetadataをatomic publishします。新しいload開始時に以前のtitleをclearします。Metadataがないfile、不正trailer、中断downloadではdirectory／basenameを表示しませんが、通常VGM dataは従来どおり再生できます。

2行のmetadataは、中央配置した320×240の紺背景（`RGB 24'h000818`）上へ表示します。固定`MegaVGMPlayer` heading、青いborder、outlineは描画しません。

## 15kHz／native video

MegaVGMPlayer v1.0はMiSTer Template準拠native timingを使用します。既存20 MHz system clockと10 MHz pixel-enable cadenceを使用し、水平約15.674 kHz、垂直約59.824 Hzを生成します。

同じnative RGB画面をMiSTerのHDMI、Analog RGB、YPbPr、CRT、Direct Video経路へ渡します。Template active area中央の320×240紺背景にはdirectoryとbasenameだけを表示します。外部ユーザー環境で15kHz CRT動作を確認済みですが、すべてのCRT／displayとの互換を保証するものではありません。

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
- Prepared `MVGMTTL` directory／basename表示
- HDMI表示と外部確認済み15kHz CRT出力

実機再生を確認した例:

- After Burner
- Out Run
- Galaxy Force II
- Thunder Blade
- Power Drift
- Space Harrier
- 複数のSega Mega Drive / Genesis title

これらは実機確認例であり、全titleへの対応や、すべてのVGM ripとの互換性を保証するものではありません。

Release bring-upではIcarus simulationとVerilator lint／regressionを使用しました。macOSではQuartus buildを行っていません。Release添付assetはWindows build・実機確認済みのbinaryです。

## Known Issues

- **After Burner II — Maximum Power:** RBF起動後の最初の再生など、特定条件でnoiseが乗る場合があります。
- **Quartet:** 既知の再生互換問題が残っています。

## その他の制約

- MegaVGMDriveは単体VGM playerであり、Mega Drive、System 16、System 18本体の完全実装ではありません。
- FPGA内でのnative `.vgz`／`.zip`展開は未実装です。
- 実装範囲外のcommandやdeviceを使うfileは、該当commandがskipされるか、意図どおり再生されない場合があります。
- Mega CD / RF5C164、32X PWM、YM2610Bは未対応です。
- `.mvgmpack`、next／previous track、autoplay、pause、progress表示はv1.0では未実装です。

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
- José Tejada Gómez（Jotego）による[JT12](https://github.com/jotego/jt12)、JT89、[JT49](https://github.com/jotego/jt49)、[JT51](https://github.com/jotego/jt51)および関連JT core
- JotegoのJTOUTRUN / `jtoutrun_pcm`実装によるSegaPCM

固定したsource revisionとlocal integrationについては[Genesis audio provenance](rtl/genesis_audio/README.md)を参照してください。元のcopyright noticeとsource headerは保持しています。

## ライセンス

Third-party componentには各upstream licenseが適用されます。同梱の[JT51 license](third_party/jt51/LICENSE)、[JT cores license](third_party/jtcores/LICENSE)、各component README、個別source headerを確認してください。

このrepositoryには現在、独立したtop-level `LICENSE` fileがありません。すべてのfileへ単一licenseが適用されると推測せず、再配布前に対象componentのlicenseとsource noticeを確認してください。
