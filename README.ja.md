# MegaVGMDrive

MiSTer FPGA向けの単体VGMプレイヤーコア

English README: [README.md](README.md)

MegaVGMDrive は、MiSTer FPGA 上で VGM command stream を再生するための実験的な core です。現在は Mega Drive / Genesis 系 VGM を主な対象に、JT12/YM2612 互換の FM 音源 path と PSG を組み合わせて再生します。

ゲーム本体を動かす console core ではありません。VGM data をロードし、register write と wait timing を再生して、単体の VGM player として音源を駆動します。

## プロジェクト概要

- MiSTer FPGA 上での VGM 再生 core
- YM2612/JT12 FM と PSG の音源構成
- MODE5 OSD file loading path
- DDRAM-backed VGM storage
- 非圧縮 `.vgm` 再生を主対象
- `.zip` / `.vgz` / `.vgm` 準備用 importer script

## Current Status

現在の gold 状態では、MODE5 loader と DDRAM backend を使った VGM 再生が安定しています。

- DDRAM backend stable
- 4 MiB+ VGM playback verified
- 1.1 MB、3.9 MB、4.3 MB 級 VGM の実機 MiSTer 再生を確認済み
- MiSTer OSD 経由の MODE5 file loading
- cache 用 `.vgm` を準備する importer available
- `ioctl_wait` / `play_ready` によるロード完了待ちを実装済み
- DDRAM address window は MiSTer 慣例に寄せた `0x30000000` 系
- PSG clock は Mega Drive 相当の 3.579545 MHz

## Audio Gold

現在の preferred audio configuration:

- `audio-gold-no-uprate-psgfix`
- FM/PCM は `jt12_fm_uprate` interpolation chain を bypass
- PSG preserved
- PSG level 0.75
- LPF disabled by default

この構成では PSG path を残しつつ、VGM player path の FM/PCM については Genesis core 向けの interpolation chain を通さない構成にしています。現在の検証では、確認済み VGM の再生においてこの path がよりクリーンな結果になっています。

Validation examples:

- Hang-On
- Thunder Force IV
- Streets of Rage
- Gunstar Heroes

## VGM Import Workflow

core が直接ロードする対象は非圧縮 `.vgm` です。`.vgz` や `.zip` は FPGA 内で展開せず、再生前に準備します。

`scripts/vgm_md_import.sh` は、MODE5 OSD loader で読み込める `.vgm` cache を作るための importer です。通常の `.vgm` はコピーし、`.vgz` は `gzip` で展開し、`.zip` 内の `.vgm` / `.vgz` entry も取り出します。

```sh
scripts/vgm_md_import.sh [SRC] [DST_DIR]
```

実行例:

```sh
scripts/vgm_md_import.sh /path/Hang-On ./vgm_cache
scripts/vgm_md_import.sh "/path/Thunder Force IV.zip" ./vgm_cache
scripts/vgm_md_import.sh /path/song.vgm ./vgm_cache
```

MiSTer 側の default path:

```text
SRC=/media/fat/games/MegaVGMDrive/inbox
DST_DIR=/media/fat/games/MegaVGMDrive/vgm_cache
```

典型的な Samba workflow:

```text
\\mister\sdcard\games\MegaVGMDrive\inbox
\\mister\sdcard\games\MegaVGMDrive\vgm_cache
```

importer は `vgm_cache` 直下に全ファイルを置かず、collection ごとの subdirectory に出力します。

入力と出力の例:

```text
Input:  /path/Hang-On/
Output: vgm_cache/Hang-On/*.vgm

Input:  /path/Thunder Force IV.zip
Output: vgm_cache/Thunder Force IV/*.vgm

Input:  /path/song.vgm
Output: vgm_cache/song/song.vgm
```

import 後は、生成された `vgm_cache/<collection>/...` を MiSTer SD card へコピーします。たとえば `/media/fat/games/MegaVGMDrive/vgm_cache` 配下に置き、MiSTer で MegaVGMDrive を起動して、OSD の `Load VGM` から import 済み `.vgm` を選択します。

## MiSTer での使い方

MegaVGMDrive の RBF は `/media/fat/_Computer/`、またはこの project で使っている MiSTer core folder に配置します。

VGM file は以下に配置します。

```text
/media/fat/games/MegaVGMDrive/
```

例:

```text
/media/fat/games/MegaVGMDrive/YM2151_SMOKE.VGM
```

現在の安全側 OSD loader entry は `F1,VGM,Load VGM;` です。MiSTer 側の file filter が大小文字を区別する環境では、拡張子は `.VGM` のように大文字にしてください。

### YM2151/JT51 Smoke Test

YM2151/JT51 playback は実験段階です。YM2151 test RBF を作る場合は、以下の macro を有効にします。

```tcl
set_global_assignment -name VERILOG_MACRO "MEGAVGMDRIVE_YM2151_MODE_TEST=1"
```

合成・自作の非商用 smoke VGM は次のコマンドで生成できます。

```sh
python3 tools/generate_ym2151_smoke_vgm.py
```

default では以下に出力します。

```text
testdata/YM2151_SMOKE.VGM
```

MiSTer SD card には以下としてコピーします。

```text
/media/fat/games/MegaVGMDrive/YM2151_SMOKE.VGM
```

YM2151 test build で OSD の `Load VGM` から読み込むと、`pi-po` 風の smoke tone がループします。

## Repository Layout

- `rtl/` - synthesis 対象 RTL、VGM loader/player logic、DDRAM backend、audio integration
- `sys/` - MiSTer framework support modules
- `tb/` - loader、player、timing、mode behavior 用 SystemVerilog testbench
- `tools/` - test / bring-up data 用 VGM 生成・抽出 helper
- `scripts/` - MiSTer 側および host 側 utility script
- `docs/` - bring-up note、audio note、backend plan
- `testdata/` - 小さな VGM probe と生成 test input

## 注意

- 現在の主対象は Mega Drive / Genesis 系 VGM です。
- YM2151/JT51 playback は実験段階で、debug build で `MEGAVGMDRIVE_YM2151_MODE_TEST=1` を有効にした場合のみ使います。
- FPGA 内 native `.vgz` gzip 展開は未実装です。
- 大きな VGM の再生は DDRAM-backed MODE5 path を使います。
- Quartus build は Windows 環境で行う想定です。
- この project では通常、macOS 側で Quartus compile / TimeQuest 確認は行いません。

## Gold Checkpoint

```text
tag: audio-gold-no-uprate-psgfix
commit: 91193848fa85e8f2e7964628a5f792890dac4300
```

この checkpoint は、FM/PCM の `jt12_fm_uprate` bypass と PSG 復活済み path を保存したものです。

## クレジット

本プロジェクトは MiSTer FPGA プラットフォーム向けに開発されています。

本プロジェクトでは、以下のオープンソースプロジェクトおよび成果物を利用・参考にしています。

- MiSTer FPGA project
- Genesis_MiSTer project
- JT12 FM core by Jose Tejada Gomez (Jotego)
- JT51 FM core by Jose Tejada Gomez (Jotego)

JT12 と JT51 は元のオープンソースライセンスに従って利用しています。
第三者コードに含まれる著作権表示およびライセンスヘッダは保持しています。

本リポジトリには独自実装に加え、上記プロジェクトを基にした統合・改変が含まれます。

リンク:
- https://github.com/MiSTer-devel/Main_MiSTer
- https://github.com/MiSTer-devel/Genesis_MiSTer
- https://github.com/jotego/jt12
- https://github.com/jotego/jt51
