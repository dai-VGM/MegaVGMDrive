#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
vgm_file="${1:-/Users/daizo/Music/Space_Harrier_(Hang-On)/02 Theme.vgm}"
test_tmp="$(mktemp -d "${TMPDIR:-/tmp}/space-harrier-ym2203.XXXXXX")"
trap 'rm -rf "$test_tmp"' EXIT

cd "$repo_dir"
if [[ ! -f "$vgm_file" ]]; then
  echo "VGM file not found: $vgm_file" >&2
  exit 1
fi

python3 tools/analyze_ym2203_vgm.py "$vgm_file"
for start in 148 157 169; do
  python3 tools/extract_ym2203_balance_window.py \
    "$vgm_file" "$test_tmp/window-$start.vgm" \
    --start "$start" --duration 1 --preroll 2
done
python3 tools/extract_ym2203_balance_window.py \
  "$vgm_file" "$test_tmp/full-pass.vgm" --full-pass

defines=(
  -DSIMULATION
  -DMEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
  -DMEGAVGMDRIVE_PRODUCTION_AUDIO_BUILD
  -DMEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
  -DMEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
  -DMEGAVGMDRIVE_SEGAPCM_MIN_DEBUG_PROBE
  -DMD_JT12_CEN_NTSC_TEST=1
)

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
  third_party/jt51/hdl/*.v
  third_party/jt51/ver/common/sep32.v
  third_party/jt51/ver/common/sep32_cnt.v
  rtl/genesis_audio/filters/*.v
  rtl/genesis_audio/jt12/*.v
  rtl/genesis_audio/jt12/adpcm/jt10_adpcm_div.v
  rtl/genesis_audio/jt12/mixer/*.v
  rtl/genesis_audio/jt49/*.v
  rtl/genesis_audio/jt89/*.v
)

iverilog -g2012 -Wall -I. "${defines[@]}" \
  -s tb_space_harrier_ym2203_balance \
  -o "$test_tmp/icarus-compile.vvp" \
  "${sources[@]}" tb/tb_space_harrier_ym2203_balance.sv
echo "ICARUS_COMPILE_PASS"

verilator_build() {
  local output_dir="$1"
  local wait_hz="$2"
  local measure_start="$3"
  local measure_end="$4"
  verilator --binary --timing --build-jobs 4 --quiet --quiet-build \
    -Wno-fatal -Wno-lint -Wno-style -Wno-TIMESCALEMOD \
    -I. "${defines[@]}" \
    -GWAIT_HZ="$wait_hz" \
    -GMEASURE_START_SAMPLES="$measure_start" \
    -GMEASURE_END_SAMPLES="$measure_end" \
    --top-module tb_space_harrier_ym2203_balance \
    -Mdir "$output_dir" \
    "${sources[@]}" tb/tb_space_harrier_ym2203_balance.sv
}

verilator_build "$test_tmp/faithful" 44100 88200 132300
for start in 148 157 169; do
  "$test_tmp/faithful/Vtb_space_harrier_ym2203_balance" \
    "+VGM=$test_tmp/window-$start.vgm" +MAX_CYCLES=150000000 \
    +AUDIO_SELECT=0 > "$test_tmp/window-$start-normal.log"
  grep -E '^(BALANCE_|PASS )' "$test_tmp/window-$start-normal.log"
done
for selector in 1 3; do
  "$test_tmp/faithful/Vtb_space_harrier_ym2203_balance" \
    "+VGM=$test_tmp/window-157.vgm" +MAX_CYCLES=150000000 \
    "+AUDIO_SELECT=$selector" > "$test_tmp/window-157-$selector.log"
  grep -E '^(BALANCE_|PASS )' "$test_tmp/window-157-$selector.log"
done

field_from_log() {
  local log_file="$1"
  local record="$2"
  local field_name="$3"
  awk -v record="$record" -v key="$field_name" '
    $1 == record {
      for (i = 1; i <= NF; i++) {
        split($i, pair, "=")
        if (pair[1] == key) {
          print pair[2]
          exit
        }
      }
    }
  ' "$log_file"
}

normal_log="$test_tmp/window-157-normal.log"
for selector in 1 3; do
  selector_log="$test_tmp/window-157-$selector.log"
  for record_field in \
    'BALANCE_RAW hash' \
    'BALANCE_FM hash' \
    'BALANCE_INTERNAL_FM hash' \
    'BALANCE_PSG hash' \
    'BALANCE_PCM hash' \
    'BALANCE_CONTROL waits' \
    'BALANCE_CONTROL commands' \
    'BALANCE_CONTROL ym_parser' \
    'BALANCE_CONTROL ym_accept' \
    'BALANCE_CONTROL ym_complete' \
    'BALANCE_CONTROL c0_parser' \
    'BALANCE_CONTROL end_pc' \
    'BALANCE_CONTROL sample_valid'; do
    read -r record field <<< "$record_field"
    normal_value="$(field_from_log "$normal_log" "$record" "$field")"
    selector_value="$(field_from_log "$selector_log" "$record" "$field")"
    if [[ "$normal_value" != "$selector_value" ]]; then
      echo "selector changed $record $field: normal=$normal_value selector=$selector_value" >&2
      exit 1
    fi
  done
done
echo "SELECTOR_INVARIANCE_PASS"

# The source loops at END. Clear only its two loop header fields, preserve all
# commands, and run one complete parser pass. Ten MHz is the fastest valid
# rising-edge wait cadence with the 20 MHz simulation clock.
verilator_build "$test_tmp/full" 10000000 0 9835567
"$test_tmp/full/Vtb_space_harrier_ym2203_balance" \
  "+VGM=$test_tmp/full-pass.vgm" +MAX_CYCLES=150000000 \
  +AUDIO_SELECT=0 > "$test_tmp/full-pass.log"
grep -E '^(BALANCE_|PASS )' "$test_tmp/full-pass.log"

for check in \
  'waits 9835567' \
  'commands 93625' \
  'ym_parser 20900' \
  'ym_accept 20900' \
  'ym_complete 20900' \
  'c0_parser 32471' \
  'end_pc 042ce5'; do
  read -r field expected <<< "$check"
  actual="$(field_from_log "$test_tmp/full-pass.log" BALANCE_CONTROL "$field")"
  if [[ "$actual" != "$expected" ]]; then
    echo "full-pass mismatch $field: expected=$expected actual=$actual" >&2
    exit 1
  fi
done
echo "FULL_PASS_CONTROL_PASS"
