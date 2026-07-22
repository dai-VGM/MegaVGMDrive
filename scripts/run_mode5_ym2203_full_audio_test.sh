#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_tmp="$(mktemp -d "${TMPDIR:-/tmp}/mode5-ym2203-full-audio.XXXXXX")"
trap 'rm -rf "$test_tmp"' EXIT

cd "$repo_dir"

defines=(
  -DSIMULATION
  -DMEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
  -DMEGAVGMDRIVE_PRODUCTION_AUDIO_BUILD
  -DMEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
  -DMEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
  -DMEGAVGMDRIVE_SEGAPCM_MIN_DEBUG_PROBE
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

for chip_clock in 4000000 3579545; do
  for audio_select in 0 3 1; do
    name="$chip_clock-$audio_select"
    if ! iverilog -g2012 -Wall -I. "${defines[@]}" \
      -Ptb_mode5_ym2203_full_audio.CHIP_CLK_HZ="$chip_clock" \
      -Ptb_mode5_ym2203_full_audio.AUDIO_SELECT="$audio_select" \
      -s tb_mode5_ym2203_full_audio \
      -o "$test_tmp/$name.vvp" \
      "${sources[@]}" \
      tb/tb_mode5_ym2203_full_audio.sv \
      >"$test_tmp/$name.compile.log" 2>&1; then
      sed -n '1,240p' "$test_tmp/$name.compile.log"
      exit 1
    fi
    (
      cd "$test_tmp"
      vvp "$name.vvp"
    ) | tee "$test_tmp/$name.run.log"
  done
done

field_from_log() {
  local log_file="$1"
  local field_name="$2"
  awk -v key="$field_name" '
    /^FULL_AUDIO_STATS / {
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

for chip_clock in 4000000 3579545; do
  normal_log="$test_tmp/$chip_clock-0.run.log"
  pcm_log="$test_tmp/$chip_clock-3.run.log"
  fm_log="$test_tmp/$chip_clock-1.run.log"

  normal_raw_hash="$(field_from_log "$normal_log" raw_hash)"
  pcm_raw_hash="$(field_from_log "$pcm_log" raw_hash)"
  fm_raw_hash="$(field_from_log "$fm_log" raw_hash)"
  normal_raw_samples="$(field_from_log "$normal_log" raw_samples)"
  pcm_raw_samples="$(field_from_log "$pcm_log" raw_samples)"
  fm_raw_samples="$(field_from_log "$fm_log" raw_samples)"
  normal_final_hash="$(field_from_log "$normal_log" final_hash)"
  fm_final_hash="$(field_from_log "$fm_log" final_hash)"
  normal_final_samples="$(field_from_log "$normal_log" final_samples)"
  pcm_final_samples="$(field_from_log "$pcm_log" final_samples)"
  fm_final_samples="$(field_from_log "$fm_log" final_samples)"
  pcm_nonzero="$(field_from_log "$pcm_log" final_nonzero)"

  if [[ "$normal_raw_hash" != "$pcm_raw_hash" ||
        "$normal_raw_hash" != "$fm_raw_hash" ||
        "$normal_raw_samples" != "$pcm_raw_samples" ||
        "$normal_raw_samples" != "$fm_raw_samples" ]]; then
    echo "FAIL selector changed YM2203 raw core activity clock=$chip_clock"
    exit 1
  fi
  if [[ "$normal_final_hash" != "$fm_final_hash" ]]; then
    echo "FAIL Normal and FM Only final samples differ clock=$chip_clock"
    exit 1
  fi
  if [[ "$normal_final_samples" != "$pcm_final_samples" ||
        "$normal_final_samples" != "$fm_final_samples" ]]; then
    echo "FAIL selector changed final sample-valid count clock=$chip_clock"
    exit 1
  fi
  if [[ "$pcm_nonzero" != "0" ]]; then
    echo "FAIL PCM Only was not silent clock=$chip_clock"
    exit 1
  fi
  echo "SELECTOR_COMPARE clock=$chip_clock raw_hash=$normal_raw_hash final_hash=$normal_final_hash samples=$normal_final_samples pcm_nonzero=$pcm_nonzero"
done

verilator --lint-only --timing -Wall -Wno-fatal -I. "${defines[@]}" \
  --top-module tb_mode5_ym2203_full_audio \
  tb/tb_mode5_ym2203_full_audio.sv \
  "${sources[@]}" \
  >"$test_tmp/verilator.log" 2>&1

warning_count="$(grep -c '^%Warning' "$test_tmp/verilator.log" || true)"
echo "VERILATOR_PASS warnings=$warning_count"
