#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../../.." && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/golden-v1-1-stage-c.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT
cd "$repo_root"
export PYTHONDONTWRITEBYTECODE=1

olga="${OLGA_VGM:-/Users/daizo/Music/03 Olga Breeze.vgm}"
expected_olga_sha="7fd15fe7bf9537128bc2eb2db957a8ccf40cdac394675137a40ba2a9daa66246"
test -f "$olga"
test "$(shasum -a 256 "$olga" | awk '{print $1}')" = "$expected_olga_sha"
test "$(wc -c < "$olga" | tr -d ' ')" = 934025

python3 tb/golden_player_shell_v1_1/stage_c/audit_stage_c_v1_1.py
python3 tb/ym2610_golden_profile/stage_c/generate_stage_c_fixtures.py \
  "$build_dir/fixtures"

# Immutable Stage C owner, byte-reader, and defensive fault contracts.
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

# Targeted parser fixtures cover both upload forms, FM, SSG, suppressed PCM,
# the B-compatible tag, loop, and exact command/accounting traces.
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

# The unchanged sound boundary is the hash authority. Three complete runs
# prove deterministic FM, SSG A/B/C, explicit volume mute, CEN, PCM, and X/Z.
iverilog -g2012 -Wall -s tb_stage_c_sound_adapter \
  -o "$build_dir/sound.vvp" \
  -c tb/ym2610_golden_profile/stage_c/stage_c_sound_sources.f \
  rtl/ym2610_golden_profile/stage_c/ym2610_golden_stage_c_sound_adapter.sv \
  tb/ym2610_golden_profile/stage_c/tb_stage_c_sound_adapter.sv
for run_id in 1 2 3; do
  vvp "$build_dir/sound.vvp" | tee "$build_dir/sound_$run_id.log"
done
test "$(shasum -a 256 "$build_dir"/sound_*.log | awk '{print $1}' | sort -u | wc -l | tr -d ' ')" = 1
grep -q 'fm_hash=2a1aa6dc21860dfd' "$build_dir/sound_1.log"
grep -q 'ssg_hash=2d7fa36247dc0e75' "$build_dir/sound_1.log"
grep -q 'mute_hash=28c31cf8df2ec325' "$build_dir/sound_1.log"

# One direct parser->sound replay per synthetic path confirms the unchanged
# integration. The five long retained-state Olga windows are blob-audited by
# audit_stage_c_v1_1.py and are not needlessly regenerated here.
iverilog -g2012 -Wall -s tb_stage_c_direct_replay \
  -o "$build_dir/direct.vvp" \
  -c tb/ym2610_golden_profile/stage_c/stage_c_sound_sources.f \
  rtl/ym2610_golden_profile/stage_b/ym2610_golden_stage_b_compat.sv \
  rtl/ym2610_golden_profile/stage_c/ym2610_golden_stage_c_parser.sv \
  rtl/ym2610_golden_profile/stage_c/ym2610_golden_stage_c_sound_adapter.sv \
  tb/ym2610_golden_profile/stage_c/tb_stage_c_direct_replay.sv
vvp "$build_dir/direct.vvp" \
  "+VGM=$build_dir/fixtures/fm_only_raw.vgm" \
  "+TRACE=$build_dir/fm.trace" +ORIGINAL=237 +DATA=80 \
  +EXPECT_EVENTS=34 +EXPECT_HASH=3600d68a4c2a4d74
vvp "$build_dir/direct.vvp" \
  "+VGM=$build_dir/fixtures/ssg_abc.vgm" \
  "+TRACE=$build_dir/ssg.trace" +ORIGINAL=174 +DATA=80 \
  +EXPECT_EVENTS=13 +EXPECT_HASH=7ee5ee210617c916

# New wrapper integration: representative reject/recovery, raw/prepared load,
# scanner->parser handoff, gate-before-start, FM/SSG/PCM suppression, end,
# loop, upload/scan/sound/playback reset, and same/different reload.
iverilog -g2012 -Wall -s tb_golden_player_shell_v1_1_stage_c_profile \
  -o "$build_dir/v1_1_profile.vvp" \
  -c tb/ym2610_golden_profile/stage_c/stage_c_sound_sources.f \
  -c tb/ym2610_golden_profile/stage_c/stage_c_profile_sources.f \
  rtl/golden_player_shell_v1_1/profiles/stage_c/golden_player_shell_v1_1_stage_c_profile.sv \
  tb/golden_player_shell_v1_1/stage_c/tb_golden_player_shell_v1_1_stage_c_profile.sv
vvp "$build_dir/v1_1_profile.vvp" "+FIXTURES=$build_dir/fixtures"

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
verilator_warnings=(-Wno-fatal -Wno-DECLFILENAME -Wno-PINCONNECTEMPTY
  -Wno-PINMISSING -Wno-PROCASSINIT -Wno-SIDEEFFECT -Wno-UNUSEDPARAM
  -Wno-UNUSEDSIGNAL -Wno-WIDTHCONCAT -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC
  -Wno-TIMESCALEMOD)

# Actual Stage C production source graph, v1.1 shim, and stable emu.
iverilog -g2012 -Wall -Wno-timescale -I. -Itb "${macros[@]}" \
  -s emu -o "$build_dir/stage_c_emu.vvp" \
  -c tb/golden_player_shell_v1_1/stage_c/stage_c_emu_sources.f
vvp "$build_dir/stage_c_emu.vvp"
echo 'V1_1_STAGE_C_FULL_EMU_ICARUS PASS'

verilator --lint-only --timing -Wall "${verilator_warnings[@]}" \
  -I. -Itb "${macros[@]}" --top-module emu \
  -f tb/golden_player_shell_v1_1/stage_c/stage_c_emu_sources.f \
  > "$build_dir/verilator_lint.log" 2>&1
if grep -Eq '%Warning-(LATCH|MULTIDRIVEN|UNOPTFLAT)|%Error' \
  "$build_dir/verilator_lint.log"; then
  grep -E '%Warning-(LATCH|MULTIDRIVEN|UNOPTFLAT)|%Error' \
    "$build_dir/verilator_lint.log"
  exit 1
fi
echo 'V1_1_STAGE_C_FULL_EMU_VERILATOR_LINT PASS LATCH=0 MULTIDRIVEN=0 UNOPTFLAT=0'

verilator --binary --timing -O3 -CFLAGS '-O3' \
  "${verilator_warnings[@]}" -I. -Itb "${macros[@]}" \
  --top-module tb_golden_player_shell_v1_1_stage_c_full_emu \
  --Mdir "$build_dir/full_obj" -o v1_1_stage_c_full \
  -f tb/golden_player_shell_v1_1/stage_c/stage_c_full_emu_sources.f \
  tb/golden_player_shell_v1_1/stage_c/tb_golden_player_shell_v1_1_stage_c_full_emu.sv \
  > "$build_dir/verilator_full_build.log" 2>&1

run_full() {
  local name="$1"
  shift
  "$build_dir/full_obj/v1_1_stage_c_full" "$@" \
    | tee "$build_dir/full_$name.log"
  grep -q 'V1_1_STAGE_C_FULL_EMU_RESULT PASS' "$build_dir/full_$name.log"
}
run_full fm "+VGM=$build_dir/fixtures/fm_only_raw.vgm"
grep -q 'hash_samples=512 hash=2a1aa6dc21860dfd pcm=0 xz=0' \
  "$build_dir/full_fm.log"
run_full ssg "+VGM=$build_dir/fixtures/ssg_abc.vgm" +SSG
run_full suppressed "+VGM=$build_dir/fixtures/suppressed_pcm.vgm" +SUPPRESSED
run_full olga "+VGM=$olga" +OLGA

# Stable shell title and video contracts remain unchanged.
sh tests/test_megavgm_title_integration.sh
iverilog -g2012 -Wall -s tb_megavgm_video_timing \
  -o "$build_dir/video.vvp" rtl/megavgm_video_timing.sv \
  tb/tb_megavgm_video_timing.sv
vvp "$build_dir/video.vvp"

python3 tb/golden_player_shell_v1_1/stage_c/audit_stage_c_v1_1.py
git diff --check
git diff --cached --check

echo 'GOLDEN_SHELL_V1_1_STAGE_C_NON_QUARTUS_RESULT PASS'
