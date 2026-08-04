# Golden Player Shell v1.1 Stage C candidate

This project combines the hardware-PASS Golden Player Shell v1.1 boundary and
Stage B scan path with the immutable existing Stage C parser and FM/SSG sound
path. ADPCM writes are trace-visible but suppressed; there is no PCM DDR
client. Hardware validation is still pending.

## Windows Full Compilation

1. Close Quartus and synchronize the complete Mac repository to Windows.
2. Delete only these project-local directories if present:
   - `hw\golden_player_shell_v1_1_stage_c\db`
   - `hw\golden_player_shell_v1_1_stage_c\incremental_db`
   - `hw\golden_player_shell_v1_1_stage_c\output_files`
3. Open `hw\golden_player_shell_v1_1_stage_c\MegaVGMPlayer_GoldenShell_v1_1_StageC_MiSTer.qpf`.
4. Confirm revision `MegaVGMPlayer_GoldenShell_v1_1_StageC_MiSTer`.
5. Run **Processing > Start Compilation** as a Full Compilation.
6. Expected RBF: `hw\golden_player_shell_v1_1_stage_c\output_files\MegaVGMPlayer_GoldenShell_v1_1_StageC_MiSTer.rbf`.

Do not edit QSF or QIP on Windows. Cold-start the RBF on MiSTer, confirm the
same video/title/OSD behavior as v1.1 Stage A/B, then load prepared Olga.
Expect silence until about 2.74 seconds after playback begins, FM-only audio
afterward, no PCM-like sound, and a loop after about 3 minutes 10 seconds.
Complete the 30-second, two-minute, OSD return, software Reset, reload, and
synthetic SSG A/B/C checks in the hardware report. Any automatic debug page,
fatal, freeze, video loss, or required power cycle is a failure.
