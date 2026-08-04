# YM2610 Golden Shell Stage B Windows build

This project reuses the hardware-proven Golden Shell Stage A source graph and
adds only the versioned profile read adapter and compatibility scanner. It has
no playback parser, sound device, PCM playback client, or register writer.
Silence after a scan is the expected Stage B result.

1. Close Quartus.
2. Synchronize the complete repository to Windows.
3. Delete `hw\ym2610_golden_shell_stage_b\db`, `incremental_db`, and
   `output_files` if they exist.
4. Open
   `hw\ym2610_golden_shell_stage_b\MegaVGMPlayer_YM2610_GoldenShell_StageB_MiSTer.qpf`.
5. Select revision `MegaVGMPlayer_YM2610_GoldenShell_StageB_MiSTer`.
6. Run Full Compilation.
7. Use
   `hw\ym2610_golden_shell_stage_b\output_files\MegaVGMPlayer_YM2610_GoldenShell_StageB_MiSTer.rbf`.
8. Start the RBF on MiSTer without pressing software Reset first.
9. Confirm the same video, OSD/Menu, and title surface as Stage A.
10. Load the prepared Olga VGM, confirm its title and complete silence, then
    leave it idle for at least two minutes.
11. Return to the OSD/Menu, use software Reset, reload Olga, and repeat the
    two-minute check.
12. If practical, also load the raw VGM and one reject fixture. No load should
    cause video loss, automatic debug switching, a freeze, or require a power
    cycle.

Expected result: the scan completes and remains idle; audio stays zero because
playback is deliberately absent in Stage B.
