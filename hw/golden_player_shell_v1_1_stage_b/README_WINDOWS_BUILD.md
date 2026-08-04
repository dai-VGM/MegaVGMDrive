# Golden Player Shell v1.1 Stage B candidate

This project combines the hardware-validated v1.1 shell/audio contract with
the existing hardware-PASS YM2610 Stage B compatibility scanner. The scanner,
single read adapter, shell, and physical upload backend are referenced from
their original sources. No playback parser or sound device is present, and
the v1.1 audio enable remains zero.

## Windows Full Compilation

1. Close Quartus and synchronize the complete Mac repository to Windows.
2. Delete only these project-local directories if present:
   - `hw\golden_player_shell_v1_1_stage_b\db`
   - `hw\golden_player_shell_v1_1_stage_b\incremental_db`
   - `hw\golden_player_shell_v1_1_stage_b\output_files`
3. Open `hw\golden_player_shell_v1_1_stage_b\MegaVGMPlayer_GoldenShell_v1_1_StageB_MiSTer.qpf`.
4. Confirm revision `MegaVGMPlayer_GoldenShell_v1_1_StageB_MiSTer`.
5. Run **Processing > Start Compilation** as a Full Compilation.
6. Expected RBF: `hw\golden_player_shell_v1_1_stage_b\output_files\MegaVGMPlayer_GoldenShell_v1_1_StageB_MiSTer.rbf`.

Do not edit QSF or QIP on Windows. On MiSTer, cold-start the RBF, verify the
v1.1 Stage A video and OSD/Menu, load prepared Olga, verify its title and total
silence, wait two minutes, return to OSD, issue software Reset, reload Olga,
and wait two minutes again. Automatic debug-page changes, fatal state, freeze,
video loss, and a required power cycle are all failures.
