#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_bin=${TMPDIR:-/tmp}/tb_megavgm_playlist_status_export.$$
trap 'rm -f "$test_bin"' EXIT HUP INT TERM

iverilog -g2012 \
	-o "$test_bin" \
	"$repo_dir/rtl/megavgm_playlist_status_export.sv" \
	"$repo_dir/tb/tb_megavgm_playlist_status_export.sv"
vvp "$test_bin"
