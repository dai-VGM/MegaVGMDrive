#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
base_head="0b2b175ca74bca6b2ad5e47a700533f82cb7bc43"
phase0b_tmp="$(mktemp -d /private/tmp/jt10-phase0b.XXXXXX)"
trap 'rm -rf "$phase0b_tmp"' EXIT

work_root="$phase0b_tmp/work"
repeat_root="$phase0b_tmp/repeat"
pinned_root="$repo_root/tb/jt10_pinned/6d51e0b6"
blob_manifest="$repo_root/tb/jt10_compat/pristine_blobs.tsv"
source_manifest="$repo_root/tb/jt10_phase0_sources.f"

copy_sources() {
    local destination="$1"
    mkdir -p \
        "$destination/rtl/genesis_audio/jt12/standard_jt10/adpcm" \
        "$destination/rtl/genesis_audio/jt12/adpcm" \
        "$destination/rtl/genesis_audio/jt12/mixer" \
        "$destination/rtl/genesis_audio/jt49" \
        "$destination/tb"
    cp "$pinned_root"/*.v \
        "$destination/rtl/genesis_audio/jt12/standard_jt10/"
    cp "$pinned_root/adpcm"/*.v \
        "$destination/rtl/genesis_audio/jt12/standard_jt10/adpcm/"
    cp "$repo_root/rtl/genesis_audio/jt12"/*.v \
        "$destination/rtl/genesis_audio/jt12/"
    cp "$repo_root/rtl/genesis_audio/jt12/adpcm/jt10_adpcm_div.v" \
        "$destination/rtl/genesis_audio/jt12/adpcm/"
    cp "$repo_root/rtl/genesis_audio/jt12/mixer"/*.v \
        "$destination/rtl/genesis_audio/jt12/mixer/"
    cp "$repo_root/rtl/genesis_audio/jt49"/*.v \
        "$destination/rtl/genesis_audio/jt49/"
    cp "$repo_root/tb/tb_jt10_standalone_elaboration.sv" \
        "$destination/tb/"
    cp "$repo_root/tb/tb_jt10_phase0a_diagnostic.sv" \
        "$destination/tb/"
}

apply_compatibility() {
    local source_root="$1"
    python3 "$repo_root/tb/jt10_compat/apply_icarus_syntax_compat.py" \
        "$source_root"
    python3 "$repo_root/tb/jt10_compat/apply_local_interface_compat.py" \
        "$source_root"
    python3 "$repo_root/tb/jt10_compat/apply_jt10_counter_reset_compat.py" \
        "$source_root"
}

echo "== Phase 0B baseline =="
[[ "$(git -C "$repo_root" branch --show-current)" == \
    "ym2610-family-bringup" ]]
head_sha="$(git -C "$repo_root" rev-parse HEAD)"
if [[ "$head_sha" != "$base_head" ]]; then
    [[ "$(git -C "$repo_root" rev-parse HEAD^)" == "$base_head" ]]
    [[ "$(git -C "$repo_root" show -s --format=%s HEAD)" == \
        "Add test-only JT10 compatibility layer" ]]
fi
echo "BASELINE branch=ym2610-family-bringup head=$head_sha base=$base_head"

echo "== pristine pinned-source verification =="
while IFS=$'\t' read -r relative expected_blob expected_sha; do
    [[ -z "$relative" || "$relative" == \#* ]] && continue
    source_file="$pinned_root/$relative"
    actual_blob="$(git -C "$repo_root" hash-object "$source_file")"
    actual_sha="$(shasum -a 256 "$source_file" | awk '{print $1}')"
    [[ "$actual_blob" == "$expected_blob" ]]
    [[ "$actual_sha" == "$expected_sha" ]]
    printf '%-34s blob=%s sha256=%s\n' \
        "$relative" "$actual_blob" "$actual_sha"
done < "$blob_manifest"
echo "PRISTINE_PINNED 15 MATCH"

copy_sources "$work_root"
copy_sources "$repeat_root"
apply_compatibility "$work_root"
apply_compatibility "$repeat_root"

patched_reg="$work_root/rtl/genesis_audio/jt12/jt12_reg.v"
repeat_reg="$repeat_root/rtl/genesis_audio/jt12/jt12_reg.v"
patched_sha="$(shasum -a 256 "$patched_reg" | awk '{print $1}')"
repeat_sha="$(shasum -a 256 "$repeat_reg" | awk '{print $1}')"
[[ "$patched_sha" == "$repeat_sha" ]]
echo "PATCHED_JT12_REG_SHA256 $patched_sha"
echo "PATCH_REGENERATION PASS"

before_reapply_sha="$patched_sha"
python3 "$repo_root/tb/jt10_compat/apply_jt10_counter_reset_compat.py" \
    "$work_root"
after_reapply_sha="$(shasum -a 256 "$patched_reg" | awk '{print $1}')"
[[ "$before_reapply_sha" == "$after_reapply_sha" ]]
echo "PATCH_REAPPLICATION PASS sha256=$after_reapply_sha"
echo "RESET_ONLY_LOGIC_CHECK PASS"

echo "== duplicate module check =="
while IFS= read -r source_file; do
    [[ -z "$source_file" || "$source_file" == \#* ]] && continue
    perl -ne \
        'print "$1\n" if /^\s*module\s+([A-Za-z_][A-Za-z0-9_]*)/' \
        "$work_root/$source_file"
done < "$source_manifest" | sort > "$phase0b_tmp/modules.txt"
uniq -d "$phase0b_tmp/modules.txt" > "$phase0b_tmp/duplicates.txt"
[[ ! -s "$phase0b_tmp/duplicates.txt" ]]
echo "DUPLICATE_MODULES 0"

echo "== Icarus compile/elaboration =="
(
    cd "$work_root"
    iverilog -g2012 -Wall -s tb_jt10_standalone_elaboration \
        -o "$phase0b_tmp/standalone.vvp" -f "$source_manifest"
    iverilog -g2012 -Wall -s tb_jt10_phase0a_diagnostic \
        -o "$phase0b_tmp/diagnostic.vvp" -f "$source_manifest" \
        tb/tb_jt10_phase0a_diagnostic.sv
) >"$phase0b_tmp/iverilog.log" 2>&1
sed -n '/warning:/p' "$phase0b_tmp/iverilog.log"
echo "ICARUS_WARNING_COUNT $(rg -c 'warning:' \
    "$phase0b_tmp/iverilog.log" || true)"
echo "UNDEFINED_MODULES 0"

echo "== Icarus standalone simulation =="
(
    cd "$work_root"
    vvp "$phase0b_tmp/standalone.vvp"
) | tee "$phase0b_tmp/standalone.log"

for reset_cen in 0 1 2 8; do
    echo "== Icarus non-SIMULATION RESET_CEN=$reset_cen =="
    (
        cd "$work_root"
        vvp "$phase0b_tmp/diagnostic.vvp" \
            +RESET_CEN="$reset_cen" +LEGAL=0 +EXPECT_PATCH=1
    ) | tee "$phase0b_tmp/diag-$reset_cen.log" | \
        rg '^(SWEEP|SOURCE|INPUT_|DIAG_RESULT|FIRST_X|X_RESULT|CADENCE_RESULT|FAIL)'
done

echo "== Icarus non-SIMULATION RESET_CEN=64 legal ADPCM-A =="
(
    cd "$work_root"
    vvp "$phase0b_tmp/diagnostic.vvp" \
        +RESET_CEN=64 +LEGAL=1 +EXPECT_PATCH=1
) | tee "$phase0b_tmp/diag-64.log" | \
    rg '^(SWEEP|SOURCE|INPUT_|FIRST_|FETCH_|ACTIVE_|SAMPLE_|DIAG_RESULT|X_RESULT|CADENCE_RESULT|LEGAL_X_RESULT|FAIL)'

echo "== Icarus SIMULATION comparison =="
(
    cd "$work_root"
    iverilog -g2012 -Wall -DSIMULATION \
        -s tb_jt10_phase0a_diagnostic \
        -o "$phase0b_tmp/diagnostic-simulation.vvp" \
        -f "$source_manifest" tb/tb_jt10_phase0a_diagnostic.sv
) >"$phase0b_tmp/iverilog-simulation.log" 2>&1
(
    cd "$work_root"
    vvp "$phase0b_tmp/diagnostic-simulation.vvp" \
        +RESET_CEN=64 +LEGAL=1 +EXPECT_PATCH=1
) | tee "$phase0b_tmp/diag-simulation.log" | \
    rg '^(SWEEP|SOURCE|FIRST_|SAMPLE_X|DIAG_RESULT|X_RESULT|CADENCE_RESULT|LEGAL_X_RESULT|FAIL)'

rg '^CADENCE_RESULT' "$phase0b_tmp/diag-64.log" \
    >"$phase0b_tmp/cadence-nonsim.txt"
rg '^CADENCE_RESULT' "$phase0b_tmp/diag-simulation.log" \
    >"$phase0b_tmp/cadence-simulation.txt"
diff -u "$phase0b_tmp/cadence-nonsim.txt" \
    "$phase0b_tmp/cadence-simulation.txt"
echo "SIMULATION_CADENCE_MATCH PASS"

echo "== Verilator patched lint/elaboration =="
set +e
(
    cd "$work_root"
    verilator --lint-only --timing -Wall -Wno-fatal \
        --top-module tb_jt10_phase0a_diagnostic \
        -f "$source_manifest" tb/tb_jt10_phase0a_diagnostic.sv
) >"$phase0b_tmp/verilator.log" 2>&1
verilator_rc=$?
set -e
echo "VERILATOR_RC $verilator_rc"
echo "VERILATOR_WARNING_COUNT $(rg -c '^%Warning-' \
    "$phase0b_tmp/verilator.log" || true)"
sed -n 's/^%Warning-\([^:]*\).*/\1/p' \
    "$phase0b_tmp/verilator.log" | sort | uniq -c | sort -k2
[[ "$verilator_rc" -eq 0 ]]

echo "== production isolation =="
git -C "$repo_root" diff --quiet "$base_head" -- \
    rtl/genesis_audio/jt12 \
    rtl/genesis_audio/jt49 \
    rtl/vgm_loaded_player.sv \
    rtl/mister_vgm_md_top.sv \
    rtl/vgm_ddram_backend.sv \
    rtl/md_sound_module.sv \
    rtl/emu.sv \
    sys/sys_top.v \
    rtl/genesis_audio/jtoutrun \
    rtl/segapcm_sound_module.sv \
    rtl/audio_mixer.sv \
    files.qip \
    VGM_MD_MiSTer.qsf
echo "PRODUCTION_BLOBS MATCH"

git -C "$repo_root" diff --check
echo "GIT_DIFF_CHECK PASS"

startup_sample_x="$(
    sed -n \
        's/^DIAG_RESULT .* sample_x=\([0-9][0-9]*\) failures=.*/\1/p' \
        "$phase0b_tmp/diag-64.log"
)"
if [[ "$startup_sample_x" != "0" ]]; then
    echo "PHASE0B_STOP sample-valid audio X count=$startup_sample_x"
    exit 1
fi
echo "PHASE0B_RUNNER PASS"
