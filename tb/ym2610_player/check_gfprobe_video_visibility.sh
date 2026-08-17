#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
emu_file="$repo_dir/rtl/emu.sv"

# The lab uses this one existing macro to enable the established video CDC.
rg -U -q '`elsif MISTER_VGM_DEBUG_VIDEO_ENABLE\n`define MEGAVGMDRIVE_VIDEO_DEBUG_CDC' "$emu_file"

# The captured error state occupies snapshot bit 5 and drives the display flag.
rg -U -q 'vgm_player_error,\n                vgm_load_overflow' "$emu_file"
rg -U -q 'wire display_vgm_player_error =\n        video_snapshot_valid && state_snapshot_video\[5\];' "$emu_file"

# Existing visible error presentation is red: R=ff, G=00, B=00.
rg -U -q 'display_vgm_player_error\) \? 8.hff' "$emu_file"
rg -U -q 'display_vgm_player_error\) \? 8.h00' "$emu_file"

echo 'PASS: GF probe debug-video visibility contract'
