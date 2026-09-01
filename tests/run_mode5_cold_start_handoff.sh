#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
RTL_ROOT=${RTL_ROOT:-$REPO_ROOT}
SIMULATION=${TMPDIR:-/tmp}/mode5_cold_start_handoff.$$
trap 'rm -f "$SIMULATION"' EXIT HUP INT TERM

iverilog -g2012 -DSIMULATION ${EXPECT_COLD_CUTOFF:+-DEXPECT_COLD_CUTOFF} \
	-s tb_mode5_cold_start_handoff \
	-o "$SIMULATION" \
	"$REPO_ROOT/tb/tb_mode5_cold_start_handoff.sv" \
	"$RTL_ROOT/rtl/mister_vgm_md_top.sv" \
	"$RTL_ROOT/rtl/vgm_file_loader.sv" \
	"$RTL_ROOT/rtl/vgm_bram_read_adapter.sv" \
	"$RTL_ROOT/rtl/vgm_ddram_backend.sv" \
	"$RTL_ROOT/rtl/vgm_loaded_player.sv" \
	"$RTL_ROOT/rtl/md_sound_module.sv" \
	"$RTL_ROOT/rtl/vgm_region_player.sv" \
	"$RTL_ROOT/rtl/ym2203_sound_module.sv" \
	"$RTL_ROOT/rtl/ym2203_dynamic_cen.sv" \
	"$RTL_ROOT/rtl/ym2151_prewait_audio_gate.sv" \
	"$RTL_ROOT"/rtl/genesis_audio/jt12/*.v \
	"$RTL_ROOT"/rtl/genesis_audio/jt12/adpcm/*.v \
	"$RTL_ROOT"/rtl/genesis_audio/jt12/mixer/*.v \
	"$RTL_ROOT"/rtl/genesis_audio/jt89/*.v \
	"$RTL_ROOT"/rtl/genesis_audio/jt49/*.v \
	"$RTL_ROOT"/rtl/genesis_audio/filters/*.v
vvp "$SIMULATION"
