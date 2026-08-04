#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
build_dir="${TMPDIR:-/tmp}/megavgm_golden_shell_stage_a"
mkdir -p "$build_dir"

cd "$repo_root"
iverilog -g2012 -Wall \
  -DMEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST=1 \
  -s tb_golden_player_shell_stage_a \
  -o "$build_dir/stage_a.vvp" \
  -c tb/golden_player_shell/golden_stage_a_sources.f
vvp "$build_dir/stage_a.vvp"
