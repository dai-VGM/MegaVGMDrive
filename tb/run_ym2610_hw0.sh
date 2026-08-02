#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_parent="${TMPDIR:-/tmp}"
work_root="$(mktemp -d "$tmp_parent/ym2610_hw0.XXXXXX")"
build_root="$work_root/build"
log_root="$work_root/logs"
mkdir -p "$build_root" "$log_root"

top=tb_ym2610_hw0_top
manifest="$repo_root/tb/ym2610_hw0_sources.f"

normalize() {
    rg '^(HW0_HASH|HW0_CONTRACT|HW0_X|HW0_TIMELINE|HW0_PASS)' "$1" |
        sed -E 's/run=[0-9]+/run=N/g'
}

echo "== HW-0 static project/protection audit =="
(
    cd "$repo_root"
    python3 tb/audit_ym2610_hw0.py
) | tee "$log_root/static.log"

echo "== HW-0 Icarus inner-top elaboration =="
(
    cd "$repo_root"
    iverilog -g2012 -Wall -s "$top" -o "$build_root/hw0.vvp" \
        -f "$manifest"
) >"$log_root/iverilog.log" 2>&1

echo "== HW-0 Icarus SIMULATION elaboration =="
(
    cd "$repo_root"
    iverilog -g2012 -Wall -DSIMULATION -s "$top" \
        -o "$build_root/hw0-simulation.vvp" -f "$manifest"
) >"$log_root/iverilog-simulation.log" 2>&1

echo "== HW-0 exact hardware pacing counts =="
(
    cd "$repo_root"
    iverilog -g2012 -s tb_ym2610_hw0_pacing \
        -o "$build_root/hw0-pacing.vvp" \
        tb/tb_ym2610_hw0_top.sv \
        rtl/ym2610_hw0/ym2610_hw0_sequencer.sv
    vvp "$build_root/hw0-pacing.vvp"
) >"$log_root/pacing.log" 2>&1
rg -q '^HW0_PACING .* result=PASS$' "$log_root/pacing.log"
rg '^HW0_PACING ' "$log_root/pacing.log"

echo "== HW-0 reset-injection elaboration =="
(
    cd "$repo_root"
    iverilog -g2012 -Wall -s tb_ym2610_hw0_reset_injection \
        -o "$build_root/hw0-reset.vvp" -f "$manifest"
) >"$log_root/iverilog-reset.log" 2>&1

echo "== HW-0 full-loop non-SIMULATION 3-run + SIMULATION =="
pids=()
for run in 1 2 3; do
    (
        cd "$repo_root"
        stdbuf -oL vvp "$build_root/hw0.vvp" +RUN_ID="$run"
    ) >"$log_root/run-$run.log" 2>&1 &
    pids+=("$!")
done
(
    cd "$repo_root"
    stdbuf -oL vvp "$build_root/hw0-simulation.vvp" +RUN_ID=1
) >"$log_root/simulation.log" 2>&1 &
pids+=("$!")
for pid in "${pids[@]}"; do
    wait "$pid"
done

for run in 1 2 3; do
    ! rg -q '^HW0_FAIL|^FATAL:' "$log_root/run-$run.log"
    rg -q "^HW0_PASS run=$run$" "$log_root/run-$run.log"
    normalize "$log_root/run-$run.log" >"$log_root/run-$run.norm"
done
! rg -q '^HW0_FAIL|^FATAL:' "$log_root/simulation.log"
rg -q '^HW0_PASS run=1$' "$log_root/simulation.log"
normalize "$log_root/simulation.log" >"$log_root/simulation.norm"
diff -u "$log_root/run-1.norm" "$log_root/run-2.norm"
diff -u "$log_root/run-1.norm" "$log_root/run-3.norm"
diff -u "$log_root/run-1.norm" "$log_root/simulation.norm"
rg '^(HW0_HASH|HW0_CONTRACT|HW0_X|HW0_TIMELINE|HW0_PASS)' \
    "$log_root/run-1.log"
echo "HW0_DETERMINISM non_simulation=3/3 simulation=MATCH result=PASS"

echo "== HW-0 reset injection FM/ADPCM-A6/ADPCM-B =="
pids=()
for target in 7 29 36; do
    (
        cd "$repo_root"
        stdbuf -oL vvp "$build_root/hw0-reset.vvp" \
            +TARGET_STATE="$target"
    ) >"$log_root/reset-$target.log" 2>&1 &
    pids+=("$!")
done
for pid in "${pids[@]}"; do
    wait "$pid"
done
for target in 7 29 36; do
    ! rg -q '^HW0_RESET_FAIL|^FATAL:' "$log_root/reset-$target.log"
    rg -q "^HW0_RESET target=$target .* result=PASS$" \
        "$log_root/reset-$target.log"
    rg '^HW0_RESET ' "$log_root/reset-$target.log"
done
echo "HW0_RESET_INJECTION cases=FM/ADPCM-A6/ADPCM-B result=PASS"

echo "== HW-0 minimal MiSTer emu elaboration =="
(
    cd "$repo_root"
    iverilog -g2012 -DMISTER_FB '-DBUILD_DATE="20260802"' \
        -s emu -o "$build_root/emu.vvp" -f "$manifest" \
        tb/ym2610_hw0_mister_stubs.sv rtl/ym2610_hw0/emu.sv
) >"$log_root/emu-iverilog.log" 2>&1
echo "HW0_EMU_ELABORATION result=PASS vendor_stubs=test_only"

echo "== HW-0 Verilator lint/elaboration =="
(
    cd "$repo_root"
    verilator --lint-only --timing -Wall -Wno-fatal \
        --top-module ym2610_hw0_top -f "$manifest"
) >"$log_root/verilator.log" 2>&1
! rg -q '^%Error' "$log_root/verilator.log"
! rg -q '^%Warning-(LATCH|UNOPTFLAT)' "$log_root/verilator.log"
warning_count="$(rg -c '^%Warning-' "$log_root/verilator.log" || true)"
sed -n 's/^%Warning-\([^:]*\).*/\1/p' "$log_root/verilator.log" |
    sort | uniq -c >"$log_root/verilator-warning-types.txt"
echo "HW0_VERILATOR rc=0 warnings=$warning_count latch=0 combinational_loop=0 result=PASS"

(
    cd "$repo_root"
    git diff --check
    python3 tb/audit_ym2610_hw0.py
) >"$log_root/final-audit.log"
rg -q '^HW0_STATIC_PASS$' "$log_root/final-audit.log"
echo "HW0_LOCAL_AUDIT PASS build=$build_root logs=$log_root"
