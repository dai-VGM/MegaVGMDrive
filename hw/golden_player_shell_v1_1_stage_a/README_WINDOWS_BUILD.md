# Golden Player Shell v1.1 Stage A candidate

This is a candidate shell-validation build, not a production release. It
directly reuses the hardware-PASS v1.0 emu, video, title, upload, PLL, pins,
and MiSTer system sources. The only new functional boundary is the versioned
audio ABI, held disabled by the inert Stage A profile.

## Windows Full Compilation

1. Close Quartus and synchronize the complete Mac repository to Windows.
2. Delete only these project-local directories if present:
   - `hw\golden_player_shell_v1_1_stage_a\db`
   - `hw\golden_player_shell_v1_1_stage_a\incremental_db`
   - `hw\golden_player_shell_v1_1_stage_a\output_files`
3. Open `hw\golden_player_shell_v1_1_stage_a\MegaVGMPlayer_GoldenShell_v1_1_StageA_MiSTer.qpf`.
4. Confirm revision `MegaVGMPlayer_GoldenShell_v1_1_StageA_MiSTer`.
5. Run **Processing > Start Compilation** as a Full Compilation.
6. Expected RBF: `hw\golden_player_shell_v1_1_stage_a\output_files\MegaVGMPlayer_GoldenShell_v1_1_StageA_MiSTer.rbf`.

Do not edit QSF or QIP on Windows. Verify v1.0-equivalent video, OSD/Menu,
raw and prepared upload/title, complete silence, software Reset, reload, two
minutes of stability, no signal loss, no freeze, and no power cycle.
