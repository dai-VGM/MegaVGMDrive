#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sim="$(mktemp "${TMPDIR:-/tmp}/mode5-stop-diagnostic.XXXXXX")"
trap 'rm -f "$sim"' EXIT

cd "$repo_root"
iverilog -g2012 -s tb_megavgm_mode5_stop_diagnostic \
    -o "$sim" \
    tb/tb_megavgm_mode5_stop_diagnostic.sv \
    rtl/megavgm_mode5_stop_diagnostic.sv
vvp "$sim"
