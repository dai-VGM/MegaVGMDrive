#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_tmp="$(mktemp -d "${TMPDIR:-/tmp}/md-historical-profile.XXXXXX")"
trap 'rm -rf "$test_tmp"' EXIT
historical_commit="91193848fa85e8f2e7964628a5f792890dac4300"
historical_dir="${MD_HISTORICAL_REPO:-}"

cd "$repo_dir"
if [[ -n "$historical_dir" ]]; then
  historical_head="$(git -C "$historical_dir" rev-parse HEAD)"
  if [[ "$historical_head" != "$historical_commit" ]]; then
    echo "Unexpected historical HEAD: $historical_head" >&2
    exit 2
  fi
else
  historical_dir="$test_tmp/historical"
  mkdir -p "$historical_dir"
  git archive "$historical_commit" | tar -x -C "$historical_dir"
fi

sources=(
  rtl/md_sound_module.sv
  rtl/genesis_audio/filters/*.v
  rtl/genesis_audio/jt12/jt12*.v
  rtl/genesis_audio/jt12/adpcm/jt10_adpcm_div.v
  rtl/genesis_audio/jt12/mixer/*.v
  rtl/genesis_audio/jt89/*.v
)
current_defines=(
  -DSIMULATION
  -DMEGAVGMDRIVE_PRODUCTION_AUDIO_BUILD=1
  -DMD_JT12_CEN_NTSC_TEST=1
)
historical_defines=(
  -DSIMULATION
  -DMD_JT12_CEN_NTSC_TEST=1
  -DMD_JT12_HIFI_PCM_TEST=1
  -DMD_AUDIO_OUTPUT_SHIFT_0_TEST=1
  -DMD_AUDIO_GENMIX_OUTPUT_GAIN_2X_TEST=1
  -DMD_AUDIO_GAIN_OSD_TEST=1
  -DMD_AUDIO_PSG_ATTEN_075_TEST=1
  -DMD_AUDIO_PSG_LEVEL_OSD_TEST=1
  -DMD_AUDIO_GENMIX_NO_UPRATE_TEST=1
)

iverilog -g2012 -I. "${current_defines[@]}" \
  -s tb_md_historical_profile_compare -o "$test_tmp/current.vvp" \
  "${sources[@]}" tb/tb_md_historical_profile_compare.sv \
  >"$test_tmp/current-compile.log" 2>&1
(
  cd "$historical_dir"
  iverilog -g2012 -I. "${historical_defines[@]}" \
    -s tb_md_historical_profile_compare -o "$test_tmp/historical.vvp" \
    "${sources[@]}" "$repo_dir/tb/tb_md_historical_profile_compare.sv" \
    >"$test_tmp/historical-compile.log" 2>&1
)
echo "ICARUS_COMPILE_PASS current historical=91193848"

for fixture in 0 1 2; do
  for gain in 0 1; do
    current_samples="$test_tmp/current-$fixture-$gain.txt"
    historical_samples="$test_tmp/historical-$fixture-$gain.txt"
    vvp "$test_tmp/current.vvp" +FIXTURE="$fixture" +GAIN="$gain" \
      +SAMPLE_FILE="$current_samples"
    vvp "$test_tmp/historical.vvp" +FIXTURE="$fixture" +GAIN="$gain" \
      +SAMPLE_FILE="$historical_samples"
    if ! cmp -s "$current_samples" "$historical_samples"; then
      echo "MD_HISTORICAL_COMPARE_FAIL fixture=$fixture gain=$gain" >&2
      diff -u "$historical_samples" "$current_samples" | head -80 >&2 || true
      exit 1
    fi
    hash="$(shasum -a 256 "$current_samples" | awk '{print $1}')"
    echo "MD_HISTORICAL_COMPARE_PASS fixture=$fixture gain=$gain sha256=$hash"
  done
done

verilator --lint-only --timing -Wall -Wno-fatal -I. \
  "${current_defines[@]}" --top-module tb_md_historical_profile_compare \
  tb/tb_md_historical_profile_compare.sv "${sources[@]}" \
  >"$test_tmp/current-verilator.log" 2>&1
(
  cd "$historical_dir"
  verilator --lint-only --timing -Wall -Wno-fatal -I. \
    "${historical_defines[@]}" \
    --top-module tb_md_historical_profile_compare \
    "$repo_dir/tb/tb_md_historical_profile_compare.sv" "${sources[@]}" \
    >"$test_tmp/historical-verilator.log" 2>&1
)
current_warnings="$(grep -c '^%Warning' "$test_tmp/current-verilator.log" || true)"
historical_warnings="$(grep -c '^%Warning' "$test_tmp/historical-verilator.log" || true)"
echo "VERILATOR_PASS current_warnings=$current_warnings historical_warnings=$historical_warnings"
