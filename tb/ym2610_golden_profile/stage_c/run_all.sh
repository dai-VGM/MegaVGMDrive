#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../../.." && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/ym2610-golden-stage-c.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT
cd "$repo_root"
export PYTHONDONTWRITEBYTECODE=1

olga="${OLGA_VGM:-/Users/daizo/Music/03 Olga Breeze.vgm}"
expected_sha="7fd15fe7bf9537128bc2eb2db957a8ccf40cdac394675137a40ba2a9daa66246"
test -f "$olga"
test "$(shasum -a 256 "$olga" | awk '{print $1}')" = "$expected_sha"

python3 tb/ym2610_golden_profile/stage_c/audit_stage_c.py
python3 tb/ym2610_golden_profile/stage_c/generate_stage_c_fixtures.py \
  "$build_dir/fixtures"
python3 tb/ym2610_golden_profile/stage_c/stage_c_reference.py "$olga" \
  --json "$build_dir/olga_reference.json" \
  --trace "$build_dir/olga_reference.trace"
cmp "$build_dir/olga_reference.json" \
  tb/ym2610_golden_profile/stage_c/olga_reference.json
python3 tb/ym2610_golden_profile/stage_c/generate_olga_windows.py \
  "$olga" "$build_dir/olga_windows.json" \
  --trace "$build_dir/olga_extended.trace"
cmp "$build_dir/olga_windows.json" \
  tb/ym2610_golden_profile/stage_c/olga_replay_windows.json

iverilog -g2012 -Wall -s tb_stage_c_owner \
  -o "$build_dir/owner.vvp" \
  rtl/ym2610_golden_profile/stage_c/ym2610_golden_stage_c_owner.sv \
  tb/ym2610_golden_profile/stage_c/tb_stage_c_owner.sv
vvp "$build_dir/owner.vvp"

iverilog -g2012 -Wall -s tb_stage_b_read_adapter \
  -o "$build_dir/read_adapter.vvp" \
  rtl/ym2610_golden_profile/stage_b/ym2610_golden_stage_b_read_adapter.sv \
  tb/ym2610_golden_profile/stage_b/tb_stage_b_read_adapter.sv
vvp "$build_dir/read_adapter.vvp"

iverilog -g2012 -Wall -s tb_stage_c_parser_faults \
  -o "$build_dir/parser_faults.vvp" \
  rtl/ym2610_golden_profile/stage_b/ym2610_golden_stage_b_compat.sv \
  rtl/ym2610_golden_profile/stage_c/ym2610_golden_stage_c_parser.sv \
  tb/ym2610_golden_profile/stage_c/tb_stage_c_parser_faults.sv
vvp "$build_dir/parser_faults.vvp"

iverilog -g2012 -Wall -s tb_stage_c_parser \
  -o "$build_dir/parser.vvp" \
  rtl/ym2610_golden_profile/stage_b/ym2610_golden_stage_b_compat.sv \
  rtl/ym2610_golden_profile/stage_c/ym2610_golden_stage_c_parser.sv \
  tb/ym2610_golden_profile/stage_c/tb_stage_c_parser.sv

run_parser() {
  vvp "$build_dir/parser.vvp" "$@"
}
run_parser \
  "+VGM=$build_dir/fixtures/fm_only_raw.vgm" +ORIGINAL=237 +DATA=80 \
  +EXPECT_COMMANDS=37 +EXPECT_WRITES=34 +EXPECT_FM=34 +EXPECT_SSG=0 \
  +EXPECT_A=0 +EXPECT_B=0 +EXPECT_BLOCKS=0 +EXPECT_SAMPLES=799 \
  +EXPECT_HASH=3600d68a4c2a4d74 +EXPECT_FIRST256=3600d68a4c2a4d74 \
  "+TRACE=$build_dir/fm.trace"
run_parser \
  "+VGM=$build_dir/fixtures/fm_only_prepared.vgm" +ORIGINAL=237 +DATA=80 \
  +EXPECT_COMMANDS=37 +EXPECT_WRITES=34 +EXPECT_FM=34 +EXPECT_SSG=0 \
  +EXPECT_A=0 +EXPECT_B=0 +EXPECT_BLOCKS=0 +EXPECT_SAMPLES=799 \
  +EXPECT_HASH=3600d68a4c2a4d74 +EXPECT_FIRST256=3600d68a4c2a4d74
run_parser \
  "+VGM=$build_dir/fixtures/ssg_abc.vgm" +ORIGINAL=174 +DATA=80 \
  +EXPECT_COMMANDS=16 +EXPECT_WRITES=13 +EXPECT_FM=0 +EXPECT_SSG=13 \
  +EXPECT_A=0 +EXPECT_B=0 +EXPECT_BLOCKS=0 +EXPECT_SAMPLES=576 \
  +EXPECT_HASH=7ee5ee210617c916 +EXPECT_FIRST256=7ee5ee210617c916 \
  "+TRACE=$build_dir/ssg.trace"
run_parser \
  "+VGM=$build_dir/fixtures/suppressed_pcm.vgm" +ORIGINAL=302 +DATA=80 \
  +EXPECT_COMMANDS=48 +EXPECT_WRITES=43 +EXPECT_FM=34 +EXPECT_SSG=0 \
  +EXPECT_A=4 +EXPECT_B=5 +EXPECT_BLOCKS=2 +EXPECT_SAMPLES=320 \
  +EXPECT_HASH=7eb5a8a39604be26 +EXPECT_FIRST256=7eb5a8a39604be26
run_parser \
  "+VGM=$build_dir/fixtures/b_compatible_fm.vgm" +ORIGINAL=237 +DATA=80 \
  +EXPECT_COMMANDS=37 +EXPECT_WRITES=34 +EXPECT_FM=34 +EXPECT_SSG=0 \
  +EXPECT_A=0 +EXPECT_B=0 +EXPECT_BLOCKS=0 +EXPECT_SAMPLES=799 \
  +EXPECT_HASH=3600d68a4c2a4d74 +EXPECT_FIRST256=3600d68a4c2a4d74
run_parser \
  "+VGM=$build_dir/fixtures/fm_loop.vgm" +ORIGINAL=237 +DATA=80 +LOOP=e0 \
  +LOOP_MODE +EXPECT_COMMANDS=37 +EXPECT_WRITES=34 +EXPECT_FM=34 \
  +EXPECT_SSG=0 +EXPECT_A=0 +EXPECT_B=0 +EXPECT_BLOCKS=0 \
  +EXPECT_SAMPLES=288 +EXPECT_HASH=05bde4f24ad7bc8a \
  +EXPECT_FIRST256=05bde4f24ad7bc8a
run_parser \
  "+VGM=$olga" +ORIGINAL=933897 +DATA=80 +LOOP=b6223 +LOOP_MODE \
  +EXPECT_COMMANDS=171869 +EXPECT_WRITES=81272 +EXPECT_FM=78293 \
  +EXPECT_SSG=0 +EXPECT_A=2752 +EXPECT_B=227 +EXPECT_BLOCKS=7 \
  +EXPECT_SAMPLES=8372668 +EXPECT_HASH=7c3088bd1d4eea6f \
  +EXPECT_FIRST256=155cbbc09e7b636b \
  "+TRACE=$build_dir/olga_rtl.trace"
cmp "$build_dir/olga_rtl.trace" "$build_dir/olga_reference.trace"
echo "STAGE_C_OLGA_FULL_TRACE PASS rows=81272 byte_exact=1"

iverilog -g2012 -Wall -s tb_stage_b_scanner \
  -o "$build_dir/scanner.vvp" \
  rtl/ym2610_golden_profile/stage_b/ym2610_golden_stage_b_compat.sv \
  rtl/ym2610_golden_profile/stage_b/ym2610_golden_stage_b_scanner.sv \
  tb/ym2610_golden_profile/stage_b/tb_stage_b_scanner.sv
vvp "$build_dir/scanner.vvp" "+VGM=$olga" +ORIGINAL=933897 +OLGA

iverilog -g2012 -Wall -s tb_stage_c_sound_adapter \
  -o "$build_dir/sound.vvp" \
  -c tb/ym2610_golden_profile/stage_c/stage_c_sound_sources.f \
  rtl/ym2610_golden_profile/stage_c/ym2610_golden_stage_c_sound_adapter.sv \
  tb/ym2610_golden_profile/stage_c/tb_stage_c_sound_adapter.sv
for run_id in 1 2 3; do
  vvp "$build_dir/sound.vvp" | tee "$build_dir/sound_$run_id.log"
done
test "$(shasum -a 256 "$build_dir"/sound_*.log | awk '{print $1}' | sort -u | wc -l | tr -d ' ')" = 1

iverilog -g2012 -Wall -s tb_stage_c_direct_replay \
  -o "$build_dir/direct.vvp" \
  -c tb/ym2610_golden_profile/stage_c/stage_c_sound_sources.f \
  rtl/ym2610_golden_profile/stage_b/ym2610_golden_stage_b_compat.sv \
  rtl/ym2610_golden_profile/stage_c/ym2610_golden_stage_c_parser.sv \
  rtl/ym2610_golden_profile/stage_c/ym2610_golden_stage_c_sound_adapter.sv \
  tb/ym2610_golden_profile/stage_c/tb_stage_c_direct_replay.sv
for run_id in 1 2 3; do
  vvp "$build_dir/direct.vvp" \
    "+VGM=$build_dir/fixtures/fm_only_raw.vgm" \
    "+TRACE=$build_dir/fm.trace" +ORIGINAL=237 +DATA=80 \
    +EXPECT_EVENTS=34 +EXPECT_HASH=3600d68a4c2a4d74 \
    | tee "$build_dir/direct_fm_$run_id.log"
  vvp "$build_dir/direct.vvp" \
    "+VGM=$build_dir/fixtures/ssg_abc.vgm" \
    "+TRACE=$build_dir/ssg.trace" +ORIGINAL=174 +DATA=80 \
    +EXPECT_EVENTS=13 +EXPECT_HASH=7ee5ee210617c916 \
    | tee "$build_dir/direct_ssg_$run_id.log"
done
test "$(shasum -a 256 "$build_dir"/direct_fm_*.log | awk '{print $1}' | sort -u | wc -l | tr -d ' ')" = 1
test "$(shasum -a 256 "$build_dir"/direct_ssg_*.log | awk '{print $1}' | sort -u | wc -l | tr -d ' ')" = 1

# The VGM timeline is accelerated only in this equivalence TB. Both sound
# cores still run with the exact header-derived 8 MHz CEN; the production
# 64-sample BUSY deadline is covered by parser_faults above. Verilator runs
# the full retained-state song/loop replay substantially faster than vvp;
# Icarus coverage remains above for the same direct TB and full parser trace.
verilator --binary --timing -Wno-fatal -Wno-DECLFILENAME \
  -Wno-PINCONNECTEMPTY -Wno-PROCASSINIT -Wno-SIDEEFFECT \
  -Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL -Wno-WIDTHCONCAT \
  -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-TIMESCALEMOD \
  --top-module tb_stage_c_direct_replay \
  --Mdir "$build_dir/direct_obj" -o stage_c_direct_verilator \
  -f tb/ym2610_golden_profile/stage_c/stage_c_sound_sources.f \
  rtl/ym2610_golden_profile/stage_b/ym2610_golden_stage_b_compat.sv \
  rtl/ym2610_golden_profile/stage_c/ym2610_golden_stage_c_parser.sv \
  rtl/ym2610_golden_profile/stage_c/ym2610_golden_stage_c_sound_adapter.sv \
  tb/ym2610_golden_profile/stage_c/tb_stage_c_direct_replay.sv \
  > "$build_dir/direct_verilator_build.log" 2>&1
for run_id in 1 2 3; do
  "$build_dir/direct_obj/stage_c_direct_verilator" \
    "+VGM=$olga" "+TRACE=$build_dir/olga_extended.trace" \
    +ORIGINAL=933897 +DATA=80 +EXPECT_EVENTS=81418 +EXPECT_HASH=0 \
    +LOOP=b6223 +TICK_DIV=1 +STOP_AFTER_HASH +OLGA_CONTRACT +CHECK_PREFM \
    +MULTI_WINDOWS +ARM0=119 +ARM1=5759 +ARM2=39435 +ARM3=40999 \
    +ARM4=81122 +WINDOW=olga_multi_full \
    | tee "$build_dir/direct_olga_$run_id.log"
done
test "$(for log in "$build_dir"/direct_olga_*.log; do \
  grep '^STAGE_C_OLGA_WINDOW' "$log" | shasum -a 256; \
done | awk '{print $1}' | sort -u | wc -l | tr -d ' ')" = 1
grep -q 'index=0.*parser_audio=bda45f7a067cf72d.*parser_fm=bda45f7a067cf72d' "$build_dir/direct_olga_1.log"
grep -q 'index=1.*parser_audio=dc663bb0b7349cd5.*parser_fm=dc663bb0b7349cd5' "$build_dir/direct_olga_1.log"
grep -q 'index=2.*parser_audio=184eec59e4466a7d.*parser_fm=184eec59e4466a7d' "$build_dir/direct_olga_1.log"
grep -q 'index=3.*parser_audio=a4a707ca22e4bb61.*parser_fm=a4a707ca22e4bb61' "$build_dir/direct_olga_1.log"
grep -q 'index=4.*parser_audio=87a5398c48b391c1.*parser_fm=87a5398c48b391c1' "$build_dir/direct_olga_1.log"
echo "STAGE_C_OLGA_DIRECT_WINDOWS PASS windows=5 runs=3 deterministic=1"

iverilog -g2012 -Wall -s tb_stage_c_profile_lifecycle \
  -o "$build_dir/profile.vvp" \
  -c tb/ym2610_golden_profile/stage_c/stage_c_sound_sources.f \
  -c tb/ym2610_golden_profile/stage_c/stage_c_profile_sources.f \
  tb/ym2610_golden_profile/stage_c/tb_stage_c_profile_lifecycle.sv

profile_base=(+EXPECT_ACCEPT=1 +EXPECT_PREPARED=0 +EXPECT_COMMANDS=37
  +EXPECT_WRITES=34 +EXPECT_FM=34 +EXPECT_SSG=0 +EXPECT_A=0 +EXPECT_B=0
  +EXPECT_BLOCKS=0 +EXPECT_HASH=3600d68a4c2a4d74)
vvp "$build_dir/profile.vvp" "+VGM=$build_dir/fixtures/fm_only_raw.vgm" \
  "${profile_base[@]}" +EXPECT_AUDIO_HASH=2a1aa6dc21860dfd
vvp "$build_dir/profile.vvp" "+VGM=$build_dir/fixtures/fm_only_raw.vgm" \
  "${profile_base[@]}" +EXPECT_AUDIO_HASH=2a1aa6dc21860dfd \
  +DIFFERENT_RELOAD "+VGM2=$build_dir/fixtures/ssg_abc.vgm" \
  +EXPECT2_PREPARED=0 +EXPECT2_COMMANDS=16 +EXPECT2_WRITES=13 \
  +EXPECT2_FM=0 +EXPECT2_SSG=13 +EXPECT2_A=0 +EXPECT2_B=0 \
  +EXPECT2_BLOCKS=0 +EXPECT2_HASH=7ee5ee210617c916
vvp "$build_dir/profile.vvp" "+VGM=$build_dir/fixtures/fm_only_prepared.vgm" \
  +EXPECT_ACCEPT=1 +EXPECT_PREPARED=1 +EXPECT_COMMANDS=37 +EXPECT_WRITES=34 \
  +EXPECT_FM=34 +EXPECT_SSG=0 +EXPECT_A=0 +EXPECT_B=0 +EXPECT_BLOCKS=0 \
  +EXPECT_HASH=3600d68a4c2a4d74 +EXPECT_AUDIO_HASH=2a1aa6dc21860dfd +RELOAD
vvp "$build_dir/profile.vvp" "+VGM=$build_dir/fixtures/ssg_abc.vgm" \
  +EXPECT_ACCEPT=1 +EXPECT_PREPARED=0 +EXPECT_COMMANDS=16 +EXPECT_WRITES=13 \
  +EXPECT_FM=0 +EXPECT_SSG=13 +EXPECT_A=0 +EXPECT_B=0 +EXPECT_BLOCKS=0 \
  +EXPECT_HASH=7ee5ee210617c916
vvp "$build_dir/profile.vvp" "+VGM=$build_dir/fixtures/suppressed_pcm.vgm" \
  +EXPECT_ACCEPT=1 +EXPECT_PREPARED=0 +EXPECT_COMMANDS=48 +EXPECT_WRITES=43 \
  +EXPECT_FM=34 +EXPECT_SSG=0 +EXPECT_A=4 +EXPECT_B=5 +EXPECT_BLOCKS=2 \
  +EXPECT_HASH=7eb5a8a39604be26
vvp "$build_dir/profile.vvp" "+VGM=$build_dir/fixtures/fm_loop.vgm" \
  +EXPECT_ACCEPT=1 +EXPECT_PREPARED=0 +EXPECT_COMMANDS=37 +EXPECT_WRITES=34 \
  +EXPECT_FM=34 +EXPECT_SSG=0 +EXPECT_A=0 +EXPECT_B=0 +EXPECT_BLOCKS=0 \
  +EXPECT_HASH=05bde4f24ad7bc8a +LOOP_TEST
for reset_at in 1 2 3 4; do
  vvp "$build_dir/profile.vvp" "+VGM=$build_dir/fixtures/fm_only_raw.vgm" \
    "${profile_base[@]}" "+RESET_AT=$reset_at"
done
vvp "$build_dir/profile.vvp" "+VGM=$build_dir/fixtures/fm_only_raw.vgm" \
  "${profile_base[@]}" +RESET_AT=5
for reject in reject_b_key reject_b_setup reject_dual reject_unknown reject_opcode; do
  vvp "$build_dir/profile.vvp" "+VGM=$build_dir/fixtures/$reject.vgm" \
    +EXPECT_ACCEPT=0 +EXPECT_PREPARED=0 +EXPECT_COMMANDS=0 +EXPECT_WRITES=0 \
    +EXPECT_FM=0 +EXPECT_SSG=0 +EXPECT_A=0 +EXPECT_B=0 +EXPECT_BLOCKS=0 \
    +EXPECT_HASH=cbf29ce484222325
done
vvp "$build_dir/profile.vvp" \
  "+VGM=$build_dir/fixtures/reject_b_key.vgm" \
  +EXPECT_ACCEPT=0 +EXPECT_PREPARED=0 +EXPECT_COMMANDS=0 +EXPECT_WRITES=0 \
  +EXPECT_FM=0 +EXPECT_SSG=0 +EXPECT_A=0 +EXPECT_B=0 +EXPECT_BLOCKS=0 \
  +EXPECT_HASH=cbf29ce484222325 +RELOAD

macros=(-DMISTER_FB=1 -DFIXED_REGION_MODE=5 -DMODE5_VGM_BACKEND=1
  -DMODE5_VGM_ADDR_WIDTH=23 -DMEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD=1
  -DMEGAVGMDRIVE_PRODUCTION_AUDIO_BUILD=1 -DMEGAVGMDRIVE_SEGAPCM_SMOKE_TEST=1
  -DMEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST=1
  -DMEGAVGMDRIVE_SEGAPCM_MIN_DEBUG_PROBE=1 -DMODE5_DEBUG_OVERLAY_ALWAYS_ON=1
  -DMEGAVGMDRIVE_SEGAPCM_AB1_MAME_SCRATCH=1
  -DMEGAVGMDRIVE_SEGAPCM_AB2_MAME_NONLOOP_END=1
  -DMEGAVGMDRIVE_SEGAPCM_SMOKE_PARSER_RUN_TEST=1
  -DMEGAVGMDRIVE_SEGAPCM_C0DRIVE_TICK_SLOW=1
  -DMEGAVGMDRIVE_START_HOLD_NO_BUSY_CLEAR=1
  -DMEGAVGMDRIVE_DIRECT_PLAYER_START_DEBUG=1 -DMD_JT12_CEN_NTSC_TEST=1)
iverilog -g2012 -Wall -Wno-timescale -I. -Itb "${macros[@]}" \
  -s emu -o "$build_dir/stage_c_emu.vvp" \
  -c tb/ym2610_golden_profile/stage_c/stage_c_emu_sources.f
vvp "$build_dir/stage_c_emu.vvp"
echo "STAGE_C_FULL_EMU_ICARUS PASS"

verilator --lint-only --timing -Wall -Wno-fatal \
  -Wno-DECLFILENAME -Wno-PINCONNECTEMPTY -Wno-PROCASSINIT \
  -Wno-SIDEEFFECT -Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL \
  -Wno-WIDTHCONCAT -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC \
  -I. -Itb "${macros[@]}" --top-module emu \
  -f tb/ym2610_golden_profile/stage_c/stage_c_emu_sources.f \
  > "$build_dir/verilator.log" 2>&1
if grep -Eq '%Warning-(LATCH|MULTIDRIVEN|UNOPTFLAT)|%Error' \
  "$build_dir/verilator.log"; then
  grep -E '%Warning-(LATCH|MULTIDRIVEN|UNOPTFLAT)|%Error' \
    "$build_dir/verilator.log"
  exit 1
fi
echo "STAGE_C_FULL_EMU_VERILATOR PASS LATCH=0 MULTIDRIVEN=0 UNOPTFLAT=0"

sh tests/test_megavgm_title_integration.sh
iverilog -g2012 -Wall -s tb_megavgm_video_timing \
  -o "$build_dir/video.vvp" rtl/megavgm_video_timing.sv \
  tb/tb_megavgm_video_timing.sv
vvp "$build_dir/video.vvp"
python3 tb/audit_ym2610_hw0.py
git diff --check
git diff --cached --check
python3 tb/ym2610_golden_profile/stage_c/audit_stage_c.py
echo "GOLDEN_SHELL_STAGE_C_NON_QUARTUS_RESULT PASS"
