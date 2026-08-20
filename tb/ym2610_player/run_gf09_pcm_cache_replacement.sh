#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
build_root="$(mktemp -d "${TMPDIR:-/tmp}/gf09-cache.XXXXXX")"
trap 'rm -rf "${build_root:?}"' EXIT

cd "$repo_root"

iverilog -g2012 -s tb_gf09_pcm_cache_replacement \
  -o "$build_root/cache.vvp" \
  rtl/ym2610_player/ym2610_player_pcm_cache.sv \
  tb/ym2610_player/tb_gf09_pcm_cache_replacement.sv
vvp "$build_root/cache.vvp"

verilator --binary --timing -Wall -Wno-fatal -Wno-DECLFILENAME \
  --top-module tb_gf09_pcm_cache_replacement \
  --Mdir "$build_root/verilator" -o cache_verilator \
  rtl/ym2610_player/ym2610_player_pcm_cache.sv \
  tb/ym2610_player/tb_gf09_pcm_cache_replacement.sv
"$build_root/verilator/cache_verilator"
