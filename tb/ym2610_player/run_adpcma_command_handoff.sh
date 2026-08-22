#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/adpcma-handoff.XXXXXX")"
baseline_dir="$build_dir/ba6f795"
cleanup() {
    case "$build_dir" in
        "${TMPDIR:-/tmp}"/adpcma-handoff.*)
            test -d "$build_dir" && rm -rf -- "$build_dir"
            ;;
        *)
            echo "refusing unexpected cleanup path: $build_dir" >&2
            ;;
    esac
}
trap cleanup EXIT

mkdir -p "$baseline_dir"
git -C "$repo_root" archive --format=tar \
    ba6f7958884309d1d9d7ffd06af39e2cdc17b1b4 |
    tar -xf - -C "$baseline_dir"

tb_abs="$repo_root/tb/ym2610_player/tb_ym2610_adpcma_command_handoff.sv"

(
    cd "$baseline_dir"
    iverilog -g2012 -Wall -Wno-timescale \
        -DEXPECT_LEGACY_LOSS=1 \
        -s tb_ym2610_adpcma_command_handoff \
        -o "$build_dir/legacy.vvp" \
        -f tb/ym2610_hw0_sources.f "$tb_abs"
)
vvp "$build_dir/legacy.vvp" | tee "$build_dir/legacy.log"
rg -q 'GF12_PREFIX_FAIL_EXPECTED.*trajectory=OLD' "$build_dir/legacy.log"
rg -q 'ADPCMA_HANDOFF_LEGACY_EXPECTED_FAIL_PASS' "$build_dir/legacy.log"

(
    cd "$repo_root"
    iverilog -g2012 -Wall -Wno-timescale \
        -s tb_ym2610_adpcma_command_handoff \
        -o "$build_dir/fixed.vvp" \
        -f tb/ym2610_hw0_sources.f \
        tb/ym2610_player/tb_ym2610_adpcma_command_handoff.sv
)
vvp "$build_dir/fixed.vvp" | tee "$build_dir/fixed.log"
rg -q 'GF12_POSTFIX_PASS.*trajectory=NEW' "$build_dir/fixed.log"
rg -q 'SPARSE_CEN_PHASE_MATRIX_PASS offsets=5' "$build_dir/fixed.log"
rg -q 'ALL_SIX_CHANNELS_PASS key_on_once=1 stop_once=1' "$build_dir/fixed.log"
rg -q 'BACK_TO_BACK_LEGAL_PASS accepts=12 consumes=12 fast_div=1' "$build_dir/fixed.log"
rg -q 'RESET_PENDING_PASS stale=0 application=0' "$build_dir/fixed.log"
rg -q 'ADPCMA_HANDOFF_FIXED_REGRESSION_PASS' "$build_dir/fixed.log"

git -C "$repo_root" diff --check
echo "ADPCMA_COMMAND_HANDOFF_REGRESSION_PASS legacy_loss=1 fixed_hold=1 gf12_reload=AB400 channels=6 phases=5 back_to_back=1 reset=1 duplicate=0"
