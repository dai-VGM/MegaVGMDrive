#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
build_root="$(mktemp -d "${TMPDIR:-/tmp}/ms-adpcmb-repeat.XXXXXX")"
trap 'rm -rf "${build_root:?}"' EXIT

cd "$repo_root"
iverilog -g2012 -DYM2610B_TEST \
  -s tb_ms_adpcmb_boundary_pending_repro \
  -o "$build_root/repeat.vvp" \
  rtl/ym2610_player/ym2610_player_pcm_cache.sv \
  tb/ym2610_player/tb_ms_adpcmb_boundary_pending_repro.sv
vvp "$build_root/repeat.vvp"

verilator --lint-only --timing -Wall -Wno-fatal -Wno-DECLFILENAME \
  -DYM2610B_TEST --top-module tb_ms_adpcmb_boundary_pending_repro \
  rtl/ym2610_player/ym2610_player_pcm_cache.sv \
  tb/ym2610_player/tb_ms_adpcmb_boundary_pending_repro.sv
