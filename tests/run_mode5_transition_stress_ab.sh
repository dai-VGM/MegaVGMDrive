#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_tmp="$(mktemp -d "${TMPDIR:-/tmp}/mode5-transition-stress-ab.XXXXXX")"
trap 'rm -rf "$test_tmp"' EXIT
cd "$repo_root"

baseline_commit=04910c09ac27d4ee2019e5477af0dc36423b5eec
if [[ ${1:-} == --policy-rearm ]]; then
  baseline_commit=4c4a77c3c67045cb295b8d7ed3d747ce80f29033
fi
git archive --format=tar --output="$test_tmp/baseline.tar" \
    "$baseline_commit" rtl/mister_vgm_md_top.sv
tar -xf "$test_tmp/baseline.tar" -C "$test_tmp"

common_sources=(
  rtl/megavgm_playlist_status_export.sv
  rtl/vgm_file_loader.sv
  rtl/vgm_bram_read_adapter.sv
  rtl/vgm_ddram_backend.sv
  rtl/vgm_loaded_player.sv
  rtl/md_sound_module.sv
  rtl/vgm_region_player.sv
  rtl/ym2203_sound_module.sv
  rtl/ym2203_dynamic_cen.sv
  rtl/ym2151_prewait_audio_gate.sv
  rtl/genesis_audio/jt12/*.v
  rtl/genesis_audio/jt12/adpcm/*.v
  rtl/genesis_audio/jt12/mixer/*.v
  rtl/genesis_audio/jt89/*.v
  rtl/genesis_audio/jt49/*.v
  rtl/genesis_audio/filters/*.v
)

if [[ ${1:-} == --policy-rearm ]]; then
  for profile in before after; do
    top_source=rtl/mister_vgm_md_top.sv
    if [[ $profile == before ]]; then top_source="$test_tmp/rtl/mister_vgm_md_top.sv"; fi
    iverilog -g2012 -DSIMULATION -s tb_mode5_load_while_playing_session \
      -o "$test_tmp/$profile.vvp" tb/tb_mode5_load_while_playing_session.sv \
      "$top_source" "${common_sources[@]}" > "$test_tmp/$profile-compile.log" 2>&1
    if vvp "$test_tmp/$profile.vvp" +POLICY_REARM_CHECK > "$test_tmp/$profile.log"; then
      [[ $profile == after ]]
      grep '^PASS policy record' "$test_tmp/$profile.log"
    else
      [[ $profile == before ]]
      grep '^FAIL index-2 completion released ended-session mute' "$test_tmp/$profile.log"
    fi
  done
  echo 'PASS policy rearm A/B: old=FAIL reproduced fixed=PASS'
  exit 0
fi

run_profile() {
  local profile="$1"
  local top_source="$2"
  shift 2
  iverilog -g2012 -DSIMULATION "$@" \
    -s tb_mode5_load_while_playing_session \
    -o "$test_tmp/$profile.vvp" \
    tb/tb_mode5_load_while_playing_session.sv \
    "$top_source" "${common_sources[@]}"
  vvp "$test_tmp/$profile.vvp" | tee "$test_tmp/$profile.log"
  grep -q '^STRESS_PASS sessions=50 ' "$test_tmp/$profile.log"
  grep -q '^PASS tb_mode5_load_while_playing_session$' \
      "$test_tmp/$profile.log"
}

run_profile 9f30ca6 rtl/mister_vgm_md_top.sv
run_profile 04910c0 "$test_tmp/rtl/mister_vgm_md_top.sv" -DBASELINE_04910

echo "PASS run_mode5_transition_stress_ab"
