#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "$0")/../.." && pwd)
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/ym2610-renderer.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT

iverilog -g2012 -s tb_ym2610_player_debug_renderer \
  -o "$build_dir/debug-renderer.vvp" \
  "$repo_dir/rtl/megavgm_font5x7.sv" \
  "$repo_dir/rtl/ym2610_player/ym2610_player_debug_renderer.sv" \
  "$repo_dir/tb/ym2610_player/tb_ym2610_player_debug_renderer.sv"
vvp "$build_dir/debug-renderer.vvp"

# Compile/elaborate the complete video path without changing timing or mux RTL.
iverilog -g2012 -s ym2610_player_video \
  -o "$build_dir/video.vvp" \
  "$repo_dir/rtl/megavgm_font5x7.sv" \
  "$repo_dir/rtl/megavgm_title_renderer.sv" \
  "$repo_dir/rtl/megavgm_video_timing.sv" \
  "$repo_dir/rtl/ym2610_player/ym2610_player_debug_renderer.sv" \
  "$repo_dir/rtl/ym2610_player/ym2610_player_video.sv"

# The existing title regression proves that Debug View=Off still leaves the
# ordinary navy title surface, prepared names, geometry and font untouched.
"$repo_dir/tb/ym2610_player/run_title.sh"

echo "YM2610_RENDERER_COMPILE debug=PASS video=PASS title_noninterference=PASS result=PASS"
