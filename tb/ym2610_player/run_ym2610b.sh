#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "$0")/../.." && pwd)
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/ym2610b.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT

cd "$repo_dir"
python3 tools/generate_ym2610_test_vgms.py "$build_dir/fixtures" >/dev/null

iverilog -g2012 -s tb_ym2610b_acc -o "$build_dir/acc.vvp" \
  rtl/genesis_audio/jt12/jt12_single_acc.v \
  rtl/ym2610_hw0/ym2610_hw0_jt10_acc.v \
  tb/ym2610_player/tb_ym2610b_acc.sv
vvp "$build_dir/acc.vvp"

iverilog -g2012 -s tb_ym2610_player_core \
  -o "$build_dir/ym2610.vvp" \
  -f tb/ym2610_player/ym2610_player_sources.f \
  tb/ym2610_player/tb_ym2610_player_core.sv
iverilog -g2012 -DYM2610B_TEST -s tb_ym2610_player_core \
  -o "$build_dir/ym2610b.vvp" \
  -f tb/ym2610_player/ym2610_player_sources.f \
  tb/ym2610_player/tb_ym2610_player_core.sv

run_b_case() {
  local fixture=$1
  local expect=$2
  local name=${fixture%.vgm}
  vvp "$build_dir/ym2610b.vvp" \
    "+VGM=$build_dir/fixtures/$fixture" "+EXPECT=$expect" \
    >"$build_dir/$name.log"
  sed -n '/^CORE_RESULT/p' "$build_dir/$name.log"
}

for channel in 1 2 3 4 5 6; do
  run_b_case "ym2610b_fm_ch${channel}.vgm" BFM
done
run_b_case ym2610b_six_fm.vgm BSIX
vvp "$build_dir/ym2610b.vvp" \
  "+VGM=$build_dir/fixtures/ym2610b_six_fm.vgm" +EXPECT=BSIX \
  >"$build_dir/ym2610b_six_fm_repeat.log"
diff -u <(sed -n '/^CORE_RESULT/p' "$build_dir/ym2610b_six_fm.log") \
        <(sed -n '/^CORE_RESULT/p' "$build_dir/ym2610b_six_fm_repeat.log")

vvp "$build_dir/ym2610b.vvp" \
  "+VGM=$build_dir/fixtures/ym2610_unflagged_extra_fm.vgm" +EXPECT=REJECT
run_b_case b_compatible.vgm BCOMP
run_b_case standard_all_raw.vgm STANDARD

vvp "$build_dir/ym2610.vvp" \
  "+VGM=$build_dir/fixtures/b_compatible.vgm" +EXPECT=BCOMP \
  >"$build_dir/b_compatible_standard_product.log"
standard_hash=$(sed -n 's/.*audio_hash=\([0-9a-f]*\).*/\1/p' \
  "$build_dir/b_compatible_standard_product.log")
ym2610b_hash=$(sed -n 's/.*audio_hash=\([0-9a-f]*\).*/\1/p' \
  "$build_dir/b_compatible.log")
test -n "$standard_hash" && test "$standard_hash" = "$ym2610b_hash"

python3 tb/ym2610_player/elaborate_ym2610b_top.py
python3 tb/ym2610_player/audit_ym2610b.py
git diff --check
echo "YM2610B_FOCUSED channels=6 simultaneous=PASS deterministic=PASS mode=PASS result=PASS"
echo "YM2610B_BOUNDARY standard_hash=$standard_hash b_hash=$ym2610b_hash ADPCM_SSG=PASS result=PASS"
