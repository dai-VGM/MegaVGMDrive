#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "$0")/../.." && pwd)
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/ym2610-faults.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT

iverilog -g2012 -s tb_ym2610_player_runtime_faults \
  -o "$build_dir/runtime-faults.vvp" \
  "$repo_dir/rtl/megavgm_video_timing.sv" \
  "$repo_dir/rtl/ym2610_player/ym2610_player_reset_fence.sv" \
  "$repo_dir/rtl/ym2610_player/ym2610_player_diagnostics.sv" \
  "$repo_dir/rtl/ym2610_player/ym2610_player_memory_arbiter.sv" \
  "$repo_dir/tb/ym2610_player/tb_ym2610_player_runtime_faults.sv"
vvp "$build_dir/runtime-faults.vvp"
