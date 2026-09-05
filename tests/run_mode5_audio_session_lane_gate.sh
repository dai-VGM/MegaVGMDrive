#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_tmp="$(mktemp -d "${TMPDIR:-/tmp}/mode5-audio-session-lane.XXXXXX")"
trap 'rm -rf "$test_tmp"' EXIT

cd "$repo_root"
iverilog -g2012 \
  -s tb_mode5_audio_session_lane_gate \
  -o "$test_tmp/test.vvp" \
  tb/tb_mode5_audio_session_lane_gate.sv \
  rtl/mode5_audio_session_lane_gate.sv
vvp "$test_tmp/test.vvp"
