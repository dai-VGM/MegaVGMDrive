#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "$0")/../.." && pwd)
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/ym2610-adpcma24.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT

cd "$repo_dir"
iverilog -g2012 -s tb_ym2610_adpcma_24bit_cache \
  -o "$build_dir/cache.vvp" \
  rtl/ym2610_player/ym2610_player_pcm_cache.sv \
  tb/ym2610_player/tb_ym2610_adpcma_24bit_cache.sv
vvp "$build_dir/cache.vvp"

verilator --lint-only --timing -Wall -Wno-fatal -Wno-DECLFILENAME \
  --top-module tb_ym2610_adpcma_24bit_cache \
  rtl/ym2610_player/ym2610_player_pcm_cache.sv \
  tb/ym2610_player/tb_ym2610_adpcma_24bit_cache.sv
