#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
diag_tmp="$(mktemp -d /private/tmp/jt10-phase0a.XXXXXX)"
trap 'rm -rf "$diag_tmp"' EXIT
work_root="$diag_tmp/work"
pinned_root="$repo_root/tb/jt10_pinned/6d51e0b6"
source_manifest="$repo_root/tb/jt10_phase0_sources.f"

mkdir -p \
    "$work_root/rtl/genesis_audio/jt12/standard_jt10/adpcm" \
    "$work_root/rtl/genesis_audio/jt12/adpcm" \
    "$work_root/rtl/genesis_audio/jt12/mixer" \
    "$work_root/rtl/genesis_audio/jt49" \
    "$work_root/tb"
cp "$pinned_root"/*.v "$work_root/rtl/genesis_audio/jt12/standard_jt10/"
cp "$pinned_root/adpcm"/*.v \
    "$work_root/rtl/genesis_audio/jt12/standard_jt10/adpcm/"
cp "$repo_root/rtl/genesis_audio/jt12"/*.v \
    "$work_root/rtl/genesis_audio/jt12/"
cp "$repo_root/rtl/genesis_audio/jt12/adpcm/jt10_adpcm_div.v" \
    "$work_root/rtl/genesis_audio/jt12/adpcm/"
cp "$repo_root/rtl/genesis_audio/jt12/mixer"/*.v \
    "$work_root/rtl/genesis_audio/jt12/mixer/"
cp "$repo_root/rtl/genesis_audio/jt49"/*.v \
    "$work_root/rtl/genesis_audio/jt49/"
cp "$repo_root/tb/tb_jt10_standalone_elaboration.sv" "$work_root/tb/"
cp "$repo_root/tb/tb_jt10_phase0a_diagnostic.sv" "$work_root/tb/"

python3 "$repo_root/tb/jt10_compat/apply_icarus_syntax_compat.py" "$work_root"
python3 "$repo_root/tb/jt10_compat/apply_local_interface_compat.py" "$work_root"

echo "== Icarus diagnostic compile =="
set +e
(
    cd "$work_root"
    iverilog -g2012 -Wall -s tb_jt10_phase0a_diagnostic \
        -o "$diag_tmp/diag.vvp" -f "$source_manifest" \
        tb/tb_jt10_phase0a_diagnostic.sv
) >"$diag_tmp/iverilog.log" 2>&1
icarus_rc=$?
set -e
if [[ "$icarus_rc" -ne 0 ]]; then
    cat "$diag_tmp/iverilog.log"
    exit "$icarus_rc"
fi
sed -n '/warning:/p' "$diag_tmp/iverilog.log"
echo "ICARUS_WARNING_COUNT $(rg -c 'warning:' "$diag_tmp/iverilog.log" || true)"

for reset_cen in 0 1 2 8; do
    echo "== Icarus RESET_CEN=$reset_cen =="
    (
        cd "$work_root"
        vvp "$diag_tmp/diag.vvp" +RESET_CEN="$reset_cen" +LEGAL=0
    ) | rg '^(SWEEP|SOURCE|INPUT_METER|DIAG_RESULT)'
done

echo "== Icarus RESET_CEN=64 legal sequence =="
(
    cd "$work_root"
    vvp "$diag_tmp/diag.vvp" +RESET_CEN=64 +LEGAL=1
) | tee "$diag_tmp/diag-64.log" | \
    rg '^(SWEEP|SOURCE|INPUT_|FIRST_|FETCH_X|FETCH_CHECK|ACTIVE_CHECK|SAMPLE_CHECK|DIAG_RESULT|FAIL)'

echo "== Icarus official SIMULATION contract comparison =="
(
    cd "$work_root"
    iverilog -g2012 -Wall -DSIMULATION -s tb_jt10_phase0a_diagnostic \
        -o "$diag_tmp/diag-simulation.vvp" -f "$source_manifest" \
        tb/tb_jt10_phase0a_diagnostic.sv
) >"$diag_tmp/iverilog-simulation.log" 2>&1
(
    cd "$work_root"
    vvp "$diag_tmp/diag-simulation.vvp" +RESET_CEN=64 +LEGAL=1
) | rg '^(SWEEP|SOURCE|INPUT_|FIRST_|FETCH_X|FETCH_CHECK|ACTIVE_CHECK|SAMPLE_CHECK|DIAG_RESULT|FAIL)'

echo "== Verilator patched lint/elaboration =="
set +e
(
    cd "$work_root"
    verilator --lint-only --timing -Wall -Wno-fatal \
        --top-module tb_jt10_phase0a_diagnostic \
        -f "$source_manifest" tb/tb_jt10_phase0a_diagnostic.sv
) >"$diag_tmp/verilator.log" 2>&1
verilator_rc=$?
set -e
echo "VERILATOR_RC $verilator_rc"
echo "VERILATOR_WARNING_COUNT $(rg -c '^%Warning-' "$diag_tmp/verilator.log" || true)"
sed -n 's/^%Warning-\([^:]*\).*/\1/p' "$diag_tmp/verilator.log" | \
    sort | uniq -c | sort -k2
if [[ "$verilator_rc" -ne 0 ]]; then
    tail -80 "$diag_tmp/verilator.log"
    exit "$verilator_rc"
fi

echo "PHASE0A_DIAGNOSTIC PASS"
