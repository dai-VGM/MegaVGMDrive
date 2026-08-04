# Golden Player Shell v1.1 Audio Contract Lab

This lab-only candidate validates the v1.1 profile audio ABI without any VGM
parser or sound-chip RTL. The profile generates one quiet direct square-wave
sequence; VGM loading remains upload/title-only.

## Windows Full Compilation

1. Close Quartus and synchronize the complete Mac repository to Windows.
2. Delete only these project-local directories if present:
   - `hw\golden_player_shell_v1_1_audio_lab\db`
   - `hw\golden_player_shell_v1_1_audio_lab\incremental_db`
   - `hw\golden_player_shell_v1_1_audio_lab\output_files`
3. Open `hw\golden_player_shell_v1_1_audio_lab\MegaVGMPlayer_GoldenShell_v1_1_AudioLab_MiSTer.qpf`.
4. Confirm revision `MegaVGMPlayer_GoldenShell_v1_1_AudioLab_MiSTer`.
5. Run **Processing > Start Compilation** as a Full Compilation.
6. Expected RBF: `hw\golden_player_shell_v1_1_audio_lab\output_files\MegaVGMPlayer_GoldenShell_v1_1_AudioLab_MiSTer.rbf`.

Do not edit QSF or QIP on Windows. After the stable shell reset hold, expect
about two seconds of silence, about one second of a small 1 kHz centered tone,
then silence. Software Reset must repeat the sequence. Verify OSD/Menu,
upload/title, normal video, no freeze, and no signal loss.
