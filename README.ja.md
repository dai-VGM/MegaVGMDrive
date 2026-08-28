# MegaVGMDrive / MegaVGMPlayer

MegaVGMPlayerは、MiSTer向けのstandalone FPGA VGM playerです。**MegaVGMDrive**はrepository／FPGA core project、**MegaVGMPlayer**は画面上で動作するplayerの名称です。

[English](README.md) · [YM2151 / SegaPCM v1.0.2 stable release](https://github.com/dai-VGM/MegaVGMDrive/releases/tag/v1.0.2) · [YM2610B Beta release](https://github.com/dai-VGM/MegaVGMDrive/releases/tag/YM2610B-beta1)

> **開発について:** このプロジェクトの実装とデバッグのほぼすべては OpenAI Codex と GPT が行いました。私は実際の音を聴き、Quartus でビルドし、MiSTer実機のデバッグ値や聴感結果を Codex に返す役割を担当しました。

## 使用するeditionを選ぶ

MegaVGMPlayerは、2つの独立したRBF product lineとして配布しています。all-in-one buildではありません。

| Edition | 状態 | 主な音源経路 | Release asset |
| --- | --- | --- | --- |
| YM2151 / SegaPCM | **Stable v1.0.2** | YM2612、SN76489、YM2151、YM2203、SSG、SegaPCM | `MegaVGMDrive_MiSTer_v1.0.2.rbf` |
| YM2610B | **Beta** | YM2610、YM2610B、FM、ADPCM-A、ADPCM-B | `MegaVGMPlayer_YM2610B.rbf` |

Cyclone Vのresource制約から、実用的なuniversal configurationは望ましくないためです。再生したいsystem／音楽に合うRBFを選んでください。一方が他方を置き換える関係ではありません。

## このplayerの特徴

VGMのregister streamをsynthesizable FPGA sound-core HDLへ直接送ります。

```text
VGM data
  -> FPGA VGM parser
  -> FPGA sound-core HDL
  -> FPGA mixer
  -> MiSTer audio output
```

PC上のsoftware synthesizerやOS audio stackを経由せず、音源処理からmixまでFPGA内部で完結します。対応音源のFPGA実装を、standalone MiSTer playerで直接聴くための短い再生経路です。

FPGA実装が自動的に実chipやsoftware emulatorより正確になる、必ず高音質になる、JT coreがoriginal siliconとtransistor levelで同一である、という意味ではありません。

## YM2151 / SegaPCM edition — stable v1.0.2

Download: [MegaVGMPlayer v1.0.2](https://github.com/dai-VGM/MegaVGMDrive/releases/tag/v1.0.2)

このeditionでは、次のproduction経路を同時に有効化しています。

- JT12によるYM2612 FM／DAC
- JT89によるSN76489 PSG
- JT51によるYM2151
- YM2203 FM＋JT49 SSG
- JTOUTRUN / `jtoutrun_pcm`によるSegaPCM

Parserは対応するVGM write（`0x50`、`0x52`、`0x53`、`0x54`、`0x55`、`0xC0`）に加え、これらの再生経路で使うwait、loop、data block、PCM seek、YM2612 DAC stream commandを処理します。YM2203とSegaPCMのclockはVGM headerから読み取り、fractional chip enableへ変換します。

### v1.0.2で修正した内容

**JT51 / YM2151**

- After Burner II「Maximum Power」のstartup buzzを修正しました。
- JT51 reset中のCEN処理を修正し、前曲のJT51 state leakageを解消しました。
- Quartetのstartup、pitch、直前の状態に依存する挙動を修正しました。
- timestamp-zeroの大量YM2151初期化writeによるFantasy Zoneのstartup flam／transientを修正しました。

**SegaPCM**

- repeat boundaryにおけるspeculative read／raw-skid deadlockを修正しました。
- `02 Start BGM`で再現していたPCM dropoutを修正しました。
- 影響を受けていたStrike Fighter trackのPCM再生も改善しました。すべてのStrike Fighter問題が同じ原因だったという主張ではありません。

**VGM import helper**

- ZIP内VGM／VGZ名にliteral wildcard文字（`[ ]`、`*`、`?`）が含まれる場合の処理を修正しました。
- Galaxy Force II、Fantasy Zone II DX、The Ninja Warriorsなどのpackで欠けていたtrackを復元しました。

詳細と検証済みdownloadは[v1.0.2 release](https://github.com/dai-VGM/MegaVGMDrive/releases/tag/v1.0.2)を参照してください。

### Stable editionのOSD

```text
Load VGM
Audio Gain:     Normal / Boost
SegaPCM Audio:  Normal / PCM Only / FM Only
Reset
```

`Audio Gain`はYM2612／SN76489のMega Drive familyへ作用します。`SegaPCM Audio`はarcade mix、FMのみ、PCMのみを選択します。

## YM2610B edition — Beta

Download: [MegaVGMPlayer YM2610B Beta 1](https://github.com/dai-VGM/MegaVGMDrive/releases/tag/YM2610B-beta1)

この独立RBFは次に対応します。

- YM2610／YM2610B再生
- YM2610B 6-channel FM
- 24-bit ADPCM-A addressing
- 24-bit ADPCM-B addressing
- 大規模またはsparseなPCM ROM layout向けのcache／serialized mapping
- Neo Geo VGM compatibility対応の継続作業

実機確認例にはDarius II、Gun Frontier、The Ninja Warriors、Night Striker、Metal Slugのmaterialが含まれます。現在もBetaであり、game／VGM固有のcompatibility issueが残っている可能性があります。

## 使い方

1. 上記のstableまたはBeta releaseから適切なRBFをdownloadします。
2. RBFを使用環境のMiSTer core配置場所へcopyし、loadします。
3. MiSTerのfile pickerから参照できる場所へ、未圧縮またはprepared VGMを置きます。
4. MegaVGMPlayerのOSDを開き、**Load VGM**からfileを選びます。

通常の未加工`.vgm`は直接loadできます。`.vgz`、ZIP archive、標準data layout、画面のtitle metadataにはimport helperを使用してください。

## VGM import helper

Repository内のhelperは[`scripts/vgm_md_import.sh`](scripts/vgm_md_import.sh)です。MiSTerで一般的に使用する設置先は次です。

```text
/media/fat/Scripts/vgm_md_import.sh
```

既定のdata layout:

```text
/media/fat/MegaVGMDrive/inbox/      source file
/media/fat/MegaVGMDrive/vgm_cache/  prepared VGM
```

Helperは次を受け付けます。

- raw `.vgm`
- `.vgz`
- VGMを含むZIP
- VGZを含むZIP

必要なinputを展開し、cache layoutを作成し、source fileを変更せずに`MVGMTTL` title metadataを追加または置換します。繰り返しprepareしてもmetadataを重複追加しません。現在のprepared file上限は128-byte title trailerを含むexactly 8 MiB（`8,388,608` bytes）のままです。

v1.0.2ではZIP entryをliteralに抽出し、space、parentheses、apostrophe、bracket、`*`、`?`を含む名前も安全に処理します。

MiSTerへのinstallと実行:

```sh
cp vgm_md_import.sh /media/fat/Scripts/vgm_md_import.sh
chmod +x /media/fat/Scripts/vgm_md_import.sh
/media/fat/Scripts/vgm_md_import.sh
```

## 曲名表示

Prepared VGMには、親directory名とtrack basenameを格納したMegaVGMPlayer `MVGMTTL` trailerを付加できます。画面上のplayerはtrailerを検証してから2行のtitleを表示します。Trailerがないfileもtitleなしで再生できます。

Binary formatと検証規則は[Prepared VGM metadata](docs/prepared_vgm_metadata.md)を参照してください。

## 現在の制約と将来候補

- MegaVGMPlayerはstandalone VGM playerであり、console／arcade machine本体の完全実装ではありません。
- 各editionの実装範囲外のcommand／deviceはskipされるか、意図どおり再生されない場合があります。
- FPGA内で`.vgz`／`.zip`をnative展開しません。import helperを使用してください。
- Mega CD / RF5C164は、現在のどちらのeditionでも未対応です。
- 32X PWMは、現在のどちらのeditionでも未対応です。
- playlist、previous／next track、autoplay、pause、progress表示は将来候補であり、現在の機能ではありません。

YM2610／YM2610Bは独立したYM2610B Beta RBFで対応しています。YM2151 / SegaPCM RBFには含まれません。

## Buildと実機検証

macOS側のrepository／QSFをsourceの正本とします。ProjectをWindowsへcopyしてQuartus compileし、そのRBFをMiSTer実機で確認してから、確認済みbinaryだけを公開します。Release用Quartus buildはmacOSで行いません。

Stable v1.0.2ではYM2151／JT51のstartup／reload、SegaPCM repeat boundary、複数音源経路、title metadata、代表的なgame musicを確認しました。YM2610B Betaは別系統のhardware／long-run validationを行っており、詳細はBeta release notesに記載しています。これらは代表的な確認例であり、すべてのVGM ripとの互換性を保証するものではありません。

## Repository構成

- `rtl/` — synthesis可能なplayer、音源integration、DDR backend、title、video logic
- `sys/` — MiSTer framework support
- `tb/`、`tests/` — simulation／helper regression
- `scripts/`、`tools/` — import、解析、test utility
- `docs/` — format、provenance、実装note

## 謝辞とupstream project

MegaVGMDriveは[MiSTer FPGA platform](https://github.com/MiSTer-devel/Main_MiSTer)向けに開発しています。次のprojectを利用、またはintegrationの基礎としています。

- [Genesis_MiSTer](https://github.com/MiSTer-devel/Genesis_MiSTer)
- José Tejada Gómez（Jotego）によるJT12、JT89、JT49、JT51、JT10および関連JT core
- JotegoのJTOUTRUN / `jtoutrun_pcm`実装によるSegaPCM

固定したrevisionとlocal integrationについては[Genesis audio provenance](rtl/genesis_audio/README.md)を参照してください。元のcopyright noticeとsource headerは保持しています。

## License

Third-party componentには各upstream licenseが適用されます。同梱の[JT51 license](third_party/jt51/LICENSE)、[JT cores license](third_party/jtcores/LICENSE)、各component README、個別source headerを確認してください。

このrepositoryには独立したtop-level `LICENSE` fileがありません。すべてのfileへ単一licenseが適用されると推測せず、再配布前に対象componentのlicenseとsource noticeを確認してください。
