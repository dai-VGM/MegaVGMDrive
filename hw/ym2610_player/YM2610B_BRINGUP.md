# YM2610B bring-up revision

This revision inherits `MegaVGMPlayer_YM2610_MiSTer.qsf` and enables the
compile-time `YM2610B_PLAYER` capability.  The Golden Shell, physical DDRAM
window (`0x30000000`), production QIP/source graph, SSG, ADPCM-A/B, PCM cache,
and ADPCM-A command handoff are shared unchanged with the YM2610 product.

The VGM header bit 31 selects YM2610B behavior per file.  A B-capable build
still rejects writes to the two extra FM channels when that header bit is not
set.  Opcodes `0x58` and `0x59` use the existing parser path.

On Windows, open
`MegaVGMPlayer_YM2610B_Bringup_MiSTer.qpf` and run Full Compilation.  The
expected artifact is
`output_files/MegaVGMPlayer_YM2610B_Bringup_MiSTer.rbf`.

Quartus has not been run on macOS.  This is a bring-up build, not a release.
