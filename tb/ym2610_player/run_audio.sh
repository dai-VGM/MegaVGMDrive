#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "$0")/../.." && pwd)
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/ym2610-audio.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT

(
  cd "$repo_dir"
  iverilog -g2012 -s tb_ym2610_player_core \
    -o "$build_dir/core.vvp" \
    -f tb/ym2610_player/ym2610_player_sources.f \
    tb/ym2610_player/tb_ym2610_player_core.sv
)
python3 "$repo_dir/tools/generate_ym2610_test_vgms.py" "$build_dir/fixtures" >/dev/null

cases=(
  "fm_standard.vgm:FM"
  "ssg_abc_raw.vgm:SSG"
  "adpcma.vgm:A"
  "adpcmb.vgm:B"
  "adpcma_b_simultaneous.vgm:AB"
  "b_compatible.vgm:BCOMP"
  "standard_all_raw.vgm:STANDARD"
)
for item in "${cases[@]}"; do
  fixture=${item%%:*}
  expect=${item##*:}
  pids=()
  for run in 1 2 3; do
    vvp "$build_dir/core.vvp" "+VGM=$build_dir/fixtures/$fixture" "+EXPECT=$expect" \
      >"$build_dir/$expect-$run.log" &
    pids+=("$!")
  done
  for pid in "${pids[@]}"; do
    wait "$pid"
  done
  sed -n '/^CORE_RESULT/p' "$build_dir/$expect-1.log"
  diff -u <(sed -n 's/ result=PASS$/ result=PASS/p' "$build_dir/$expect-1.log") \
          <(sed -n 's/ result=PASS$/ result=PASS/p' "$build_dir/$expect-2.log")
  diff -u <(sed -n 's/ result=PASS$/ result=PASS/p' "$build_dir/$expect-1.log") \
          <(sed -n 's/ result=PASS$/ result=PASS/p' "$build_dir/$expect-3.log")
done
for fixture in b_only_keyon.vgm b_only_setup.vgm dual_unsupported.vgm \
               unknown_register.vgm unsupported_opcode.vgm \
               block_out_of_range.vgm; do
  vvp "$build_dir/core.vvp" "+VGM=$build_dir/fixtures/$fixture" "+EXPECT=REJECT"
done
vvp "$build_dir/core.vvp" "+VGM=$build_dir/fixtures/lifecycle.vgm" "+EXPECT=LIFE"
vvp "$build_dir/core.vvp" "+VGM=$build_dir/fixtures/loop.vgm" "+EXPECT=LOOP"
echo "YM2610_AUDIO_DETERMINISM cases=7 runs=3 result=PASS"
echo "YM2610_CONTRACT rejects=6 lifecycle=PASS loop=PASS result=PASS"
