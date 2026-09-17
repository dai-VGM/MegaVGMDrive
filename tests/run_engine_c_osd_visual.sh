#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
out=${TMPDIR:-/tmp}/megavgm-engine-c-osd-visual
mkdir -p "$out"
cd "$root"
iverilog -g2012 -s tb_engine_c_sid_activity_history -o "$out/activity" \
  tb/tb_engine_c_sid_activity_history.sv rtl/engine_c_packed_v2/sid_activity_history.sv
vvp "$out/activity"
iverilog -g2012 -s tb_engine_c_title_renderer -o "$out/renderer" \
  tb/tb_engine_c_title_renderer.sv rtl/engine_c_packed_v2/megavgm_title_renderer_engine_c.sv rtl/megavgm_font5x7.sv
vvp "$out/renderer"
python3 tests/test_engine_c_osd_visual.py
