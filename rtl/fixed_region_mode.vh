// Source-side fixed region selection for MiSTer hardware smoke tests.
//
// QSF does not currently define FIXED_REGION_MODE, so this header provides the
// temporary hardware default used by both emu.sv debug colors and
// vgm_region_player.sv ROM selection.
//
//   0 = BRINGUP_TONE
//   1 = VGM_SNIPPET smoke test
//   2 = VGM_REAL_SNIPPET, real-VGM-derived YM snippet
`ifndef FIXED_REGION_MODE
`define FIXED_REGION_MODE 2
`endif
