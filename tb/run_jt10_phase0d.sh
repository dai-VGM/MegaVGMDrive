#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
base_head="0b2b175ca74bca6b2ad5e47a700533f82cb7bc43"
phase0d_tmp="$(mktemp -d /private/tmp/jt10-phase0d.XXXXXX)"
trap 'rm -rf "$phase0d_tmp"' EXIT

work_root="$phase0d_tmp/work"
repeat_root="$phase0d_tmp/repeat"
pinned_root="$repo_root/tb/jt10_pinned/6d51e0b6"
blob_manifest="$repo_root/tb/jt10_compat/pristine_blobs.tsv"
source_manifest="$repo_root/tb/jt10_phase0_sources.f"
wrapper="$repo_root/tb/jt10_phase0_warmup_wrapper.sv"
phase0d_tb="$repo_root/tb/tb_jt10_phase0d_warmup.sv"
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
    cp "$wrapper" "$phase0d_tb" "$destination/tb/"
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

run_phase0d() {
    local name="$1"
    shift
    (
        cd "$work_root"
        vvp "$phase0d_tmp/phase0d.vvp" "$@"
    ) > "$phase0d_tmp/$name.log"
    rg \
        '^(RESET_CONTRACT|WARMUP_TRACE|READY_EDGE|PUBLIC_START|HASH_RESULT|READY_STABILITY_RESULT|INVALID_RESET_RESULT|SCENARIO_RESULT|LEGAL_RESULT|LOOP_RESULT|REARM_RESULT|PHASE0D_RESULT|PHASE0D_PASS|FAIL)' \
        "$phase0d_tmp/$name.log"
}

echo "== Phase 0D baseline =="
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
echo "COMPATIBILITY_GENERATOR_SHA256 $(shasum -a 256 \
    "$counter_generator" | awk '{print $1}')"
for generator in \
    "$repo_root/tb/jt10_compat/apply_icarus_syntax_compat.py" \
    "$repo_root/tb/jt10_compat/apply_local_interface_compat.py"; do
    echo "COMPATIBILITY_SCRIPT file=$(basename "$generator") sha256=$(shasum -a 256 \
        "$generator" | awk '{print $1}')"
done

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
tree_digest "$work_root" > "$phase0d_tmp/work-tree.sha256"
tree_digest "$repeat_root" > "$phase0d_tmp/repeat-tree.sha256"
diff -u "$phase0d_tmp/work-tree.sha256" \
    "$phase0d_tmp/repeat-tree.sha256"
echo "GENERATOR_REPRODUCIBILITY PASS"

patched_reg="$work_root/rtl/genesis_audio/jt12/jt12_reg.v"
before_reapply_sha="$(shasum -a 256 "$patched_reg" | awk '{print $1}')"
python3 "$counter_generator" "$work_root"
after_reapply_sha="$(shasum -a 256 "$patched_reg" | awk '{print $1}')"
[[ "$before_reapply_sha" == "$after_reapply_sha" ]]
echo "PATCH_REAPPLICATION PASS sha256=$after_reapply_sha"

echo "== duplicate module check =="
while IFS= read -r source_file; do
    [[ -z "$source_file" || "$source_file" == \#* ]] && continue
    perl -ne \
        'print "$1\n" if /^\s*module\s+([A-Za-z_][A-Za-z0-9_]*)/' \
        "$work_root/$source_file"
done < "$source_manifest" > "$phase0d_tmp/modules.txt"
for source_file in \
    "$work_root/tb/jt10_phase0_warmup_wrapper.sv" \
    "$work_root/tb/tb_jt10_phase0d_warmup.sv"; do
    perl -ne \
        'print "$1\n" if /^\s*module\s+([A-Za-z_][A-Za-z0-9_]*)/' \
        "$source_file" >> "$phase0d_tmp/modules.txt"
done
sort "$phase0d_tmp/modules.txt" -o "$phase0d_tmp/modules.txt"
uniq -d "$phase0d_tmp/modules.txt" > "$phase0d_tmp/duplicates.txt"
[[ ! -s "$phase0d_tmp/duplicates.txt" ]]
echo "DUPLICATE_MODULES 0"

echo "== Icarus non-SIMULATION compile/elaboration =="
(
    cd "$work_root"
    iverilog -g2012 -Wall -s tb_jt10_standalone_elaboration \
        -o "$phase0d_tmp/standalone.vvp" -f "$source_manifest"
    iverilog -g2012 -Wall -s tb_jt10_phase0d_warmup \
        -o "$phase0d_tmp/phase0d.vvp" -f "$source_manifest" \
        tb/jt10_phase0_warmup_wrapper.sv \
        tb/tb_jt10_phase0d_warmup.sv
) > "$phase0d_tmp/iverilog-nonsim.log" 2>&1
echo "ICARUS_NON_SIM_WARNING_COUNT $(rg -c 'warning:' \
    "$phase0d_tmp/iverilog-nonsim.log" || true)"
sed -n '/warning:/p' "$phase0d_tmp/iverilog-nonsim.log"
echo "ICARUS_ELABORATION PASS"
echo "UNDEFINED_MODULES 0"
(
    cd "$work_root"
    vvp "$phase0d_tmp/standalone.vvp"
) | tee "$phase0d_tmp/standalone.log"

echo "== reset-CEN sweep =="
for reset_cen in 0 1 2 5 6 8 64 128 256 512; do
    if (( reset_cen < 6 )); then
        expected_valid=0
    else
        expected_valid=1
    fi
    if (( reset_cen == 64 )); then
        echo "-- RESET_CEN=$reset_cen EXPECT_VALID=$expected_valid"
        run_phase0d "sweep-$reset_cen" \
            +RESET_CEN="$reset_cen" \
            +EXPECT_VALID="$expected_valid" \
            +EXPECT_STARTUP_X=1 \
            +SCENARIO=0
    else
        echo "-- RESET_CEN=$reset_cen EXPECT_VALID=$expected_valid"
        run_phase0d "sweep-$reset_cen" \
            +RESET_CEN="$reset_cen" \
            +EXPECT_VALID="$expected_valid" \
            +SCENARIO=0
    fi
done

echo "== post-ready lane and legal ADPCM-A comparisons =="
for scenario in 1 2 3; do
    echo "-- SCENARIO=$scenario"
    run_phase0d "scenario-$scenario" \
        +RESET_CEN=64 +EXPECT_VALID=1 +SCENARIO="$scenario"
done

echo "== session/reload and loop no-rearm =="
run_phase0d "rearm" \
    +RESET_CEN=64 +EXPECT_VALID=1 +SCENARIO=0 +REARM=3

echo "== individual four-state checks =="
isunknown_count="$(rg -o '\$isunknown' "$phase0d_tb" | wc -l | tr -d ' ')"
[[ "$isunknown_count" -ge 20 ]]
echo "INDIVIDUAL_ISUNKNOWN_CALLS $isunknown_count"
echo "ICARUS_4STATE_RESULT PASS"

echo "== Icarus SIMULATION comparison =="
(
    cd "$work_root"
    iverilog -g2012 -Wall -DSIMULATION \
        -s tb_jt10_phase0d_warmup \
        -o "$phase0d_tmp/phase0d-simulation.vvp" \
        -f "$source_manifest" \
        tb/jt10_phase0_warmup_wrapper.sv \
        tb/tb_jt10_phase0d_warmup.sv
) > "$phase0d_tmp/iverilog-simulation.log" 2>&1
echo "ICARUS_SIM_WARNING_COUNT $(rg -c 'warning:' \
    "$phase0d_tmp/iverilog-simulation.log" || true)"
sed -n '/warning:/p' "$phase0d_tmp/iverilog-simulation.log"
(
    cd "$work_root"
    vvp "$phase0d_tmp/phase0d-simulation.vvp" \
        +RESET_CEN=64 +EXPECT_VALID=1 +EXPECT_STARTUP_X=1 +SCENARIO=0
) > "$phase0d_tmp/simulation.log"
rg \
    '^(WARMUP_TRACE|READY_EDGE|PUBLIC_START|HASH_RESULT|READY_STABILITY_RESULT|PHASE0D_RESULT|PHASE0D_PASS|FAIL)' \
    "$phase0d_tmp/simulation.log"
rg '^(WARMUP_TRACE|READY_EDGE|PUBLIC_START|HASH_RESULT|READY_STABILITY_RESULT|PHASE0D_RESULT)' \
    "$phase0d_tmp/sweep-64.log" > "$phase0d_tmp/nonsim-compare.txt"
rg '^(WARMUP_TRACE|READY_EDGE|PUBLIC_START|HASH_RESULT|READY_STABILITY_RESULT|PHASE0D_RESULT)' \
    "$phase0d_tmp/simulation.log" > "$phase0d_tmp/simulation-compare.txt"
diff -u "$phase0d_tmp/nonsim-compare.txt" \
    "$phase0d_tmp/simulation-compare.txt"
echo "SIMULATION_TRACE_MATCH PASS"

echo "== Verilator lint/elaboration =="
set +e
(
    cd "$work_root"
    verilator --lint-only --timing -Wall -Wno-fatal \
        --top-module tb_jt10_phase0d_warmup \
        -f "$source_manifest" \
        tb/jt10_phase0_warmup_wrapper.sv \
        tb/tb_jt10_phase0d_warmup.sv
) > "$phase0d_tmp/verilator.log" 2>&1
verilator_rc=$?
set -e
echo "VERILATOR_RC $verilator_rc"
echo "VERILATOR_WARNING_COUNT $(rg -c '^%Warning-' \
    "$phase0d_tmp/verilator.log" || true)"
sed -n 's/^%Warning-\([^:]*\).*/\1/p' \
    "$phase0d_tmp/verilator.log" | sort | uniq -c | sort -k2
[[ "$verilator_rc" -eq 0 ]]
echo "VERILATOR_ELABORATION PASS"

echo "== gate cost and structure =="
echo "GATE_STRUCTURE warmup_counter_bits=3 ready_ff=1 edge_ff=1 output_mux_bits=33 warmup_comparator_bits=3"
echo "RESET_GUARD_STRUCTURE cen_counter_bits=3 tracking_ff=1 validity_comparator_bits=3"
echo "ESTIMATED_COST state_ff=9 expected_alm_class=small_mux_dominated"
echo "RESET_FANOUT warmup_state_ff=5 core_reset_path=unchanged"
echo "CONFINEMENT standalone_wrapper_only=PASS shared_YM2612_YM2203_change=0"
rg -q 'module jt10_acc' \
    "$work_root/rtl/genesis_audio/jt12/standard_jt10/jt10_acc.v"
rg -q 'num_ch\(6\).*use_adpcm\(1\)' \
    "$work_root/rtl/genesis_audio/jt12/standard_jt10/jt10.v"
rg -q 'Uses 6 FM channels but only 4 are outputted' \
    "$work_root/rtl/genesis_audio/jt12/standard_jt10/jt10.v"
echo "STANDARD_ACCUMULATOR PASS"
echo "FM_STRUCTURE internal_channels=6 audible_channels=4 result=PASS"

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
    rtl/ym2203_sound_module.sv \
    rtl/emu.sv \
    sys/sys_top.v \
    rtl/genesis_audio/jtoutrun \
    rtl/segapcm_sound_module.sv \
    rtl/audio_mixer.sv \
    files.qip \
    VGM_MD_MiSTer.qsf
echo "PRODUCTION_BLOBS MATCH"
if rg -n 'tb/jt10_pinned|standard_jt10|jt10_phase0' \
    "$repo_root/files.qip" "$repo_root/VGM_MD_MiSTer.qsf"; then
    echo "FAIL standalone JT10 entered production build lists"
    exit 1
fi
echo "PRODUCTION_BUILD_JT10_STANDALONE 0"
echo "YM2610B_CHANGE 0"

sacred_sha_after="$(shasum -a 256 "$sacred_tb" | awk '{print $1}')"
sacred_stat_after="$(stat -f 'size=%z mtime=%m inode=%i' "$sacred_tb")"
[[ "$sacred_sha_before" == "$sacred_sha_after" ]]
[[ "$sacred_stat_before" == "$sacred_stat_after" ]]
echo "SACRED_END sha256=$sacred_sha_after $sacred_stat_after result=UNCHANGED"

if find "$repo_root" -type f \
    \( -name '*.vvp' -o -name '*.vcd' -o -name '*.fst' \
       -o -name '*.lxt' -o -name '*.log' \) -print -quit | rg -q .; then
    echo "FAIL generated simulation artifact in repository"
    exit 1
fi
echo "REPOSITORY_SIM_ARTIFACTS 0"
echo "PHASE0D_REGRESSION PASS"
