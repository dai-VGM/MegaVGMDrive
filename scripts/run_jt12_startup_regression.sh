#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
baseline_commit="24c4a0cdb8b0ae1940593fd26ec547c16bd9a8cf"
regression_tmp="$(mktemp -d "${TMPDIR:-/tmp}/jt12-startup-regression.XXXXXX")"
trap 'rm -rf "$regression_tmp"' EXIT

original_tree="$regression_tmp/original"
original_ns="$regression_tmp/original-ns"
mkdir -p "$original_tree" "$original_ns"

cd "$repo_dir"
git archive "$baseline_commit" | tar -x -C "$original_tree"

# Icarus cannot elaborate two definitions with the same module name.  Rename
# every original JT12 module token while retaining the exact original logic.
for source_file in "$original_tree"/rtl/genesis_audio/jt12/*.v; do
    output_file="$original_ns/$(basename "$source_file")"
    perl -pe 's/\bjt12_/jt12_orig_/g; s/\bjt12\b/jt12_orig/g; s/\bjt03_acc\b/jt03_acc_orig/g' \
        "$source_file" > "$output_file"
done

jt12_sources=(
    rtl/genesis_audio/jt12/*.v
    rtl/genesis_audio/jt12/adpcm/jt10_adpcm_div.v
)

iverilog -g2012 -DSIMULATION -s tb_jt12_fm_startup_trace \
    -o "$regression_tmp/startup.vvp" \
    "${jt12_sources[@]}" rtl/genesis_audio/jt49/*.v \
    tb/tb_jt12_fm_startup_trace.sv
vvp "$regression_tmp/startup.vvp" > "$regression_tmp/startup.log"
grep -E '^(SUMMARY|PASS_STARTUP)' "$regression_tmp/startup.log"

for reset_mode in 0 1 2 3 4 5 9; do
    iverilog -g2012 -DSIMULATION \
        -Ptb_jt12_fm_reset_sweep.RESET_MODE="$reset_mode" \
        -s tb_jt12_fm_reset_sweep \
        -o "$regression_tmp/sweep-$reset_mode.vvp" \
        "${jt12_sources[@]}" tb/tb_jt12_fm_reset_sweep.sv
    vvp "$regression_tmp/sweep-$reset_mode.vvp" \
        > "$regression_tmp/sweep-$reset_mode.log"
    grep -E '^(SWEEP|PASS_SWEEP)' "$regression_tmp/sweep-$reset_mode.log"
done

for channel_count in 3 6; do
    iverilog -g2012 -DSIMULATION \
        -Ptb_jt12_startup_equiv.NUM_CH="$channel_count" \
        -s tb_jt12_startup_equiv \
        -o "$regression_tmp/equiv-$channel_count.vvp" \
        "${jt12_sources[@]}" "$original_ns"/*.v \
        tb/tb_jt12_startup_equiv.sv
    vvp "$regression_tmp/equiv-$channel_count.vvp" \
        > "$regression_tmp/equiv-$channel_count.log"
    grep -E '^(COMMON_VALID|PASS_EQUIV)' \
        "$regression_tmp/equiv-$channel_count.log"
done
