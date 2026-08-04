# Stable emu compatibility mapping

`rtl/emu.sv`は正本の`mister_vgm_md_top` instanceを変更せず保持します。`mister_vgm_md_top_compat.sv`は正本topのparameter/port宣言538行だけを再掲したcompatibility shimで、production実装ロジック5,138行はcopyしていません。

## Active Stage A mapping

| stable emu port | Stage A destination/source | contract |
|---|---|---|
| `clk` | upload/profile `clk` | stable `clk_sys` |
| `reset_n` | local `reset = !reset_n` | stable emu resetのみ |
| `ioctl_download/wr/addr/dout/index` | `golden_player_shell_upload` | index 1 physical write |
| `ioctl_wait` | stable `vgm_ddram_backend.ioctl_wait` | observer/titleはwaitを所有しない |
| `ddram_busy/dout/dout_ready` | stable backend input | MiSTer DDR response |
| `ddram_burstcnt/addr/din/be/we` | stable backend output | base `{4'b0011,25'd0}`、FIFO 256 |
| `ddram_rd` | stable backend output | Stage A profile requestが0なので常時0 |
| `vgm_load_busy/done/error/overflow` | stable backend status | upload/flush/drain status |
| `vgm_load_size/magic` | stable backend debug | physical size/modulo-four observer |
| `audio_l/r` | Stage A profile | signed zero |
| `audio_sample_valid` | Stage A profile | zero |
| `player_busy` | `playback_active` | zero |
| `vgm_player_error` | `profile_fatal` | zero |
| `vgm_mem_rd_*_debug` | profile/backend file-read boundary | request/valid 0 |
| parser/scanner/sound/debug outputs | known zero | no hidden engine/state |

`audio_muted=1`、`audio_gate_open=0`、`startup_done=1`です。release video/title pathはこれらのdebug statusから独立しており、stable `emu`のvideo blobとwiringをそのまま使用します。

Title receiverはstable emu内でioctlをpassive observeするparallel pathです。compatibility shimを通さず、`ioctl_wait`も駆動しません。

## Future plain-port profile boundary

Input候補:

- `clk_sys`、stable shell `reset`
- download begin/endとioctl write metadata
- uploaded physical/body/original size
- stable physical DDR read response interface
- OSD profile controls
- title valid/text（必要なstageのみ）
- shell sample timing

Output候補:

- parser/file read request
- PCM read request A/B
- signed audio L/Rとsample valid
- playback active
- fatal/status
- debug page data

Stage Aはすべてのread request、audio、playback、fatal、parser/scanner/sound counterを0に固定します。
