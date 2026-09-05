#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_tmp="$(mktemp -d "${TMPDIR:-/tmp}/mode5-stop-diag-integration.XXXXXX")"
trap 'rm -rf "$test_tmp"' EXIT
cd "$repo_root"

iverilog -g2012 -DSIMULATION \
    -DMEGAVGMDRIVE_MODE5_STOP_DIAGNOSTIC \
    -s tb_mode5_load_while_playing_session \
    -o "$test_tmp/diag.vvp" \
    tb/tb_mode5_load_while_playing_session.sv \
    rtl/megavgm_mode5_stop_diagnostic.sv \
    rtl/mister_vgm_md_top.sv \
    rtl/megavgm_playlist_status_export.sv \
    rtl/vgm_file_loader.sv \
    rtl/vgm_bram_read_adapter.sv \
    rtl/vgm_ddram_backend.sv \
    rtl/vgm_loaded_player.sv \
    rtl/md_sound_module.sv \
    rtl/vgm_region_player.sv \
    rtl/ym2203_sound_module.sv \
    rtl/ym2203_dynamic_cen.sv \
    rtl/ym2151_prewait_audio_gate.sv \
    rtl/genesis_audio/jt12/*.v \
    rtl/genesis_audio/jt12/adpcm/*.v \
    rtl/genesis_audio/jt12/mixer/*.v \
    rtl/genesis_audio/jt89/*.v \
    rtl/genesis_audio/jt49/*.v \
    rtl/genesis_audio/filters/*.v

vvp "$test_tmp/diag.vvp" | tee "$test_tmp/diag.log"
grep -q '^STRESS_PASS sessions=50 ' "$test_tmp/diag.log"
grep -q '^PASS tb_mode5_load_while_playing_session$' "$test_tmp/diag.log"
echo "PASS run_mode5_stop_diagnostic_integration"
