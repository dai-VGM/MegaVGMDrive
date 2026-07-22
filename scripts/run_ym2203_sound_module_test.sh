#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sim_out="${TMPDIR:-/tmp}/tb_ym2203_sound_module.vvp"

cd "$repo_dir"

sources=(
  rtl/ym2203_dynamic_cen.sv
  rtl/ym2203_sound_module.sv
  rtl/genesis_audio/jt12/*.v
  rtl/genesis_audio/jt12/adpcm/jt10_adpcm_div.v
  rtl/genesis_audio/jt49/*.v
)

iverilog -g2012 -Wall -DSIMULATION \
  -s tb_ym2203_sound_module \
  -o "$sim_out" \
  "${sources[@]}" \
  tb/tb_ym2203_sound_module.sv

vvp "$sim_out"

verilator --lint-only --timing -Wall -Wno-fatal -DSIMULATION \
  --top-module tb_ym2203_sound_module \
  tb/tb_ym2203_sound_module.sv \
  "${sources[@]}"
