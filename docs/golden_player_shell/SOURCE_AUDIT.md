# Stage A source and equivalence audit

## Authoritative graph

- QPF/QSF/QIP authority: `VGM_MD_MiSTer.qpf`、`VGM_MD_MiSTer.qsf`、`files.qip`
- stable emu: `rtl/emu.sv`
- title: `rtl/megavgm_title_receiver.sv`、`rtl/megavgm_title_renderer.sv`、`rtl/megavgm_font5x7.sv`
- native video: `rtl/megavgm_video_timing.sv`
- physical upload: `rtl/vgm_ddram_backend.sv`
- system/video/scaler/OSD: `sys/sys.tcl`、`sys/sys.qip`以下
- clock/timing: `rtl/pll.qip`以下、system PLL QIP、`sys/sys_top.sdc`

正本監査対象は現worktreeとstable commitでblob一致しています。個別blob IDとSHA-256は`stable_source_manifest.json`が正本です。

## Golden graph

static audit result:

- source files: 52
- QIP files: 9
- stable shell/system source: 49
- profile-local source: 3
- production `files.qip`から除外したSega/parser/sound source assignment: 74
- duplicate source/module: 0
- absolute path: 0
- DDR read client: 0
- sound device: 0
- parser/scanner: 0

Golden QIPはstable emu/title/video/backendを直接参照し、profile-localのupload adapter、compatibility shim、inert profileだけを追加します。production `mister_vgm_md_top.sv`、JT12/JT51/JTOUTRUN/SegaPCM、current YM2610 player/HW-0、testbenchはproject source graphへ入りません。

## QSF equivalence

Golden QSFはstable QSFをtemplateとして使用します。normalized比較で無視するのはproject-directoryに依存するsource/QIP pathとoutput directoryだけです。device、top、macro、optimization、configurationは完全一致します。

`sys_golden_shell.tcl`はstable `sys/sys.tcl`のbuild-idとsystem-QIP pathだけをproject相対へ変え、generated `jtag.cdf`はproject directoryに維持します。QSFのrelative `SEARCH_PATH`は、unchanged stable emuの`rtl/fixed_region_mode.vh` includeをrepository root基準で解決します。`sys_golden_shell.qip`はstable system sourceを同じ順で参照します。stable `sys/pll_q17.qip`の意味は、Golden directory基準で`../../rtl/pll.qip`と`../../sys/pll_hdmi.qip`、`pll_audio.qip`、`pll_cfg.qip`へ展開します。

## Non-Quartus verification

`tb/golden_player_shell/run_all.sh`は次を実行します。

1. stable/current blob、QSF normalized、QIP path/source、forbidden/duplicate、protected/stash audit
2. stable emu + compatibility shimのIcarus full elaboration
3. Stage A raw/prepared/title/reset/reload/abort/934025-byte/partial flush/120秒相当idle simulation
4. Verilator full emu lint/elaborationと`LATCH`/`MULTIDRIVEN`/`UNOPTFLAT` 0確認
5. stable title/video regressionsとunstaged/staged両方の`git diff --check`

MacではQuartusを実行せず、ALM/resource実測はWindows Stage A compileへ残します。
