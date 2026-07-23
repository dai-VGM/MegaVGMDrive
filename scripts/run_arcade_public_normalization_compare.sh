#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
vgm_file="${1:-/Users/daizo/Music/Space_Harrier_(Hang-On)/02 Theme.vgm}"
test_tmp="$(mktemp -d "${TMPDIR:-/tmp}/arcade-public-normalization.XXXXXX")"
trap 'rm -rf "$test_tmp"' EXIT
baseline_commit="111cfa6d4d0058cf296a557fd8928e6d113326da"
baseline_dir="${ARCADE_BASELINE_REPO:-}"

cd "$repo_dir"
if [[ -n "$baseline_dir" ]]; then
  if [[ "$(git -C "$baseline_dir" rev-parse HEAD)" != "$baseline_commit" ]]; then
    echo "Baseline worktree is not 111cfa6: $baseline_dir" >&2
    exit 2
  fi
else
  baseline_dir="$test_tmp/baseline-source"
  mkdir -p "$baseline_dir"
  git archive "$baseline_commit" | tar -x -C "$baseline_dir"
fi
if [[ ! -f "$vgm_file" ]]; then
  echo "VGM file not found: $vgm_file" >&2
  exit 2
fi

python3 "$repo_dir/tools/extract_ym2203_balance_window.py" \
  "$vgm_file" "$test_tmp/window.vgm" --start 157 --duration 1 --preroll 2

build_profile() {
  local source_dir="$1"
  local output_dir="$2"
  local baseline_define="$3"
  (
    cd "$source_dir"
    sources=(
      rtl/mister_vgm_md_top.sv
      rtl/vgm_region_player.sv
      rtl/vgm_file_loader.sv
      rtl/vgm_bram_read_adapter.sv
      rtl/vgm_ddram_backend.sv
      rtl/vgm_c0_lab_backend.sv
      rtl/vgm_loaded_player.sv
      rtl/md_sound_module.sv
      rtl/mode5_ym2203_audio_mixer.sv
      rtl/ym2203_dynamic_cen.sv
      rtl/ym2203_sound_module.sv
      rtl/ym2151_sound_module.sv
      rtl/segapcm_sound_module.sv
      third_party/jtcores/cores/outrun/hdl/jtoutrun_pcm.v
      third_party/jtcores/modules/jtframe/hdl/ram/jtframe_dual_ram.v
      "$repo_dir"/third_party/jt51/hdl/*.v
      "$repo_dir"/third_party/jt51/ver/common/sep32.v
      "$repo_dir"/third_party/jt51/ver/common/sep32_cnt.v
      rtl/genesis_audio/filters/*.v
      rtl/genesis_audio/jt12/*.v
      rtl/genesis_audio/jt12/adpcm/jt10_adpcm_div.v
      rtl/genesis_audio/jt12/mixer/*.v
      rtl/genesis_audio/jt49/*.v
      rtl/genesis_audio/jt89/*.v
    )
    defines=(
      -DSIMULATION
      -DMEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
      -DMEGAVGMDRIVE_PRODUCTION_AUDIO_BUILD
      -DMEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
      -DMEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
      -DMEGAVGMDRIVE_SEGAPCM_MIN_DEBUG_PROBE
      -DMD_JT12_CEN_NTSC_TEST=1
    )
    if [[ "$baseline_define" == "1" ]]; then
      defines+=( -DARCADE_BASELINE_PUBLIC_SHIFT2=1 )
    fi
    verilator --binary --timing --build-jobs 4 --quiet --quiet-build \
      -Wno-fatal -Wno-lint -Wno-style -Wno-TIMESCALEMOD \
      -I. "${defines[@]}" \
      -GWAIT_HZ=44100 -GMEASURE_START_SAMPLES=88200 \
      -GMEASURE_END_SAMPLES=132300 \
      --top-module tb_space_harrier_ym2203_balance \
      -Mdir "$output_dir" "${sources[@]}" \
      "$repo_dir/tb/tb_space_harrier_ym2203_balance.sv"
  )
}

build_profile "$baseline_dir" "$test_tmp/baseline" 1
build_profile "$repo_dir" "$test_tmp/current" 0

for selector in 0 1 3; do
  "$test_tmp/baseline/Vtb_space_harrier_ym2203_balance" \
    "+VGM=$test_tmp/window.vgm" +MAX_CYCLES=150000000 \
    "+AUDIO_SELECT=$selector" >"$test_tmp/baseline-$selector.log"
  "$test_tmp/current/Vtb_space_harrier_ym2203_balance" \
    "+VGM=$test_tmp/window.vgm" +MAX_CYCLES=150000000 \
    "+AUDIO_SELECT=$selector" >"$test_tmp/current-$selector.log"
  grep '^BALANCE_' "$test_tmp/baseline-$selector.log" \
    >"$test_tmp/baseline-$selector.stats"
  grep '^BALANCE_' "$test_tmp/current-$selector.log" \
    >"$test_tmp/current-$selector.stats"
  if ! cmp -s "$test_tmp/baseline-$selector.stats" \
              "$test_tmp/current-$selector.stats"; then
    echo "ARCADE_PUBLIC_NORMALIZATION_FAIL selector=$selector" >&2
    diff -u "$test_tmp/baseline-$selector.stats" \
            "$test_tmp/current-$selector.stats" >&2 || true
    exit 1
  fi
  final_hash="$(awk '$1 == "BALANCE_FINAL" {
    for (i = 1; i <= NF; i++) if ($i ~ /^hash=/) {sub(/^hash=/, "", $i); print $i}
  }' "$test_tmp/current-$selector.stats")"
  echo "ARCADE_PUBLIC_NORMALIZATION_PASS selector=$selector final_hash=$final_hash"
done
