#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
base_head="0b2b175ca74bca6b2ad5e47a700533f82cb7bc43"
phase0c_tmp="$(mktemp -d /private/tmp/jt10-phase0c.XXXXXX)"
trap 'rm -rf "$phase0c_tmp"' EXIT

work_root="$phase0c_tmp/work"
repeat_root="$phase0c_tmp/repeat"
pinned_root="$repo_root/tb/jt10_pinned/6d51e0b6"
blob_manifest="$repo_root/tb/jt10_compat/pristine_blobs.tsv"
source_manifest="$repo_root/tb/jt10_phase0_sources.f"
sacred_tb="$repo_root/tb/tb_jt49_audio_compare.sv"
counter_generator="$repo_root/tb/jt10_compat/apply_jt10_counter_reset_compat.py"

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
    cp "$repo_root/tb/tb_jt10_phase0c_diagnostic.sv" \
        "$destination/tb/"
}

apply_compatibility() {
    local source_root="$1"
    python3 "$repo_root/tb/jt10_compat/apply_icarus_syntax_compat.py" \
        "$source_root"
    python3 "$repo_root/tb/jt10_compat/apply_local_interface_compat.py" \
        "$source_root"
    python3 "$counter_generator" "$source_root"
}

tree_digest() {
    local source_root="$1"
    (
        cd "$source_root"
        while IFS= read -r source_file; do
            shasum -a 256 "$source_file"
        done < <(find . -type f | sort)
    )
}

run_diag() {
    local executable="$1"
    local log_file="$2"
    shift 2
    (
        cd "$work_root"
        vvp "$executable" "$@"
    ) | tee "$log_file"
}

echo "== Phase 0C baseline =="
branch="$(git -C "$repo_root" branch --show-current)"
head_sha="$(git -C "$repo_root" rev-parse HEAD)"
[[ "$branch" == "ym2610-family-bringup" ]]
if [[ "$head_sha" != "$base_head" ]]; then
    [[ "$(git -C "$repo_root" rev-parse HEAD^)" == "$base_head" ]]
    [[ "$(git -C "$repo_root" show -s --format=%s HEAD)" == \
        "Add test-only JT10 compatibility layer" ]]
fi
echo "BASELINE branch=$branch head=$head_sha base=$base_head"
git -C "$repo_root" diff --quiet
git -C "$repo_root" diff --cached --quiet
echo "TRACKED_DIFF none"
echo "STAGED_DIFF none"
git -C "$repo_root" status --short --untracked-files=all

sacred_sha_before="$(shasum -a 256 "$sacred_tb" | awk '{print $1}')"
sacred_stat_before="$(stat -f 'size=%z mtime=%m inode=%i' "$sacred_tb")"
echo "SACRED_BEGIN sha256=$sacred_sha_before $sacred_stat_before"
counter_generator_sha="$(shasum -a 256 "$counter_generator" | awk '{print $1}')"
echo "PHASE0B_GENERATOR_SHA256 $counter_generator_sha"

echo "== pristine pinned-source verification =="
pinned_count=0
while IFS=$'\t' read -r relative expected_blob expected_sha; do
    [[ -z "$relative" || "$relative" == \#* ]] && continue
    source_file="$pinned_root/$relative"
    actual_blob="$(git -C "$repo_root" hash-object "$source_file")"
    actual_sha="$(shasum -a 256 "$source_file" | awk '{print $1}')"
    [[ "$actual_blob" == "$expected_blob" ]]
    [[ "$actual_sha" == "$expected_sha" ]]
    pinned_count=$((pinned_count + 1))
done < "$blob_manifest"
[[ "$pinned_count" -eq 15 ]]
echo "PRISTINE_PINNED count=$pinned_count result=MATCH"

copy_sources "$work_root"
copy_sources "$repeat_root"
apply_compatibility "$work_root"
apply_compatibility "$repeat_root"
tree_digest "$work_root" > "$phase0c_tmp/work-tree.sha256"
tree_digest "$repeat_root" > "$phase0c_tmp/repeat-tree.sha256"
diff -u "$phase0c_tmp/work-tree.sha256" "$phase0c_tmp/repeat-tree.sha256"
echo "DIAGNOSTIC_REGENERATION PASS"
echo "DIAGNOSTIC_TB_SHA256 $(shasum -a 256 \
    "$repo_root/tb/tb_jt10_phase0c_diagnostic.sv" | awk '{print $1}')"

patched_reg="$work_root/rtl/genesis_audio/jt12/jt12_reg.v"
before_reapply_sha="$(shasum -a 256 "$patched_reg" | awk '{print $1}')"
python3 "$counter_generator" "$work_root"
after_reapply_sha="$(shasum -a 256 "$patched_reg" | awk '{print $1}')"
[[ "$before_reapply_sha" == "$after_reapply_sha" ]]
echo "COUNTER_PATCH_REAPPLICATION PASS sha256=$after_reapply_sha"

echo "== duplicate module check =="
while IFS= read -r source_file; do
    [[ -z "$source_file" || "$source_file" == \#* ]] && continue
    perl -ne \
        'print "$1\n" if /^\s*module\s+([A-Za-z_][A-Za-z0-9_]*)/' \
        "$work_root/$source_file"
done < "$source_manifest" > "$phase0c_tmp/modules.txt"
perl -ne \
    'print "$1\n" if /^\s*module\s+([A-Za-z_][A-Za-z0-9_]*)/' \
    "$work_root/tb/tb_jt10_phase0c_diagnostic.sv" \
    >> "$phase0c_tmp/modules.txt"
sort "$phase0c_tmp/modules.txt" -o "$phase0c_tmp/modules.txt"
uniq -d "$phase0c_tmp/modules.txt" > "$phase0c_tmp/duplicates.txt"
[[ ! -s "$phase0c_tmp/duplicates.txt" ]]
echo "DUPLICATE_MODULES 0"

echo "== Icarus compile/elaboration =="
(
    cd "$work_root"
    iverilog -g2012 -Wall -s tb_jt10_standalone_elaboration \
        -o "$phase0c_tmp/standalone.vvp" -f "$source_manifest"
    iverilog -g2012 -Wall -s tb_jt10_phase0c_diagnostic \
        -o "$phase0c_tmp/diagnostic.vvp" -f "$source_manifest" \
        tb/tb_jt10_phase0c_diagnostic.sv
) > "$phase0c_tmp/iverilog.log" 2>&1
echo "ICARUS_NON_SIM_WARNING_COUNT $(rg -c 'warning:' \
    "$phase0c_tmp/iverilog.log" || true)"
sed -n '/warning:/p' "$phase0c_tmp/iverilog.log"
echo "UNDEFINED_MODULES 0"

echo "== standalone simulation =="
(
    cd "$work_root"
    vvp "$phase0c_tmp/standalone.vvp"
) | tee "$phase0c_tmp/standalone.log"

echo "== reset CEN=64 first ten sample pulses =="
run_diag "$phase0c_tmp/diagnostic.vvp" \
    "$phase0c_tmp/trace-64.log" \
    +RESET_CEN=64 +RUN_CYCLES=1800 +TRACE_PULSES=10 +TRACE_SLOTS=80 \
    | rg '^(SLOT_X|PULSE|PHASE0C_RESULT|ROOT_RESULT|OUTPUT_RESULT|STATE_RESULT|INPUT_RESULT|FAIL)'

echo "== reset-CEN sweep =="
for reset_cen in 0 1 2 8 64 128 256 512; do
    echo "-- RESET_CEN=$reset_cen"
    run_diag "$phase0c_tmp/diagnostic.vvp" \
        "$phase0c_tmp/sweep-$reset_cen.log" \
        +RESET_CEN="$reset_cen" +RUN_CYCLES=20000 \
        | rg '^(PHASE0C_RESULT|ROOT_RESULT|OUTPUT_RESULT|STATE_RESULT|INPUT_RESULT|FAIL)'
done

echo "== operator/accumulator/ADPCM isolation =="
for diag_mode in 0 1 2 3 4; do
    echo "-- MODE=$diag_mode"
    run_diag "$phase0c_tmp/diagnostic.vvp" \
        "$phase0c_tmp/mode-$diag_mode.log" \
        +RESET_CEN=64 +RUN_CYCLES=1600 +MODE="$diag_mode" \
        | rg '^(PHASE0C_RESULT|ROOT_RESULT|OUTPUT_RESULT|STATE_RESULT|INPUT_RESULT|FAIL)'
done

echo "== feedback-root isolation with ADPCM lanes known zero =="
for root_mask in 0 1 2 4 3 5 6 7 8 16; do
    echo "-- ROOT_MASK=$root_mask"
    run_diag "$phase0c_tmp/diagnostic.vvp" \
        "$phase0c_tmp/root-$root_mask.log" \
        +RESET_CEN=64 +RUN_CYCLES=1200 +MODE=2 \
        +ROOT_MASK="$root_mask" \
        | rg '^(PHASE0C_RESULT|ROOT_RESULT|OUTPUT_RESULT|STATE_RESULT|INPUT_RESULT|FAIL)'
done

echo "== FM register initialization comparison =="
run_diag "$phase0c_tmp/diagnostic.vvp" \
    "$phase0c_tmp/init-keyoff.log" \
    +RESET_CEN=64 +RUN_CYCLES=3000 +FM_INIT=1 \
    | rg '^(PHASE0C_RESULT|ROOT_RESULT|OUTPUT_RESULT|STATE_RESULT|INPUT_RESULT|FAIL)'
run_diag "$phase0c_tmp/diagnostic.vvp" \
    "$phase0c_tmp/init-full.log" \
    +RESET_CEN=64 +RUN_CYCLES=3000 +FM_INIT=2 \
    | rg '^(PHASE0C_RESULT|ROOT_RESULT|OUTPUT_RESULT|STATE_RESULT|INPUT_RESULT|FAIL)'
keyoff_cycles="$(sed -n \
    's/^PHASE0C_RESULT .*init_cycles=\([0-9][0-9]*\).*/\1/p' \
    "$phase0c_tmp/init-keyoff.log")"
full_init_cycles="$(sed -n \
    's/^PHASE0C_RESULT .*init_cycles=\([0-9][0-9]*\).*/\1/p' \
    "$phase0c_tmp/init-full.log")"
run_diag "$phase0c_tmp/diagnostic.vvp" \
    "$phase0c_tmp/init-keyoff-idle.log" \
    +RESET_CEN=64 +RUN_CYCLES=3000 +START_DELAY="$keyoff_cycles" \
    | rg '^(PHASE0C_RESULT|ROOT_RESULT|OUTPUT_RESULT|STATE_RESULT|INPUT_RESULT|FAIL)'
run_diag "$phase0c_tmp/diagnostic.vvp" \
    "$phase0c_tmp/init-full-idle.log" \
    +RESET_CEN=64 +RUN_CYCLES=3000 +START_DELAY="$full_init_cycles" \
    | rg '^(PHASE0C_RESULT|ROOT_RESULT|OUTPUT_RESULT|STATE_RESULT|INPUT_RESULT|FAIL)'
echo "FM_INIT_DELAYS keyoff=$keyoff_cycles full=$full_init_cycles"

echo "== Icarus SIMULATION comparison =="
(
    cd "$work_root"
    iverilog -g2012 -Wall -DSIMULATION \
        -s tb_jt10_phase0c_diagnostic \
        -o "$phase0c_tmp/diagnostic-simulation.vvp" \
        -f "$source_manifest" tb/tb_jt10_phase0c_diagnostic.sv
) > "$phase0c_tmp/iverilog-simulation.log" 2>&1
echo "ICARUS_SIM_WARNING_COUNT $(rg -c 'warning:' \
    "$phase0c_tmp/iverilog-simulation.log" || true)"
sed -n '/warning:/p' "$phase0c_tmp/iverilog-simulation.log"
run_diag "$phase0c_tmp/diagnostic-simulation.vvp" \
    "$phase0c_tmp/trace-simulation.log" \
    +RESET_CEN=64 +RUN_CYCLES=1800 +TRACE_PULSES=10 \
    | rg '^(PULSE|PHASE0C_RESULT|ROOT_RESULT|OUTPUT_RESULT|STATE_RESULT|INPUT_RESULT|FAIL)'
rg '^(PULSE|PHASE0C_RESULT|ROOT_RESULT|OUTPUT_RESULT)' \
    "$phase0c_tmp/trace-64.log" > "$phase0c_tmp/compare-nonsim.txt"
rg '^(PULSE|PHASE0C_RESULT|ROOT_RESULT|OUTPUT_RESULT)' \
    "$phase0c_tmp/trace-simulation.log" \
    > "$phase0c_tmp/compare-simulation.txt"
sed 's/mode=0 root_mask=0/mode=0 root_mask=0/' \
    "$phase0c_tmp/compare-simulation.txt" \
    > "$phase0c_tmp/compare-simulation-normalized.txt"
diff -u "$phase0c_tmp/compare-nonsim.txt" \
    "$phase0c_tmp/compare-simulation-normalized.txt"
echo "SIMULATION_TRACE_MATCH PASS"

echo "== Verilator lint/elaboration =="
set +e
(
    cd "$work_root"
    verilator --lint-only --timing -Wall -Wno-fatal \
        --top-module tb_jt10_phase0c_diagnostic \
        -f "$source_manifest" tb/tb_jt10_phase0c_diagnostic.sv
) > "$phase0c_tmp/verilator.log" 2>&1
verilator_rc=$?
set -e
echo "VERILATOR_RC $verilator_rc"
echo "VERILATOR_WARNING_COUNT $(rg -c '^%Warning-' \
    "$phase0c_tmp/verilator.log" || true)"
sed -n 's/^%Warning-\([^:]*\).*/\1/p' \
    "$phase0c_tmp/verilator.log" | sort | uniq -c | sort -k2
[[ "$verilator_rc" -eq 0 ]]

echo "== final isolation audit =="
git -C "$repo_root" diff --quiet
git -C "$repo_root" diff --cached --quiet
git -C "$repo_root" diff --check
echo "TRACKED_DIFF none"
echo "STAGED_DIFF none"
echo "GIT_DIFF_CHECK PASS"

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

sacred_sha_after="$(shasum -a 256 "$sacred_tb" | awk '{print $1}')"
sacred_stat_after="$(stat -f 'size=%z mtime=%m inode=%i' "$sacred_tb")"
[[ "$sacred_sha_before" == "$sacred_sha_after" ]]
[[ "$sacred_stat_before" == "$sacred_stat_after" ]]
echo "SACRED_END sha256=$sacred_sha_after $sacred_stat_after result=UNCHANGED"
echo "PHASE0C_DIAGNOSTIC PASS"
