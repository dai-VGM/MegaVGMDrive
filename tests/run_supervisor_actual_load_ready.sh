#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
SIMULATION=${TMPDIR:-/tmp}/supervisor_actual_load_ready.$$
trap 'rm -f "$SIMULATION"' EXIT HUP INT TERM

iverilog -g2012 -DSIMULATION \
	-DMEGAVGMDRIVE_PLAYLIST_LOOP_PHASE1E=1 \
	-s tb_supervisor_actual_load_ready \
	-o "$SIMULATION" \
	"$REPO_ROOT/tb/tb_supervisor_actual_load_ready.sv" \
	"$REPO_ROOT/rtl/megavgm_title_receiver.sv" \
	"$REPO_ROOT/rtl/megavgm_playlist_status_export.sv" \
	"$REPO_ROOT/rtl/vgm_ddram_backend.sv" \
	"$REPO_ROOT/rtl/mister_vgm_md_top.sv" \
	"$REPO_ROOT/rtl/vgm_file_loader.sv" \
	"$REPO_ROOT/rtl/vgm_bram_read_adapter.sv" \
	"$REPO_ROOT/rtl/vgm_loaded_player.sv" \
	"$REPO_ROOT/rtl/md_sound_module.sv" \
	"$REPO_ROOT/rtl/vgm_region_player.sv" \
	"$REPO_ROOT/rtl/ym2203_sound_module.sv" \
	"$REPO_ROOT/rtl/ym2203_dynamic_cen.sv" \
	"$REPO_ROOT/rtl/ym2151_prewait_audio_gate.sv" \
	"$REPO_ROOT"/rtl/genesis_audio/jt12/*.v \
	"$REPO_ROOT"/rtl/genesis_audio/jt12/adpcm/*.v \
	"$REPO_ROOT"/rtl/genesis_audio/jt12/mixer/*.v \
	"$REPO_ROOT"/rtl/genesis_audio/jt89/*.v \
	"$REPO_ROOT"/rtl/genesis_audio/jt49/*.v \
	"$REPO_ROOT"/rtl/genesis_audio/filters/*.v
vvp "$SIMULATION"
