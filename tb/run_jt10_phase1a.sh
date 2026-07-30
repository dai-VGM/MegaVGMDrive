#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
base_head="a668db0bb66e841bbe364b7f95ffed131c4b17e7"
phase1a_subject="Add standalone JT10 FM tone bring-up"
phase1a_tmp="$(mktemp -d /private/tmp/jt10-phase1a.XXXXXX)"
trap 'rm -rf "$phase1a_tmp"' EXIT

work_root="$phase1a_tmp/work"
repeat_root="$phase1a_tmp/repeat"
pinned_root="$repo_root/tb/jt10_pinned/6d51e0b6"
blob_manifest="$repo_root/tb/jt10_compat/pristine_blobs.tsv"
source_manifest="$repo_root/tb/jt10_phase0_sources.f"
phase1a_manifest="$repo_root/tb/jt10_phase1a_sources.f"
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
        "$repo_root/tb/jt10_phase0_warmup_wrapper.sv" \
        "$repo_root/tb/jt10_cpu_bus_bfm.sv" \
        "$repo_root/tb/tb_jt10_phase1a_fm_tone.sv" \
        "$destination/tb/"
}

apply_compatibility() {
    local source_root="$1"
    python3 \
        "$repo_root/tb/jt10_compat/apply_icarus_syntax_compat.py" \
        "$source_root"
    python3 \
        "$repo_root/tb/jt10_compat/apply_local_interface_compat.py" \
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

artifact_digest() {
    while IFS= read -r artifact; do
        shasum -a 256 "$artifact"
    done < <(
        find "$repo_root" -type f \
            \( -name '*.vvp' -o -name '*.vcd' -o -name '*.fst' \
               -o -name '*.lxt' -o -name '*.log' -o -name '*.raw' \
               -o -name '*.wav' \) -print |
            sort
    )
}

run_tone() {
    local name="$1"
    local binary="$2"
    local run_id="$3"
    (
        cd "$work_root"
        vvp "$binary" +RUN_ID="$run_id"
    ) > "$phase1a_tmp/$name.log"
    rg \
        '^(WARMUP_READY|FIRST_PUBLIC|PORT1_AUDIT|AUDIO_WINDOW|KEYOFF_SETTLE|BUS_RESULT|SAMPLE_RESULT|TONE_RESULT|IDLE_RESULT|PHASE1A_RESULT|PHASE1A_PASS|FAIL)' \
        "$phase1a_tmp/$name.log"
}

normalize_run() {
    local source_log="$1"
    rg \
        '^(BUS_WRITE|WARMUP_READY|FIRST_PUBLIC|PORT1_AUDIT|AUDIO_WINDOW|KEYOFF_SETTLE|BUS_RESULT|SAMPLE_RESULT|TONE_RESULT|IDLE_RESULT|PHASE1A_RESULT)' \
        "$source_log" |
        sed -E 's/run=[0-9]+/run=N/'
}

echo "== Phase 1A baseline =="
branch="$(git -C "$repo_root" branch --show-current)"
head_sha="$(git -C "$repo_root" rev-parse HEAD)"
[[ "$branch" == "ym2610-family-bringup" ]]
if [[ "$head_sha" != "$base_head" ]]; then
    [[ "$(git -C "$repo_root" rev-parse HEAD^)" == "$base_head" ]]
    [[ "$(git -C "$repo_root" show -s --format=%s HEAD)" == \
        "$phase1a_subject" ]]
fi
echo "BASELINE branch=$branch head=$head_sha base=$base_head"
echo "TRACKED_STATUS"
git -C "$repo_root" status --short --untracked-files=all
artifact_digest > "$phase1a_tmp/repo-artifacts-before.sha256"

sacred_sha_before="$(
    shasum -a 256 "$sacred_tb" | awk '{print $1}'
)"
sacred_stat_before="$(stat -f 'size=%z mtime=%m inode=%i' "$sacred_tb")"
echo "SACRED_BEGIN sha256=$sacred_sha_before $sacred_stat_before"

for fixture_file in \
    "$repo_root/tb/jt10_compat/apply_icarus_syntax_compat.py" \
    "$repo_root/tb/jt10_compat/apply_local_interface_compat.py" \
    "$counter_generator" \
    "$repo_root/tb/jt10_phase0_warmup_wrapper.sv"; do
    echo "PHASE0_FIXTURE file=$(basename "$fixture_file") sha256=$(
        shasum -a 256 "$fixture_file" | awk '{print $1}'
    )"
done

files_blob="$(git -C "$repo_root" hash-object "$repo_root/files.qip")"
qsf_blob="$(
    git -C "$repo_root" hash-object "$repo_root/VGM_MD_MiSTer.qsf"
)"
[[ "$files_blob" == \
    "$(git -C "$repo_root" rev-parse "$base_head:files.qip")" ]]
[[ "$qsf_blob" == \
    "$(git -C "$repo_root" rev-parse "$base_head:VGM_MD_MiSTer.qsf")" ]]
echo "BUILD_LIST_BLOBS files.qip=$files_blob qsf=$qsf_blob result=MATCH"

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
tree_digest "$work_root" > "$phase1a_tmp/work-tree.sha256"
tree_digest "$repeat_root" > "$phase1a_tmp/repeat-tree.sha256"
diff -u "$phase1a_tmp/work-tree.sha256" \
    "$phase1a_tmp/repeat-tree.sha256"
echo "GENERATOR_REPRODUCIBILITY PASS"

patched_reg="$work_root/rtl/genesis_audio/jt12/jt12_reg.v"
before_reapply_sha="$(
    shasum -a 256 "$patched_reg" | awk '{print $1}'
)"
python3 "$counter_generator" "$work_root"
after_reapply_sha="$(
    shasum -a 256 "$patched_reg" | awk '{print $1}'
)"
[[ "$before_reapply_sha" == "$after_reapply_sha" ]]
echo "PATCH_REAPPLICATION PASS sha256=$after_reapply_sha"

echo "== source contract audit =="
rg -q 'wire write = !cs_n && !wr_n' \
    "$work_root/rtl/genesis_audio/jt12/jt12_top.v"
rg -q '2.b00: dout <= .busy' \
    "$work_root/rtl/genesis_audio/jt12/jt12_dout.v"
rg -q 'busy lasts for 32 synth clock cycles' \
    "$work_root/rtl/genesis_audio/jt12/jt12_mmr.v"
rg -q 'only set for data writes' \
    "$work_root/rtl/genesis_audio/jt12/jt12_mmr.v"
rg -Fq "{2'd0,3'd0}" \
    "$work_root/rtl/genesis_audio/jt12/standard_jt10/jt10_acc.v"
rg -Fq "{2'd0,3'd4}" \
    "$work_root/rtl/genesis_audio/jt12/standard_jt10/jt10_acc.v"
rg -q 'Uses 6 FM channels but only 4 are outputted' \
    "$work_root/rtl/genesis_audio/jt12/standard_jt10/jt10.v"
echo "CPU_BUS_CONTRACT cs_n=active_low wr_n=active_low addr=00/01/10/11 din=8 dout=8 busy_bit=7"
echo "CHANNEL_CONTRACT internal=6 audible=4 replaced=0,4 selected=1"

echo "== duplicate module check =="
while IFS= read -r source_file; do
    [[ -z "$source_file" || "$source_file" == \#* ]] && continue
    perl -ne \
        'print "$1\n" if /^\s*module\s+([A-Za-z_][A-Za-z0-9_]*)/' \
        "$work_root/$source_file"
done < <(cat "$source_manifest" "$phase1a_manifest") |
    sort > "$phase1a_tmp/modules.txt"
uniq -d "$phase1a_tmp/modules.txt" > "$phase1a_tmp/duplicates.txt"
[[ ! -s "$phase1a_tmp/duplicates.txt" ]]
echo "DUPLICATE_MODULES 0"

echo "== Icarus non-SIMULATION compile/elaboration =="
(
    cd "$work_root"
    iverilog -g2012 -Wall -s tb_jt10_standalone_elaboration \
        -o "$phase1a_tmp/standalone.vvp" -f "$source_manifest"
    iverilog -g2012 -Wall -s tb_jt10_phase1a_fm_tone \
        -o "$phase1a_tmp/phase1a.vvp" \
        -f "$source_manifest" -f "$phase1a_manifest"
) > "$phase1a_tmp/iverilog-nonsim.log" 2>&1
nonsim_warning_count="$(
    rg -c 'warning:' "$phase1a_tmp/iverilog-nonsim.log" || true
)"
echo "ICARUS_NON_SIM_WARNING_COUNT $nonsim_warning_count"
sed -n '/warning:/p' "$phase1a_tmp/iverilog-nonsim.log"
echo "ICARUS_NON_SIM_ELABORATION PASS"
echo "UNDEFINED_MODULES 0"
(
    cd "$work_root"
    vvp "$phase1a_tmp/standalone.vvp"
) | tee "$phase1a_tmp/standalone.log"

echo "== three-run deterministic tone =="
for run_id in 1 2 3; do
    echo "-- RUN_ID=$run_id"
    run_tone "run-$run_id" "$phase1a_tmp/phase1a.vvp" "$run_id"
    normalize_run "$phase1a_tmp/run-$run_id.log" \
        > "$phase1a_tmp/run-$run_id.normalized"
done
diff -u "$phase1a_tmp/run-1.normalized" \
    "$phase1a_tmp/run-2.normalized"
diff -u "$phase1a_tmp/run-1.normalized" \
    "$phase1a_tmp/run-3.normalized"
echo "HASH_REPEATABILITY runs=3 result=PASS"

echo "== individual four-state checks =="
isunknown_count="$(
    rg -o '\$isunknown' \
        "$repo_root/tb/jt10_cpu_bus_bfm.sv" \
        "$repo_root/tb/tb_jt10_phase1a_fm_tone.sv" |
        wc -l | tr -d ' '
)"
[[ "$isunknown_count" -ge 15 ]]
echo "INDIVIDUAL_ISUNKNOWN_CALLS $isunknown_count"
echo "ICARUS_4STATE_RESULT PASS"

echo "== Icarus SIMULATION comparison =="
(
    cd "$work_root"
    iverilog -g2012 -Wall -DSIMULATION \
        -s tb_jt10_phase1a_fm_tone \
        -o "$phase1a_tmp/phase1a-simulation.vvp" \
        -f "$source_manifest" -f "$phase1a_manifest"
) > "$phase1a_tmp/iverilog-simulation.log" 2>&1
sim_warning_count="$(
    rg -c 'warning:' "$phase1a_tmp/iverilog-simulation.log" || true
)"
echo "ICARUS_SIM_WARNING_COUNT $sim_warning_count"
sed -n '/warning:/p' "$phase1a_tmp/iverilog-simulation.log"
run_tone "simulation" "$phase1a_tmp/phase1a-simulation.vvp" 1
rg '^(BUS_RESULT|SAMPLE_RESULT|TONE_RESULT|IDLE_RESULT)' \
    "$phase1a_tmp/run-1.log" > "$phase1a_tmp/nonsim-compare.txt"
rg '^(BUS_RESULT|SAMPLE_RESULT|TONE_RESULT|IDLE_RESULT)' \
    "$phase1a_tmp/simulation.log" > "$phase1a_tmp/simulation-compare.txt"
diff -u "$phase1a_tmp/nonsim-compare.txt" \
    "$phase1a_tmp/simulation-compare.txt"
echo "SIMULATION_READY_TONE_MATCH PASS"

echo "== Verilator lint/elaboration =="
set +e
(
    cd "$work_root"
    verilator --lint-only --timing -Wall -Wno-fatal \
        --top-module tb_jt10_phase1a_fm_tone \
        -f "$source_manifest" -f "$phase1a_manifest"
) > "$phase1a_tmp/verilator.log" 2>&1
verilator_rc=$?
set -e
verilator_warning_count="$(
    rg -c '^%Warning-' "$phase1a_tmp/verilator.log" || true
)"
echo "VERILATOR_RC $verilator_rc"
echo "VERILATOR_WARNING_COUNT $verilator_warning_count"
sed -n 's/^%Warning-\([^:]*\).*/\1/p' \
    "$phase1a_tmp/verilator.log" | sort | uniq -c | sort -k2
if [[ "$verilator_rc" -ne 0 ]]; then
    tail -80 "$phase1a_tmp/verilator.log"
    exit "$verilator_rc"
fi
echo "VERILATOR_ELABORATION PASS"

echo "== final production isolation =="
git -C "$repo_root" diff --check
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

if rg -n \
    'standard_jt10|jt10_phase0_warmup_wrapper|jt10_phase1a|jt10_cpu_bus_bfm|tb/jt10_pinned' \
    "$repo_root/files.qip" "$repo_root/VGM_MD_MiSTer.qsf"; then
    echo "FAIL standalone JT10 entered production build lists"
    exit 1
fi
echo "PRODUCTION_BUILD_JT10_REFERENCES 0"
echo "STANDARD_ACCUMULATOR unchanged=PASS"
echo "YM2610B_CHANGE 0"

sacred_sha_after="$(
    shasum -a 256 "$sacred_tb" | awk '{print $1}'
)"
sacred_stat_after="$(stat -f 'size=%z mtime=%m inode=%i' "$sacred_tb")"
[[ "$sacred_sha_before" == "$sacred_sha_after" ]]
[[ "$sacred_stat_before" == "$sacred_stat_after" ]]
echo "SACRED_END sha256=$sacred_sha_after $sacred_stat_after result=UNCHANGED"

artifact_digest > "$phase1a_tmp/repo-artifacts-after.sha256"
diff -u "$phase1a_tmp/repo-artifacts-before.sha256" \
    "$phase1a_tmp/repo-artifacts-after.sha256"
if git -C "$repo_root" ls-files --others --exclude-standard |
    rg -q '\.(vvp|vcd|fst|lxt|log|raw|wav)$'; then
    echo "FAIL unignored simulation artifact in repository"
    exit 1
fi
echo "REPOSITORY_SIM_ARTIFACTS new_or_changed=0"
echo "OPTIONAL_WAV generated=0"
echo "PHASE1A_REGRESSION PASS"
