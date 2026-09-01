#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_tmp="$(mktemp -d "${TMPDIR:-/tmp}/mode5-cold-regressions.XXXXXX")"
trap 'rm -rf "$test_tmp"' EXIT
cd "$repo_root"

common_sources=(
  rtl/megavgm_playlist_status_export.sv
  rtl/mister_vgm_md_top.sv
  rtl/vgm_file_loader.sv
  rtl/vgm_bram_read_adapter.sv
  rtl/vgm_ddram_backend.sv
  rtl/vgm_loaded_player.sv
  rtl/md_sound_module.sv
  rtl/vgm_region_player.sv
  rtl/ym2203_sound_module.sv
  rtl/ym2203_dynamic_cen.sv
  rtl/ym2151_prewait_audio_gate.sv
  rtl/genesis_audio/jt12/*.v
  rtl/genesis_audio/jt12/adpcm/*.v
  rtl/genesis_audio/jt12/mixer/*.v
  rtl/genesis_audio/jt89/*.v
  rtl/genesis_audio/jt49/*.v
  rtl/genesis_audio/filters/*.v
)

run_top_test() {
  local top="$1"
  iverilog -g2012 -DSIMULATION \
    -s "$top" -o "$test_tmp/$top.vvp" \
    "tb/$top.sv" "${common_sources[@]}"
  vvp "$test_tmp/$top.vvp"
}

tests/run_mode5_cold_start_handoff.sh
tests/run_supervisor_actual_load_ready.sh
tests/run_supervisor_early_load_boundary.sh
run_top_test tb_mode5_sound_reset_sequence
run_top_test tb_mode5_audio_mute_gate
run_top_test tb_mode5_load_while_playing_session
run_top_test tb_mode5_repeat_policy
tb/run_megavgm_playlist_status_export.sh
tb/run_megavgm_playlist_loop_status_export.sh

echo "PASS run_mode5_cold_start_regressions"
