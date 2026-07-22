#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_tmp="$(mktemp -d "${TMPDIR:-/tmp}/production-ym2612-route.XXXXXX")"
trap 'rm -rf "$test_tmp"' EXIT
cd "$repo_dir"

# Active VERILOG_MACRO assignments in VGM_MD_MiSTer.qsf. Keep this explicit so
# the reproduction cannot silently fall back to the non-production MD build.
defines=(
  -DSIMULATION
  -DMISTER_FB=1
  -DFIXED_REGION_MODE=5
  -DMODE5_VGM_BACKEND=1
  -DMODE5_VGM_ADDR_WIDTH=23
  -DMEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD=1
  -DMEGAVGMDRIVE_PRODUCTION_AUDIO_BUILD=1
  -DMEGAVGMDRIVE_SEGAPCM_SMOKE_TEST=1
  -DMEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST=1
  -DMEGAVGMDRIVE_SEGAPCM_MIN_DEBUG_PROBE=1
  -DMODE5_DEBUG_OVERLAY_ALWAYS_ON=1
  -DMEGAVGMDRIVE_SEGAPCM_AB1_MAME_SCRATCH=1
  -DMEGAVGMDRIVE_SEGAPCM_AB2_MAME_NONLOOP_END=1
  -DMEGAVGMDRIVE_SEGAPCM_SMOKE_PARSER_RUN_TEST=1
  -DMEGAVGMDRIVE_SEGAPCM_C0DRIVE_TICK_SLOW=1
  -DMEGAVGMDRIVE_START_HOLD_NO_BUSY_CLEAR=1
  -DMEGAVGMDRIVE_DIRECT_PLAYER_START_DEBUG=1
)

sources=(
  rtl/mister_vgm_md_top.sv
  rtl/vgm_region_player.sv
  rtl/vgm_file_loader.sv
  rtl/vgm_bram_read_adapter.sv
  rtl/vgm_ddram_backend.sv
  rtl/vgm_c0_lab_backend.sv
  rtl/vgm_loaded_player.sv
  rtl/md_sound_module.sv
  rtl/mode5_ym2203_audio_mixer.sv
  rtl/ym2203_dynamic_cen.sv
  rtl/ym2203_sound_module.sv
  rtl/ym2151_sound_module.sv
  rtl/segapcm_sound_module.sv
  third_party/jtcores/cores/outrun/hdl/jtoutrun_pcm.v
  third_party/jtcores/modules/jtframe/hdl/ram/jtframe_dual_ram.v
  third_party/jt51/hdl/*.v
  third_party/jt51/ver/common/sep32.v
  third_party/jt51/ver/common/sep32_cnt.v
  rtl/genesis_audio/filters/*.v
  rtl/genesis_audio/jt12/*.v
  rtl/genesis_audio/jt12/adpcm/jt10_adpcm_div.v
  rtl/genesis_audio/jt12/mixer/*.v
  rtl/genesis_audio/jt49/*.v
  rtl/genesis_audio/jt89/*.v
)

iverilog -g2012 -Wall -I. "${defines[@]}" \
  -s tb_production_ym2612_route_repro \
  -o "$test_tmp/repro.vvp" \
  "${sources[@]}" tb/tb_production_ym2612_route_repro.sv \
  >"$test_tmp/icarus-compile.log" 2>&1
echo "ICARUS_COMPILE_PASS"
for fixture_select in "0 0" "1 0" "2 0" "3 0" "3 1" "3 3"; do
  read -r fixture audio_select <<<"$fixture_select"
  (
    cd "$test_tmp"
    vvp repro.vvp +FIXTURE="$fixture" +AUDIO_SELECT="$audio_select"
  ) | tee "$test_tmp/icarus-run-$fixture-$audio_select.log"
done

verilator --lint-only --timing -Wall -Wno-fatal -I. "${defines[@]}" \
  --top-module tb_production_ym2612_route_repro \
  tb/tb_production_ym2612_route_repro.sv "${sources[@]}" \
  >"$test_tmp/verilator.log" 2>&1
warning_count="$(grep -c '^%Warning' "$test_tmp/verilator.log" || true)"
echo "VERILATOR_PASS warnings=$warning_count"
