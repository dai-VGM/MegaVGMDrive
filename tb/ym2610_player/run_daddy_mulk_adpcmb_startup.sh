#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "$0")/../.." && pwd)
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/daddy-mulk-startup.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT

sources=(
  tb/jt10_pinned/6d51e0b6/adpcm/jt10_adpcmb.v
  rtl/genesis_audio/jt10_ym2610/adpcm/jt10_adpcm_div.v
  rtl/genesis_audio/jt10_ym2610/adpcm/jt10_adpcmb_interpol.v
  rtl/genesis_audio/jt10_ym2610/adpcm/jt10_adpcmb_gain.v
  rtl/genesis_audio/jt10_ym2610/adpcm/jt10_adpcmb_cnt.v
  rtl/genesis_audio/jt10_ym2610/adpcm/jt10_adpcm_drvB.v
  tb/ym2610_player/tb_daddy_mulk_adpcmb_startup.sv
)

cd "$repo_dir"
iverilog -g2012 -s tb_daddy_mulk_adpcmb_startup \
  -o "$build_dir/startup.vvp" "${sources[@]}"
vvp "$build_dir/startup.vvp"
verilator --lint-only --timing -Wall -Wno-fatal -Wno-DECLFILENAME \
  --top-module tb_daddy_mulk_adpcmb_startup "${sources[@]}"
