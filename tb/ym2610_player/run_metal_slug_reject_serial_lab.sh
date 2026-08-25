#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/metal-slug-reject-uart.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT
cd "$repo_root"

audit=tb/ym2610_player/audit_metal_slug_reject_serial_lab.py
observer=rtl/ym2610_player_lab/ym2610b_metal_slug_reject_serial_observer.sv
observer_tb=tb/ym2610_player/tb_ym2610b_metal_slug_reject_serial_observer.sv

python3 "$audit"
tclsh hw/ym2610_player/check_metal_slug_reject_ddram_base.tcl

iverilog -g2012 -Wall -s tb_ym2610b_metal_slug_reject_serial_observer \
  -o "$build_dir/observer.vvp" "$observer" "$observer_tb"
vvp "$build_dir/observer.vvp"

verilator --lint-only --timing -Wall -Wno-fatal \
  -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC \
  --top-module tb_ym2610b_metal_slug_reject_serial_observer \
  "$observer" "$observer_tb" >"$build_dir/observer_verilator.log" 2>&1
if rg -n '%Warning-(LATCH|MULTIDRIVEN|UNOPTFLAT)|%Error' \
    "$build_dir/observer_verilator.log"; then
  exit 1
fi

python3 "$audit" --emit-sources >"$build_dir/lab_sources.f"
python3 "$audit" --emit-production-sources >"$build_dir/production_sources.f"

common_macros=(
  -DMISTER_FB=1
  -DYM2610_PLAYER=1
  -DYM2610B_PLAYER=1
  -DFIXED_REGION_MODE=5
  -DMODE5_VGM_BACKEND=1
  -DMODE5_VGM_ADDR_WIDTH=23
  -DMEGAVGMDRIVE_PRODUCTION_AUDIO_BUILD=1
)
lab_macros=("${common_macros[@]}" -DYM2610B_METAL_SLUG_REJECT_UART_LAB=1)
stubs=(
  tb/golden_player_shell_v1_1/stage_c/hps_io_stage_c_upload_stub.sv
  tb/megavgm_pll_elab_stubs.sv
)
verilator_warnings=(
  -Wno-fatal -Wno-DECLFILENAME -Wno-PINCONNECTEMPTY -Wno-PINMISSING
  -Wno-PROCASSINIT -Wno-SIDEEFFECT -Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL
  -Wno-WIDTHCONCAT -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-TIMESCALEMOD
)

iverilog -g2012 -Wall -Wno-timescale -I. -Itb "${lab_macros[@]}" \
  -s golden_player_shell_v1_1_profile -o "$build_dir/lab_profile.vvp" \
  -f "$build_dir/lab_sources.f"
vvp "$build_dir/lab_profile.vvp"

iverilog -g2012 -Wall -Wno-timescale -I. -Itb "${lab_macros[@]}" \
  -s emu -o "$build_dir/lab_emu.vvp" -f "$build_dir/lab_sources.f" \
  "${stubs[@]}"

verilator --lint-only --timing -Wall "${verilator_warnings[@]}" \
  -I. -Itb "${lab_macros[@]}" --top-module emu \
  -f "$build_dir/lab_sources.f" "${stubs[@]}" \
  >"$build_dir/lab_verilator.log" 2>&1
if rg -n '%Warning-(LATCH|MULTIDRIVEN|UNOPTFLAT)|%Error' \
    "$build_dir/lab_verilator.log"; then
  exit 1
fi

# Macro-off proof: the exact inherited production graph still elaborates.
iverilog -g2012 -Wall -Wno-timescale -I. -Itb "${common_macros[@]}" \
  -s emu -o "$build_dir/production_emu.vvp" \
  -f "$build_dir/production_sources.f" "${stubs[@]}"

verilator --lint-only --timing -Wall "${verilator_warnings[@]}" \
  -I. -Itb "${common_macros[@]}" --top-module emu \
  -f "$build_dir/production_sources.f" "${stubs[@]}" \
  >"$build_dir/production_verilator.log" 2>&1
if rg -n '%Warning-(LATCH|MULTIDRIVEN|UNOPTFLAT)|%Error' \
    "$build_dir/production_verilator.log"; then
  exit 1
fi

git diff --check
echo "METAL_SLUG_REJECT_SERIAL_LAB_REGRESSION_PASS observer=1 idle_high=1 first_snapshot=1 reload=1 full_top=1 production_top=1 xmr=0 ddram_base=0x30000000"
