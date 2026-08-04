#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
build_dir="${TMPDIR:-/tmp}/megavgm_golden_shell_v1_1"
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

python3 tb/golden_player_shell_v1_1/audit_v1_1.py

iverilog -g2012 -Wall -s tb_golden_player_shell_v1_1_stage_a \
  -o "$build_dir/stage_a_contract.vvp" \
  -c tb/golden_player_shell_v1_1/stage_a_contract_sources.f
vvp "$build_dir/stage_a_contract.vvp"

iverilog -g2012 -Wall -s tb_golden_player_shell_v1_1_audio_lab \
  -o "$build_dir/audio_lab_contract.vvp" \
  -c tb/golden_player_shell_v1_1/audio_lab_contract_sources.f
vvp "$build_dir/audio_lab_contract.vvp"

# The same stable upload/title regression with the lab profile proves that a
# load aborts lab audio and never starts a VGM/scanner/parser/sound path.
iverilog -g2012 -Wall -s tb_golden_player_shell_v1_1_stage_a \
  -o "$build_dir/audio_lab_upload.vvp" \
  rtl/vgm_ddram_backend.sv rtl/megavgm_title_receiver.sv \
  rtl/golden_player_shell_v1_1/profiles/golden_player_shell_v1_1_audio_lab_profile.sv \
  rtl/golden_player_shell/golden_player_shell_upload.sv \
  tb/golden_player_shell_v1_1/tb_golden_player_shell_v1_1_stage_a.sv
vvp "$build_dir/audio_lab_upload.vvp"
echo "GOLDEN_SHELL_V1_1_UPLOAD_TITLE PASS"

for flavor in stage_a audio_lab; do
  sources="tb/golden_player_shell_v1_1/${flavor}_emu_sources.f"
  extra=(-DV1_1_STAGE_A_TEST=1)
  label=STAGE_A
  if [[ "$flavor" == "audio_lab" ]]; then
    extra=(-DV1_1_AUDIO_LAB_TEST=1)
    label=AUDIO_LAB
  fi
  iverilog -g2012 -Wall -Wno-timescale -I. -Itb "${macros[@]}" \
    "${extra[@]}" -s emu -o "$build_dir/${flavor}_emu.vvp" -c "$sources" \
    >"$build_dir/${flavor}_iverilog.log" 2>&1
  vvp "$build_dir/${flavor}_emu.vvp"
  echo "GOLDEN_SHELL_V1_1_${label}_EMU_ICARUS PASS"

  iverilog -g2012 -Wall -Wno-timescale -I. -Itb "${macros[@]}" \
    "${extra[@]}" -s tb_golden_player_shell_v1_1_shim \
    -o "$build_dir/${flavor}_shim.vvp" -c "$sources" \
    tb/golden_player_shell_v1_1/tb_golden_player_shell_v1_1_shim.sv
  vvp "$build_dir/${flavor}_shim.vvp"

  verilator --lint-only --timing -Wall -Wno-fatal \
    -Wno-DECLFILENAME -Wno-PINCONNECTEMPTY -Wno-PROCASSINIT \
    -Wno-SIDEEFFECT -Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL \
    -Wno-WIDTHCONCAT -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC \
    -I. -Itb "${macros[@]}" "${extra[@]}" --top-module emu \
    -f "$sources" >"$build_dir/${flavor}_verilator.log" 2>&1
  if grep -Eq '%Warning-(LATCH|MULTIDRIVEN|UNOPTFLAT)|%Error' \
      "$build_dir/${flavor}_verilator.log"; then
    grep -E '%Warning-(LATCH|MULTIDRIVEN|UNOPTFLAT)|%Error' \
      "$build_dir/${flavor}_verilator.log"
    exit 1
  fi
  echo "GOLDEN_SHELL_V1_1_${label}_VERILATOR PASS LATCH=0 MULTIDRIVEN=0 UNOPTFLAT=0"
done

# Actual stable emu runtime proof with production defaults: the 24-bit stable
# reset hold, two-second profile silence, one-second tone, and final mute all
# remain in the elaborated path.
verilator --binary --timing -Wall -Wno-fatal \
  -Wno-DECLFILENAME -Wno-PINCONNECTEMPTY -Wno-PROCASSINIT \
  -Wno-SIDEEFFECT -Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL \
  -Wno-WIDTHCONCAT -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC \
  -Wno-TIMESCALEMOD -I. -Itb "${macros[@]}" -DV1_1_AUDIO_LAB_TEST=1 \
  --top-module tb_golden_player_shell_v1_1_emu \
  -f tb/golden_player_shell_v1_1/audio_lab_emu_sources.f \
  tb/golden_player_shell_v1_1/tb_golden_player_shell_v1_1_emu.sv \
  --Mdir "$build_dir/obj_audio_lab_emu" \
  -o v1_1_audio_lab_emu >"$build_dir/audio_lab_binary_build.log" 2>&1
"$build_dir/obj_audio_lab_emu/v1_1_audio_lab_emu"
echo "GOLDEN_SHELL_V1_1_AUDIO_LAB_FINAL_EMU_AUDIO PASS"

verilator --json-only --timing -Wall -Wno-fatal \
  -Wno-DECLFILENAME -Wno-PINCONNECTEMPTY -Wno-PROCASSINIT \
  -Wno-SIDEEFFECT -Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL \
  -Wno-WIDTHCONCAT -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC \
  -I. -Itb "${macros[@]}" --top-module emu \
  -f tb/golden_player_shell_v1_1/stage_a_emu_sources.f \
  --Mdir "$build_dir/obj_stage_a_json" \
  --json-only-output "$build_dir/stage_a.json" \
  --json-only-meta-output "$build_dir/stage_a.meta.json" \
  >"$build_dir/stage_a_json.log" 2>&1
verilator --json-only --timing -Wall -Wno-fatal \
  -Wno-DECLFILENAME -Wno-PINCONNECTEMPTY -Wno-PROCASSINIT \
  -Wno-SIDEEFFECT -Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL \
  -Wno-WIDTHCONCAT -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC \
  -I. -Itb "${macros[@]}" --top-module emu \
  -f tb/golden_player_shell_v1_1/audio_lab_emu_sources.f \
  --Mdir "$build_dir/obj_audio_lab_json" \
  --json-only-output "$build_dir/audio_lab.json" \
  --json-only-meta-output "$build_dir/audio_lab.meta.json" \
  >"$build_dir/audio_lab_json.log" 2>&1
grep -q 'profile_audio_enable' "$build_dir/audio_lab.json"
grep -q 'audio_gate_open' "$build_dir/audio_lab.json"
grep -q 'AUDIO_L' "$build_dir/audio_lab.json"
echo "GOLDEN_SHELL_V1_1_ELABORATED_JSON PASS"

sh tests/test_megavgm_title_integration.sh
echo "GOLDEN_SHELL_V1_1_STABLE_TITLE PASS"

python3 tb/golden_player_shell_v1_1/audit_v1_1.py
git diff --check
git diff --cached --check
echo "GOLDEN_SHELL_V1_1_GIT_DIFF_CHECK PASS"
echo "GOLDEN_SHELL_V1_1_NON_QUARTUS_RESULT PASS"
