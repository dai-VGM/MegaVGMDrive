#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_tmp="$(mktemp -d "${TMPDIR:-/tmp}/mode5-ym2203-mixer.XXXXXX")"
trap 'rm -rf "$test_tmp"' EXIT

cd "$repo_dir"

iverilog -g2012 -Wall -I. \
  -s tb_mode5_ym2203_audio_mixer \
  -o "$test_tmp/mixer.vvp" \
  rtl/mode5_ym2203_audio_mixer.sv \
  tb/tb_mode5_ym2203_audio_mixer.sv

vvp "$test_tmp/mixer.vvp"

verilator --lint-only --timing -Wall -Wno-fatal -I. \
  --top-module tb_mode5_ym2203_audio_mixer \
  tb/tb_mode5_ym2203_audio_mixer.sv \
  rtl/mode5_ym2203_audio_mixer.sv
