# YM2610 Golden Shell Stage C Windows build

Stage C keeps the hardware-PASS Stage A/B Golden Player Shell unchanged and
adds the versioned FM/SSG playback profile. Do not edit QSF or QIP on Windows.

1. Close Quartus.
2. Synchronize the complete repository to Windows.
3. Delete, if present:
   - `hw\ym2610_golden_shell_stage_c\db`
   - `hw\ym2610_golden_shell_stage_c\incremental_db`
   - `hw\ym2610_golden_shell_stage_c\output_files`
4. Open `hw\ym2610_golden_shell_stage_c\MegaVGMPlayer_YM2610_GoldenShell_StageC_MiSTer.qpf`.
5. Confirm revision `MegaVGMPlayer_YM2610_GoldenShell_StageC_MiSTer`.
6. Run **Processing > Start Compilation** (Full Compilation).
7. The expected output is
   `hw\ym2610_golden_shell_stage_c\output_files\MegaVGMPlayer_YM2610_GoldenShell_StageC_MiSTer.rbf`.

## MiSTer check

Boot the RBF without pressing software Reset. Confirm the same image, title,
OSD, and Menu behavior as Stages A/B. Load the prepared Olga Breeze fixture.
The first ADPCM-B event at about 0.105 s is intentionally suppressed. Audio
remains effectively silent until the first standard FM key-on at sample
120851 (about 2.740385 s); from there FM-only partial music is expected.
Voice, drum, and other ADPCM material must remain absent.

Check 30 seconds, two minutes, and beyond about 3 minutes 10 seconds for the
loop. Confirm OSD/Menu access, software Reset, same-file and different-file
reload, no automatic
debug page, no video loss, no freeze, and no required power cycle. Then load
the copyright-free SSG fixture generated from the repository root with
`python tb\ym2610_golden_profile\stage_c\generate_stage_c_fixtures.py %TEMP%\ym2610_stage_c`,
then load `%TEMP%\ym2610_stage_c\ssg_abc.vgm`.
Confirm channels A, B, and C followed by silence at end.

Record ALM use and all observations with the report form in
`docs/ym2610_golden_shell_stage_c/DESIGN.md`.
