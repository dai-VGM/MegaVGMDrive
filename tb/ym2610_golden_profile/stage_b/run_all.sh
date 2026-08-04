#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../../.." && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/ym2610-golden-stage-b.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT
cd "$repo_root"

olga="${OLGA_VGM:-/Users/daizo/Music/03 Olga Breeze.vgm}"
expected_sha="7fd15fe7bf9537128bc2eb2db957a8ccf40cdac394675137a40ba2a9daa66246"
test -f "$olga"
actual_sha="$(shasum -a 256 "$olga" | awk '{print $1}')"
test "$actual_sha" = "$expected_sha"
test "$(stat -f %z "$olga")" = "934025"

PYTHONDONTWRITEBYTECODE=1 python3 \
  tb/ym2610_golden_profile/stage_b/audit_stage_b.py
python3 tb/ym2610_golden_profile/stage_b/generate_stage_b_fixtures.py \
  "$build_dir/fixtures"

profile_sources=(
  rtl/ym2610_golden_profile/stage_b/ym2610_golden_stage_b_compat.sv
  rtl/ym2610_golden_profile/stage_b/ym2610_golden_stage_b_read_adapter.sv
  rtl/ym2610_golden_profile/stage_b/ym2610_golden_stage_b_scanner.sv
  rtl/ym2610_golden_profile/stage_b/ym2610_golden_stage_b_profile.sv
)

iverilog -g2012 -Wall -s tb_stage_b_read_adapter \
  -o "$build_dir/read_adapter.vvp" \
  rtl/ym2610_golden_profile/stage_b/ym2610_golden_stage_b_read_adapter.sv \
  tb/ym2610_golden_profile/stage_b/tb_stage_b_read_adapter.sv
vvp "$build_dir/read_adapter.vvp"

iverilog -g2012 -Wall -s tb_stage_b_scanner -o "$build_dir/scanner.vvp" \
  rtl/ym2610_golden_profile/stage_b/ym2610_golden_stage_b_compat.sv \
  rtl/ym2610_golden_profile/stage_b/ym2610_golden_stage_b_scanner.sv \
  tb/ym2610_golden_profile/stage_b/tb_stage_b_scanner.sv
python3 - "$build_dir/fixtures/manifest.json" <<'PY' > "$build_dir/fixture_rows"
import json
import sys
for name, row in json.load(open(sys.argv[1])).items():
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

iverilog -g2012 -Wall -s tb_stage_b_profile_lifecycle \
  -o "$build_dir/lifecycle.vvp" "${profile_sources[@]}" \
  tb/ym2610_golden_profile/stage_b/tb_stage_b_profile_lifecycle.sv
vvp "$build_dir/lifecycle.vvp" "+FIXTURES=$build_dir/fixtures"

iverilog -g2012 -Wall -DMEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST=1 \
  -s tb_stage_b_olga_upload -o "$build_dir/olga_upload.vvp" \
  rtl/vgm_ddram_backend.sv rtl/megavgm_title_receiver.sv \
  rtl/golden_player_shell/golden_player_shell_upload.sv \
  "${profile_sources[@]}" \
  tb/ym2610_golden_profile/stage_b/tb_stage_b_olga_upload.sv
vvp "$build_dir/olga_upload.vvp" "+VGM=$olga"

# The immutable Stage A upload/title/large-file regression is compiled from
# its own unchanged source list. Its branch-specific audit is intentionally
# replaced by the Stage B provenance audit above.
bash tb/golden_player_shell/run_stage_a.sh

macros=(
  -DMISTER_FB=1 -DFIXED_REGION_MODE=5 -DMODE5_VGM_BACKEND=1
  -DMODE5_VGM_ADDR_WIDTH=23 -DMEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD=1
  -DMEGAVGMDRIVE_PRODUCTION_AUDIO_BUILD=1 -DMEGAVGMDRIVE_SEGAPCM_SMOKE_TEST=1
  -DMEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST=1
  -DMEGAVGMDRIVE_SEGAPCM_MIN_DEBUG_PROBE=1 -DMODE5_DEBUG_OVERLAY_ALWAYS_ON=1
  -DMEGAVGMDRIVE_SEGAPCM_AB1_MAME_SCRATCH=1
  -DMEGAVGMDRIVE_SEGAPCM_AB2_MAME_NONLOOP_END=1
  -DMEGAVGMDRIVE_SEGAPCM_SMOKE_PARSER_RUN_TEST=1
  -DMEGAVGMDRIVE_SEGAPCM_C0DRIVE_TICK_SLOW=1
  -DMEGAVGMDRIVE_START_HOLD_NO_BUSY_CLEAR=1
  -DMEGAVGMDRIVE_DIRECT_PLAYER_START_DEBUG=1 -DMD_JT12_CEN_NTSC_TEST=1
)
iverilog -g2012 -Wall -Wno-timescale -I. -Itb "${macros[@]}" \
  -s emu -o "$build_dir/stage_b_emu.vvp" \
  -c tb/ym2610_golden_profile/stage_b/stage_b_emu_sources.f \
  > "$build_dir/emu_iverilog.log" 2>&1
vvp "$build_dir/stage_b_emu.vvp"
echo "STAGE_B_FULL_EMU_ICARUS PASS"

verilator --lint-only --timing -Wall -Wno-fatal \
  -Wno-DECLFILENAME -Wno-PINCONNECTEMPTY -Wno-PROCASSINIT \
  -Wno-SIDEEFFECT -Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL \
  -Wno-WIDTHCONCAT -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC \
  -I. -Itb "${macros[@]}" --top-module emu \
  $(tr '\n' ' ' < tb/ym2610_golden_profile/stage_b/stage_b_emu_sources.f) \
  > "$build_dir/emu_verilator.log" 2>&1
if grep -Eq '%Warning-(LATCH|MULTIDRIVEN|UNOPTFLAT)|%Error' \
  "$build_dir/emu_verilator.log"; then
  grep -E '%Warning-(LATCH|MULTIDRIVEN|UNOPTFLAT)|%Error' \
    "$build_dir/emu_verilator.log"
  exit 1
fi
echo "STAGE_B_FULL_EMU_VERILATOR PASS LATCH=0 MULTIDRIVEN=0 UNOPTFLAT=0"

sh tests/test_megavgm_title_integration.sh
iverilog -g2012 -Wall -s tb_megavgm_video_timing \
  -o "$build_dir/video.vvp" rtl/megavgm_video_timing.sv \
  tb/tb_megavgm_video_timing.sv
vvp "$build_dir/video.vvp"

git diff --check
git diff --cached --check
PYTHONDONTWRITEBYTECODE=1 python3 \
  tb/ym2610_golden_profile/stage_b/audit_stage_b.py
echo "GOLDEN_SHELL_STAGE_B_NON_QUARTUS_RESULT PASS"
