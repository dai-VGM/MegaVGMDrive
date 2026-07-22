#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_tmp="$(mktemp -d "${TMPDIR:-/tmp}/vgm-ym2203-integration.XXXXXX")"
trap 'rm -rf "$test_tmp"' EXIT

cd "$repo_dir"

sources=(
  rtl/vgm_loaded_player.sv
  rtl/ym2203_dynamic_cen.sv
  rtl/ym2203_sound_module.sv
  rtl/genesis_audio/jt12/*.v
  rtl/genesis_audio/jt12/adpcm/jt10_adpcm_div.v
  rtl/genesis_audio/jt49/*.v
)

for chip_clock in 4000000 3579545; do
  iverilog -g2012 -Wall -DSIMULATION \
    -Ptb_vgm_loaded_player_ym2203.CHIP_CLK_HZ="$chip_clock" \
    -s tb_vgm_loaded_player_ym2203 \
    -o "$test_tmp/integration-$chip_clock.vvp" \
    "${sources[@]}" \
    tb/tb_vgm_loaded_player_ym2203.sv
  vvp "$test_tmp/integration-$chip_clock.vvp"
done

verilator --lint-only --timing -Wall -Wno-fatal -DSIMULATION \
  --top-module tb_vgm_loaded_player_ym2203 \
  tb/tb_vgm_loaded_player_ym2203.sv \
  "${sources[@]}"
