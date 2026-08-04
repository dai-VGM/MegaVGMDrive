#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../../.." && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/golden-shell-v1.1-stage-b.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT
cd "$repo_root"

olga="${OLGA_VGM:-/Users/daizo/Music/03 Olga Breeze.vgm}"
expected_sha="7fd15fe7bf9537128bc2eb2db957a8ccf40cdac394675137a40ba2a9daa66246"
test -f "$olga"
actual_sha="$(shasum -a 256 "$olga" | awk '{print $1}')"
test "$actual_sha" = "$expected_sha"
test "$(stat -f %z "$olga")" = "934025"

PYTHONDONTWRITEBYTECODE=1 python3 \
  tb/golden_player_shell_v1_1/stage_b/audit_stage_b_v1_1.py
PYTHONDONTWRITEBYTECODE=1 python3 \
  tb/ym2610_golden_profile/stage_b/generate_stage_b_fixtures.py \
  "$build_dir/fixtures"

profile_sources=(
  rtl/ym2610_golden_profile/stage_b/ym2610_golden_stage_b_compat.sv
  rtl/ym2610_golden_profile/stage_b/ym2610_golden_stage_b_read_adapter.sv
  rtl/ym2610_golden_profile/stage_b/ym2610_golden_stage_b_scanner.sv
  rtl/ym2610_golden_profile/stage_b/ym2610_golden_stage_b_profile.sv
  rtl/golden_player_shell_v1_1/profiles/stage_b/golden_player_shell_v1_1_stage_b_profile.sv
)

# Reuse the unchanged hardware-PASS request/response and scanner references.
iverilog -g2012 -Wall -s tb_stage_b_read_adapter \
  -o "$build_dir/read_adapter.vvp" \
  rtl/ym2610_golden_profile/stage_b/ym2610_golden_stage_b_read_adapter.sv \
  tb/ym2610_golden_profile/stage_b/tb_stage_b_read_adapter.sv
vvp "$build_dir/read_adapter.vvp"

iverilog -g2012 -Wall -s tb_stage_b_scanner \
  -o "$build_dir/scanner.vvp" \
  rtl/ym2610_golden_profile/stage_b/ym2610_golden_stage_b_compat.sv \
  rtl/ym2610_golden_profile/stage_b/ym2610_golden_stage_b_scanner.sv \
  tb/ym2610_golden_profile/stage_b/tb_stage_b_scanner.sv
python3 - "$build_dir/fixtures/manifest.json" <<'PY' > "$build_dir/fixture_rows"
import json
import sys
for row in json.load(open(sys.argv[1])).values():
    print(row["file"], row["original"], row["classification"],
          row["reject"], int(row["accepted"]))
PY
while read -r file original classification reject accepted; do
  vvp "$build_dir/scanner.vvp" \
    "+VGM=$build_dir/fixtures/$file" "+ORIGINAL=$original" \
    "+EXPECT_CLASS=$classification" "+EXPECT_REJECT=$reject" \
    "+EXPECT_ACCEPT=$accepted"
done < "$build_dir/fixture_rows"
vvp "$build_dir/scanner.vvp" "+VGM=$olga" +ORIGINAL=933897 +OLGA
echo "GOLDEN_SHELL_V1_1_STAGE_B_REFERENCE PASS"

# Actual v1.1 adapter integration: raw/prepared accept, reject/reload,
# abort/reload, stale generation quarantine, reset during upload/scan, and idle.
iverilog -g2012 -Wall \
  -s tb_golden_player_shell_v1_1_stage_b_lifecycle \
  -o "$build_dir/lifecycle.vvp" "${profile_sources[@]}" \
  tb/golden_player_shell_v1_1/stage_b/tb_golden_player_shell_v1_1_stage_b_lifecycle.sv
vvp "$build_dir/lifecycle.vvp" "+FIXTURES=$build_dir/fixtures"

# Exact stable physical upload backend, byte-lane contract, prepared title,
# 934025-byte completion fence, and full Olga scan through the v1.1 wrapper.
iverilog -g2012 -Wall -DMEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST=1 \
  -s tb_golden_player_shell_v1_1_stage_b_olga_upload \
  -o "$build_dir/olga_upload.vvp" \
  rtl/vgm_ddram_backend.sv rtl/megavgm_title_receiver.sv \
  rtl/golden_player_shell/golden_player_shell_upload.sv \
  "${profile_sources[@]}" \
  tb/golden_player_shell_v1_1/stage_b/tb_golden_player_shell_v1_1_stage_b_olga_upload.sv
vvp "$build_dir/olga_upload.vvp" "+VGM=$olga"

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
sources=tb/golden_player_shell_v1_1/stage_b/stage_b_emu_sources.f

iverilog -g2012 -Wall -Wno-timescale -I. -Itb "${macros[@]}" \
  -s emu -o "$build_dir/stage_b_emu.vvp" -c "$sources" \
  >"$build_dir/emu_iverilog.log" 2>&1
echo "GOLDEN_SHELL_V1_1_STAGE_B_FULL_EMU_ICARUS PASS"

verilator --lint-only --timing -Wall -Wno-fatal \
  -Wno-DECLFILENAME -Wno-PINCONNECTEMPTY -Wno-PROCASSINIT \
  -Wno-SIDEEFFECT -Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL \
  -Wno-WIDTHCONCAT -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC \
  -I. -Itb "${macros[@]}" --top-module emu -f "$sources" \
  >"$build_dir/emu_verilator.log" 2>&1
if grep -Eq '%Warning-(LATCH|MULTIDRIVEN|UNOPTFLAT)|%Error' \
    "$build_dir/emu_verilator.log"; then
  grep -E '%Warning-(LATCH|MULTIDRIVEN|UNOPTFLAT)|%Error' \
    "$build_dir/emu_verilator.log"
  exit 1
fi
echo "GOLDEN_SHELL_V1_1_STAGE_B_VERILATOR PASS LATCH=0 MULTIDRIVEN=0 UNOPTFLAT=0"

verilator --json-only --timing -Wall -Wno-fatal \
  -Wno-DECLFILENAME -Wno-PINCONNECTEMPTY -Wno-PROCASSINIT \
  -Wno-SIDEEFFECT -Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL \
  -Wno-WIDTHCONCAT -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC \
  -I. -Itb "${macros[@]}" --top-module emu -f "$sources" \
  --Mdir "$build_dir/obj_json" \
  --json-only-output "$build_dir/stage_b.json" \
  --json-only-meta-output "$build_dir/stage_b.meta.json" \
  >"$build_dir/emu_json.log" 2>&1
for symbol in golden_player_shell_v1_1_profile ym2610_golden_stage_a \
              ym2610_golden_stage_b_scanner profile_audio_enable \
              audio_gate_open AUDIO_L; do
  grep -q "$symbol" "$build_dir/stage_b.json"
done
echo "GOLDEN_SHELL_V1_1_STAGE_B_ELABORATED_JSON PASS"

verilator --binary --timing -Wall -Wno-fatal \
  -Wno-DECLFILENAME -Wno-PINCONNECTEMPTY -Wno-PROCASSINIT \
  -Wno-SIDEEFFECT -Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL \
  -Wno-WIDTHCONCAT -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC \
  -Wno-TIMESCALEMOD -I. -Itb "${macros[@]}" \
  --top-module tb_golden_player_shell_v1_1_stage_b_emu \
  -f "$sources" \
  tb/golden_player_shell_v1_1/stage_b/tb_golden_player_shell_v1_1_stage_b_emu.sv \
  --Mdir "$build_dir/obj_emu" -o v1_1_stage_b_emu \
  >"$build_dir/emu_binary_build.log" 2>&1
"$build_dir/obj_emu/v1_1_stage_b_emu"

sh tests/test_megavgm_title_integration.sh
echo "GOLDEN_SHELL_V1_1_STAGE_B_TITLE_OSD_SURFACE PASS"

PYTHONDONTWRITEBYTECODE=1 python3 \
  tb/golden_player_shell_v1_1/stage_b/audit_stage_b_v1_1.py
git diff --check
git diff --cached --check
echo "GOLDEN_SHELL_V1_1_STAGE_B_GIT_DIFF_CHECK PASS"
echo "GOLDEN_SHELL_V1_1_STAGE_B_NON_QUARTUS_RESULT PASS"
