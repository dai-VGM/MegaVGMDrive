#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_bin=${TMPDIR:-/tmp}/tb_phase1b_mode5_status_integration.$$
trap 'rm -f "$test_bin"' EXIT HUP INT TERM

cd "$repo_dir"
iverilog -g2012 -DSIMULATION \
	-s tb_mode5_load_while_playing_session \
	-o "$test_bin" \
	tb/tb_mode5_load_while_playing_session.sv \
	rtl/megavgm_playlist_status_export.sv \
	rtl/mister_vgm_md_top.sv \
	rtl/vgm_file_loader.sv \
	rtl/vgm_bram_read_adapter.sv \
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
vvp "$test_bin"
