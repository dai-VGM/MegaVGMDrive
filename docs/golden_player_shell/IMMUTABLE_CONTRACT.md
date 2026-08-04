# Golden Player Shell immutable contract

## Authority

Golden Player Shellの外殻正本はMegaVGMPlayer v1.0.1、commit `5ecce555edb80bdcb010a322ee46ba8837a6ee27`です。production `rtl/emu.sv`は現worktreeでも正本blobと同一であり、Golden projectから直接compileします。copy/fork/編集はしません。

次はStage A以降もimmutableです。

- `rtl/emu.sv`のMiSTer port、`CONF_STR`、HPS/OSD、title receiver/renderer、native video timingとstable reset equation
- `sys/**`のMiSTer top、OSD、scaler、HDMI、analog video、platform audio-output support
- `rtl/pll.qip`以下と`sys/sys_top.sdc`
- `rtl/vgm_ddram_backend.sv`のphysical upload/write、FIFO、partial-word flush、DDRAM base、file-size契約
- production QPF/QSF/QIPと既存YM2610 player/HW-0/JT10/formal source

project-directory差を吸収する`sys_golden_shell.tcl`と`sys_golden_shell.qip`はpath adapterです。assignment/source semantics以外を変えてはいけません。

## Stage A behavior

- raw/prepared VGMのindex 1 uploadをstable DDR backendへ渡す
- prepared `MVGMTTL`はstable passive title observerが検証し、Directory/Basenameをatomic publishする
- upload完了後はFIFO empty、partial word flush済み、write outstanding 0、DDRAM request deassertで静止する
- parser start 0、scanner start 0、file/PCM DDR read request 0、sound write 0
- audio L/R 0、audio sample valid 0、playback active 0、fatal 0
- stable emu以外のPOR/reset fenceを追加しない
- Stage A独自video marker、debug自動切替、descriptor scan、read arbiterを追加しない

`vgm_ddram_backend.magic_debug`は先頭magicをlatched保持するsignalではなく、address modulo 4ごとの最終write byte observerです。この正本挙動は変更しません。

## Change boundary

将来profileは`ym2610_golden_stage_a`と置換します。stable emu、title/video、upload backend、QSF non-source assignmentを変更して機能を足してはいけません。Stage B以降でread clientを解禁するときは、request/owner/response contractを段階ごとに明示し、前段の0-request回帰を残します。

Stage AのWindows Full Compilationと実機試験がPASSするまでStage Bへ進みません。
