#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
build_dir="${TMPDIR:-/tmp}/megavgm_golden_shell_all"
mkdir -p "$build_dir"
cd "$repo_root"

macros=(
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
  -DMD_JT12_CEN_NTSC_TEST=1
)

python3 tb/golden_player_shell/audit_golden_shell.py

bash tb/golden_player_shell/run_stage_a.sh

iverilog -g2012 -Wall -Wno-timescale -I. -Itb \
  "${macros[@]}" \
  -s emu \
  -o "$build_dir/golden_emu.vvp" \
  -c tb/golden_player_shell/golden_emu_sources.f \
  >"$build_dir/iverilog.log" 2>&1
vvp "$build_dir/golden_emu.vvp"
iverilog_warning_count="$(grep -c 'warning:' "$build_dir/iverilog.log" || true)"
echo "GOLDEN_EMU_ICARUS PASS warnings=$iverilog_warning_count"

verilator --lint-only --timing -Wall -Wno-fatal \
  -Wno-DECLFILENAME -Wno-PINCONNECTEMPTY -Wno-PROCASSINIT \
  -Wno-SIDEEFFECT -Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL \
  -Wno-WIDTHCONCAT -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC \
  -I. -Itb "${macros[@]}" --top-module emu \
  $(tr '\n' ' ' < tb/golden_player_shell/golden_emu_sources.f) \
  >"$build_dir/verilator.log" 2>&1
if grep -Eq '%Warning-(LATCH|MULTIDRIVEN|UNOPTFLAT)|%Error' "$build_dir/verilator.log"; then
  grep -E '%Warning-(LATCH|MULTIDRIVEN|UNOPTFLAT)|%Error' "$build_dir/verilator.log"
  exit 1
fi
verilator_warning_count="$(grep -c '^%Warning-' "$build_dir/verilator.log" || true)"
echo "GOLDEN_EMU_VERILATOR PASS warnings=$verilator_warning_count LATCH=0 MULTIDRIVEN=0 UNOPTFLAT=0"

sh tests/test_megavgm_title_integration.sh
echo "GOLDEN_STABLE_TITLE_REGRESSION PASS"

iverilog -g2012 -Wall -s tb_megavgm_video_timing \
  -o "$build_dir/video_timing.vvp" \
  rtl/megavgm_video_timing.sv tb/tb_megavgm_video_timing.sv
vvp "$build_dir/video_timing.vvp"
echo "GOLDEN_STABLE_VIDEO_REGRESSION PASS"

git diff --check
git diff --cached --check
echo "GOLDEN_GIT_DIFF_CHECK PASS"
echo "GOLDEN_SHELL_NON_QUARTUS_RESULT PASS"
