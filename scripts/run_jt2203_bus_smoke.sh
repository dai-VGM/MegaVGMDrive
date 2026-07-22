#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sim_out="${TMPDIR:-/tmp}/tb_jt2203_bus_smoke.vvp"

cd "$repo_dir"

sources=(
  rtl/genesis_audio/jt12/*.v
  rtl/genesis_audio/jt12/adpcm/jt10_adpcm_div.v
  rtl/genesis_audio/jt49/*.v
)

iverilog -g2012 -Wall -DSIMULATION \
  -s tb_jt2203_bus_smoke \
  -o "$sim_out" \
  "${sources[@]}" \
  tb/tb_jt2203_bus_smoke.sv

vvp "$sim_out"

verilator --lint-only --timing -Wall -Wno-fatal -DSIMULATION \
  --top-module tb_jt2203_bus_smoke \
  tb/tb_jt2203_bus_smoke.sv \
  "${sources[@]}"

verilator --lint-only --timing -Wall -Wno-fatal -DSIMULATION \
  --top-module jt12_top \
  -Guse_lfo=0 -Guse_ssg=1 -Gnum_ch=3 \
  -Guse_pcm=0 -Guse_adpcm=0 -GJT49_DIV=2 -Gmask_div=0 \
  "${sources[@]}"
