#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_tmp="$(mktemp -d "${TMPDIR:-/tmp}/mode5-audio-handoff-ab.XXXXXX")"
trap 'rm -rf "$test_tmp"' EXIT
cd "$repo_root"

for revision in 04910c09ac27d4ee2019e5477af0dc36423b5eec \
                9f30ca68b288cb394cb720af0a4d3718000396c7; do
  mkdir -p "$test_tmp/$revision"
  git archive --format=tar --output="$test_tmp/$revision/top.tar" \
    "$revision" rtl/mister_vgm_md_top.sv
  tar -xf "$test_tmp/$revision/top.tar" -C "$test_tmp/$revision"
done

common_defines=(
  -DSIMULATION
  -DPRODUCTION_AUDIO_HANDOFF_TRACE=1
  -DMEGAVGMDRIVE_PRODUCTION_AUDIO_BUILD=1
  -DMEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD=1
  -DMEGAVGMDRIVE_SEGAPCM_SMOKE_TEST=1
  -DMEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST=1
  -DMEGAVGMDRIVE_SEGAPCM_MIN_DEBUG_PROBE=1
  -DMEGAVGMDRIVE_SEGAPCM_AB1_MAME_SCRATCH=1
  -DMEGAVGMDRIVE_SEGAPCM_AB2_MAME_NONLOOP_END=1
  -DMEGAVGMDRIVE_SEGAPCM_SMOKE_PARSER_RUN_TEST=1
  -DMEGAVGMDRIVE_SEGAPCM_C0DRIVE_TICK_SLOW=1
  -DMEGAVGMDRIVE_START_HOLD_NO_BUSY_CLEAR=1
  -DMEGAVGMDRIVE_DIRECT_PLAYER_START_DEBUG=1
  -DMD_JT12_CEN_NTSC_TEST=1
)

common_sources=(
  tb/tb_mode5_load_while_playing_session.sv
  rtl/megavgm_playlist_status_export.sv
  rtl/mode5_audio_session_lane_gate.sv
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
  rtl/ym2151_prewait_audio_gate.sv
  rtl/segapcm_sound_module.sv
  third_party/jtcores/cores/outrun/hdl/jtoutrun_pcm.v
  third_party/jtcores/modules/jtframe/hdl/ram/jtframe_dual_ram.v
  third_party/jt51/hdl/*.v
  third_party/jt51/ver/common/sep32.v
  third_party/jt51/ver/common/sep32_cnt.v
  rtl/genesis_audio/filters/*.v
  rtl/genesis_audio/jt12/adpcm/*.v
  rtl/genesis_audio/jt12/*.v
  rtl/genesis_audio/jt12/mixer/*.v
  rtl/genesis_audio/jt49/*.v
  rtl/genesis_audio/jt89/*.v
)

compile_profile() {
  local profile="$1"
  local top_source="$2"
  shift 2
  iverilog -g2012 "${common_defines[@]}" "$@" \
    -s tb_mode5_load_while_playing_session \
    -o "$test_tmp/$profile.vvp" \
    "${common_sources[@]:0:2}" "$top_source" \
    "${common_sources[@]:2}" >"$test_tmp/$profile-compile.log" 2>&1
}

compile_profile fixed rtl/mister_vgm_md_top.sv
compile_profile 9f30ca6 \
  "$test_tmp/9f30ca68b288cb394cb720af0a4d3718000396c7/rtl/mister_vgm_md_top.sv"
compile_profile 04910c0 \
  "$test_tmp/04910c09ac27d4ee2019e5477af0dc36423b5eec/rtl/mister_vgm_md_top.sv" \
  -DBASELINE_04910=1

for profile in fixed 9f30ca6 04910c0; do
  for path in MANUAL_NEXT NATURAL_EOF LOOP_LIMIT; do
    if ! vvp "$test_tmp/$profile.vvp" "+PATH=$path" > \
        "$test_tmp/$profile-$path.log"; then
      cat "$test_tmp/$profile-$path.log" >&2
      exit 1
    fi
    if ! grep -q '^PASS production audio handoff trace ' \
        "$test_tmp/$profile-$path.log"; then
      cat "$test_tmp/$profile-$path.log" >&2
      exit 1
    fi
  done
done

for path in MANUAL_NEXT NATURAL_EOF LOOP_LIMIT; do
  fixed_log="$test_tmp/fixed-$path.log"
  old_9f_log="$test_tmp/9f30ca6-$path.log"
  old_049_log="$test_tmp/04910c0-$path.log"
  if ! grep -q "path=$path session=2 sample=0 .*out_l=0 out_r=0" \
      "$fixed_log"; then
    cat "$fixed_log" >&2
    exit 1
  fi
  if grep -Eq "path=$path session=2 sample=([0-9]|[12][0-9]|3[01]) .*sega_valid=0 .*out_l=-?[1-9][0-9]*" \
      "$fixed_log"; then
    echo "fixed profile leaked stale lane in $path" >&2
    cat "$fixed_log" >&2
    exit 1
  fi
  if ! grep -q "path=$path session=2 sample=0 .*out_l=0 out_r=0" \
      "$old_9f_log" ||
      ! grep -q "path=$path session=2 sample=1 .*sega_valid=0 .*out_l=8000 out_r=-8000" \
      "$old_9f_log"; then
    cat "$old_9f_log" >&2
    exit 1
  fi
  if ! grep -q "path=$path session=2 sample=0 .*sega_valid=0 .*out_l=8000 out_r=-8000" \
      "$old_049_log"; then
    cat "$old_049_log" >&2
    exit 1
  fi
done

for path in MANUAL_NEXT NATURAL_EOF LOOP_LIMIT; do
  for profile in fixed 9f30ca6 04910c0; do
    grep -E "path=$path session=2 sample=[01] " \
      "$test_tmp/$profile-$path.log" |
      sed "s/^/$profile /"
  done
done

echo "PASS run_mode5_audio_handoff_samples_ab"
