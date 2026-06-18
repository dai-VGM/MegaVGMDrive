# MiSTer VGM Player Core

MiSTer VGM Player Core は、MiSTer FPGA 上で VGM を再生するための実験的な core です。

現状は Mega Drive / Genesis 系の VGM を中心に、YM2612/YM3438 互換の JT12 FM 音源と PSG/JT89 系の音源を FPGA 上で駆動して鳴らすことを目的にしています。ゲーム本体を動かす core ではなく、VGM のコマンド列を読み込み、音源レジスタ write と wait timing を再現する VGM プレイヤーです。

## 現在の到達点

現在の gold checkpoint では、Mode 5 の DDRAM backend を使った大きめの VGM 再生が安定しています。

- DDRAM 4MB+ / `addr23` 構成で安定確認
- 1.1MB 級、3.9MB 級、4.3MB 級の VGM 再生を実機 MiSTer で確認
- `ioctl_wait` / `play_ready` によるロード完了待ちを実装
- DDRAM address window は MiSTer 慣例に寄せた `0x30000000` 系
- PSG clock を Mega Drive 相当の 3.579545MHz に修正
- PSG level は現状 Low 相当、約 0.75x を標準評価
- Audio gold: `NO_UPRATE + PSG fix`

音質評価済みの代表例:

- Hang-On: リードのノイズ解消
- Thunder Force IV: ギター / アルペジオ良好
- Go Straight: 良好
- Gunstar Heroes: 良好
- 全体として foobar2000 VGM plugin に近いクリーンな傾向

## 音質 gold について

現在の音質 gold は、Genesis 用の `jt12_fm_uprate` / interpolation chain を FM/PCM 側では使わない構成です。

JT12 由来の `jt12_fm_uprate` は、Genesis core の master clock / clock enable 構成で FM と PSG を高速な内部 sample stream へ補間するための処理です。一方、この VGM player では VGM wait timing に従って音源を駆動するため、FM/PCM をその補間 chain に通すより、JT12 出力をより直接扱う方が良好な結果になりました。

gold 状態の要点:

- `MD_AUDIO_GENMIX_NO_UPRATE_TEST=1`
- FM/PCM は `jt12_fm_uprate` / interpolation bypass
- PSG は消さずに残す
- LPF なし
- ladder なし
- feedback 制限なし
- saturate 系 test なし
- PMS/AMS mask なし

この構成で Hang-On、Thunder Force IV、Go Straight、Gunstar Heroes などを確認し、現時点の音質基準としています。

## 注意

このプロジェクトは実験的な MiSTer core です。

- すべての VGM の完全再生を保証するものではありません。
- 現状の主な対象は Mega Drive / Genesis 系 VGM です。
- `.vgz` の FPGA 内 native 展開には対応していません。
- `.vgz` は事前に `.vgm` へ展開して使う想定です。
- Quartus build は Windows 環境で行う想定です。
- Mac 側では通常、Quartus compile / TimeQuest 確認は行いません。

## ビルドと配置

1. Windows 側で Quartus project を開き、通常手順で compile します。
2. `.sof` 生成後、`quartus_cpf` などで `.rbf` を生成します。
3. 生成した `.rbf` を MiSTer の `/media/fat/_Console/` など、利用する core 配置先へコピーします。
4. MiSTer の OSD から core を起動します。
5. VGM file は OSD file load から読み込みます。

gold checkpoint 用の RBF 名候補:

```text
VGM_MD_audio_gold_no_uprate_psgfix.rbf
```

## VGM / VGZ の準備

VGM は非圧縮 `.vgm` をロード対象にします。

`.vgz` を使う場合は、事前に展開して `.vgm` にしてください。補助スクリプトとして、`scripts/vgz_to_vgm_cache.sh` や `scripts/vgm_md_import.sh` を用意しています。

想定運用例:

```text
\\mister\sdcard\VGM_MD\inbox
```

へ `.zip` / `.vgz` / `.vgm` を入れ、MiSTer 側で importer script を実行して、

```text
\\mister\sdcard\VGM_MD\vgm_cache
```

に展開済み `.vgm` を作る運用です。

## 現在の gold checkpoint

```text
tag: audio-gold-no-uprate-psgfix
commit: 91193848fa85e8f2e7964628a5f792890dac4300
```

この checkpoint は、FM/PCM の `jt12_fm_uprate` bypass と PSG 復活済み path を保存したものです。
