#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "$0")/../.." && pwd)
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/ym2610-title.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT

python3 "$repo_dir/tools/generate_ym2610_test_vgms.py" "$build_dir/fixtures" >/dev/null
iverilog -g2012 -s tb_ym2610_player_title_file \
  -o "$build_dir/title-file.vvp" \
  "$repo_dir/rtl/megavgm_title_receiver.sv" \
  "$repo_dir/tb/ym2610_player/tb_ym2610_player_title_file.sv"
vvp "$build_dir/title-file.vvp" \
  "+VGM=$build_dir/fixtures/ssg_abc_prepared.vgm" \
  "+TITLE=1" "+DIR=Synthetic" "+BASE=SSG A B C"
vvp "$build_dir/title-file.vvp" \
  "+VGM=$build_dir/fixtures/ssg_abc_raw.vgm" "+TITLE=0"
if [[ -f "/Users/daizo/Music/03 Olga Breeze.vgm" ]]; then
  vvp "$build_dir/title-file.vvp" \
    "+VGM=/Users/daizo/Music/03 Olga Breeze.vgm" \
    "+TITLE=1" "+DIR=Darius_II_(Arcade)" "+BASE=03 Olga Breeze"
fi

iverilog -g2012 -s tb_megavgm_title_renderer \
  -o "$build_dir/title-renderer.vvp" \
  "$repo_dir/rtl/megavgm_font5x7.sv" \
  "$repo_dir/rtl/megavgm_title_renderer.sv" \
  "$repo_dir/tb/tb_megavgm_title_renderer.sv"
vvp "$build_dir/title-renderer.vvp"
echo "YM2610_TITLE raw=PASS prepared=PASS geometry=PASS navy=000818 result=PASS"
