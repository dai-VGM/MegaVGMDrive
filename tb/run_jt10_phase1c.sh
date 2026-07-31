#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
base_head="cc2cd261744d83aa89c6ffc00c68701ba1bbd60c"
phase1c_head="bee41751e46c2032ecb8288d15746c44d8bc3ae2"
phase2a_head="517f5c2af12527c71b63e819857b9f4221584dec"
phase2b_head="82290dc61912af144bbf5f0c291e9cbed4ee5ffd"
phase1c_subject="Cover all standard JT10 FM channels"
phase2a_subject="Add standalone JT10 SSG tone bring-up"
phase2b_subject="Cover all JT10 SSG tone channels"
phase3a_subject="Add standalone JT10 ADPCM-A voice 0 bring-up"
phase1c_tmp="$(mktemp -d /private/tmp/jt10-phase1c.XXXXXX)"
trap 'rm -rf "$phase1c_tmp"' EXIT

work_root="$phase1c_tmp/work"
repeat_root="$phase1c_tmp/repeat"
pinned_root="$repo_root/tb/jt10_pinned/6d51e0b6"
blob_manifest="$repo_root/tb/jt10_compat/pristine_blobs.tsv"
source_manifest="$repo_root/tb/jt10_phase0_sources.f"
phase1a_manifest="$repo_root/tb/jt10_phase1a_sources.f"
phase1b_manifest="$repo_root/tb/jt10_phase1b_sources.f"
phase1c_manifest="$repo_root/tb/jt10_phase1c_sources.f"
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
        "$repo_root/tb/tb_jt10_phase1b_fm_tone.sv" \
        "$repo_root/tb/tb_jt10_phase1c_ch2_fm_tone.sv" \
        "$repo_root/tb/tb_jt10_phase1c_ch6_fm_tone.sv" \
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

run_fixture() {
    local name="$1"
    local binary="$2"
    local run_id="$3"
    (
        cd "$work_root"
        vvp "$binary" +RUN_ID="$run_id"
    ) > "$phase1c_tmp/$name.log"
    rg \
        '^(WARMUP_READY|FIRST_PUBLIC|PORT1_AUDIT|CHANNEL_AUDIT|ACCUMULATOR_TRACE|AUDIO_WINDOW|MUTE_SETTLE|KEYOFF_SETTLE|BUS_RESULT|SAMPLE_RESULT|TONE_RESULT|TONE_COMPARE|IDLE_RESULT|PHASE1[ABC]_RESULT|PHASE1[ABC]_PASS|FAIL)' \
        "$phase1c_tmp/$name.log"
}

normalize_fixture() {
    local source_log="$1"
    rg \
        '^(BUS_WRITE|WARMUP_READY|FIRST_PUBLIC|PORT1_AUDIT|CHANNEL_AUDIT|ACCUMULATOR_TRACE|AUDIO_WINDOW|MUTE_SETTLE|KEYOFF_SETTLE|BUS_RESULT|SAMPLE_RESULT|TONE_RESULT|TONE_COMPARE|IDLE_RESULT|PHASE1[ABC]_RESULT)' \
        "$source_log" |
        sed -E 's/run=[0-9]+/run=N/'
}

ready_result() {
    local source_log="$1"
    rg \
        '^(BUS_RESULT|SAMPLE_RESULT|TONE_RESULT|TONE_COMPARE|IDLE_RESULT|ACCUMULATOR_TRACE|PHASE1[ABC]_RESULT)' \
        "$source_log"
}

tone_field() {
    local source_log="$1"
    local field_name="$2"
    rg '^TONE_RESULT ' "$source_log" |
        sed -E "s/.* ${field_name}=([^ ]+).*/\\1/"
}

echo "== Phase 1C baseline =="
branch="$(git -C "$repo_root" branch --show-current)"
head_sha="$(git -C "$repo_root" rev-parse HEAD)"
[[ "$branch" == "ym2610-family-bringup" ]]
if [[ "$head_sha" != "$base_head" ]]; then
    if [[ "$head_sha" == "$phase1c_head" ]]; then
        [[ "$(git -C "$repo_root" rev-parse HEAD^)" == "$base_head" ]]
        [[ "$(git -C "$repo_root" show -s --format=%s HEAD)" == \
            "$phase1c_subject" ]]
    elif [[ "$head_sha" == "$phase2a_head" ]]; then
        [[ "$(git -C "$repo_root" rev-parse HEAD^)" == \
            "$phase1c_head" ]]
        [[ "$(git -C "$repo_root" show -s --format=%s HEAD)" == \
            "$phase2a_subject" ]]
    elif [[ "$head_sha" == "$phase2b_head" ]]; then
        [[ "$(git -C "$repo_root" rev-parse HEAD^)" == \
            "$phase2a_head" ]]
        [[ "$(git -C "$repo_root" show -s --format=%s HEAD)" == \
            "$phase2b_subject" ]]
    else
        [[ "$(git -C "$repo_root" rev-parse HEAD^)" == \
            "$phase2b_head" ]]
        [[ "$(git -C "$repo_root" show -s --format=%s HEAD)" == \
            "$phase3a_subject" ]]
    fi
fi
echo "BASELINE branch=$branch head=$head_sha base=$base_head"
git -C "$repo_root" status --short --untracked-files=all
artifact_digest > "$phase1c_tmp/repo-artifacts-before.sha256"

sacred_sha_before="$(
    shasum -a 256 "$sacred_tb" | awk '{print $1}'
)"
sacred_stat_before="$(stat -f 'size=%z mtime=%m inode=%i' "$sacred_tb")"
echo "SACRED_BEGIN sha256=$sacred_sha_before $sacred_stat_before"

for fixture_file in \
    "$repo_root/tb/jt10_compat/apply_icarus_syntax_compat.py" \
    "$repo_root/tb/jt10_compat/apply_local_interface_compat.py" \
    "$counter_generator" \
    "$repo_root/tb/jt10_phase0_warmup_wrapper.sv" \
    "$repo_root/tb/jt10_cpu_bus_bfm.sv" \
    "$repo_root/tb/tb_jt10_phase1a_fm_tone.sv" \
    "$repo_root/tb/run_jt10_phase1a.sh" \
    "$repo_root/tb/tb_jt10_phase1b_fm_tone.sv" \
    "$repo_root/tb/run_jt10_phase1b.sh"; do
    [[ -f "$fixture_file" ]]
    echo "FIXTURE file=$(basename "$fixture_file") sha256=$(
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
    [[ "$(git -C "$repo_root" hash-object "$source_file")" == \
        "$expected_blob" ]]
    [[ "$(shasum -a 256 "$source_file" | awk '{print $1}')" == \
        "$expected_sha" ]]
    pinned_count=$((pinned_count + 1))
done < "$blob_manifest"
[[ "$pinned_count" -eq 15 ]]
echo "PRISTINE_PINNED count=$pinned_count result=MATCH"

copy_sources "$work_root"
copy_sources "$repeat_root"
apply_compatibility "$work_root"
apply_compatibility "$repeat_root"
tree_digest "$work_root" > "$phase1c_tmp/work-tree.sha256"
tree_digest "$repeat_root" > "$phase1c_tmp/repeat-tree.sha256"
diff -u "$phase1c_tmp/work-tree.sha256" \
    "$phase1c_tmp/repeat-tree.sha256"
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

echo "== source and mapping contract audit =="
accumulator="$work_root/rtl/genesis_audio/jt12/standard_jt10/jt10_acc.v"
mmr="$work_root/rtl/genesis_audio/jt12/jt12_mmr.v"
rg -Fq 'case( {cur_op,cur_ch} )' "$accumulator"
rg -Fq "{2'd0,3'd0}" "$accumulator"
rg -Fq "{2'd0,3'd4}" "$accumulator"
rg -Fq 'acc_input_l = opext >>> 1' "$accumulator"
rg -Fq 'up_ch <= {part, selected_register[1:0]}' "$mmr"
rg -Fq 'up_keyon <= selected_register == REG_KON && !part' "$mmr"
rg -q 'busy lasts for 32 synth clock cycles' "$mmr"
echo "CHANNEL_CONTRACT encoding=2 port=0 offset=2 fnum=A6/A2 alg=B2 pan=B6 keyon=12 audible=PASS"
echo "CHANNEL_CONTRACT encoding=6 port=1 offset=2 fnum=A6/A2 alg=B2 pan=B6 keyon_port=0 keyon=16 audible=PASS"
echo "ACCUMULATOR_PREDICATES encoding0='{2d0,3d0}:ADPCM-A' encoding4='{2d0,3d4}:ADPCM-B' audible_default=1,2,5,6 result=PASS"

echo "== duplicate module check =="
while IFS= read -r source_file; do
    [[ -z "$source_file" || "$source_file" == \#* ]] && continue
    perl -ne \
        'print "$1\n" if /^\s*module\s+([A-Za-z_][A-Za-z0-9_]*)/' \
        "$work_root/$source_file"
done < <(cat "$source_manifest" "$phase1a_manifest" \
              "$phase1b_manifest" "$phase1c_manifest") |
    sort > "$phase1c_tmp/modules.txt"
uniq -d "$phase1c_tmp/modules.txt" > "$phase1c_tmp/duplicates.txt"
[[ ! -s "$phase1c_tmp/duplicates.txt" ]]
echo "DUPLICATE_MODULES 0"

echo "== Icarus non-SIMULATION compile/elaboration =="
set +e
(
    cd "$work_root"
    iverilog -g2012 -Wall -s tb_jt10_standalone_elaboration \
        -o "$phase1c_tmp/standalone.vvp" -f "$source_manifest"
    iverilog -g2012 -Wall -s tb_jt10_phase1a_fm_tone \
        -o "$phase1c_tmp/ch1.vvp" \
        -f "$source_manifest" -f "$phase1a_manifest"
    iverilog -g2012 -Wall -s tb_jt10_phase1b_fm_tone \
        -o "$phase1c_tmp/ch5.vvp" \
        -f "$source_manifest" -f "$phase1a_manifest" \
        -f "$phase1b_manifest"
    iverilog -g2012 -Wall -s tb_jt10_phase1c_ch2_fm_tone \
        -o "$phase1c_tmp/ch2.vvp" \
        -f "$source_manifest" -f "$phase1a_manifest" \
        -f "$phase1c_manifest"
    iverilog -g2012 -Wall -s tb_jt10_phase1c_ch6_fm_tone \
        -o "$phase1c_tmp/ch6.vvp" \
        -f "$source_manifest" -f "$phase1a_manifest" \
        -f "$phase1c_manifest"
) > "$phase1c_tmp/iverilog-nonsim.log" 2>&1
nonsim_rc=$?
set -e
if [[ "$nonsim_rc" -ne 0 ]]; then
    cat "$phase1c_tmp/iverilog-nonsim.log"
    exit "$nonsim_rc"
fi
nonsim_warning_count="$(
    rg -c 'warning:' "$phase1c_tmp/iverilog-nonsim.log" || true
)"
echo "ICARUS_NON_SIM_WARNING_COUNT $nonsim_warning_count"
sed -n '/warning:/p' "$phase1c_tmp/iverilog-nonsim.log"
echo "ICARUS_NON_SIM_ELABORATION PASS"
echo "UNDEFINED_MODULES 0"
(
    cd "$work_root"
    vvp "$phase1c_tmp/standalone.vvp"
) | tee "$phase1c_tmp/standalone.log"

echo "== Phase 1A encoding-1 regression =="
run_fixture "ch1-run-1" "$phase1c_tmp/ch1.vvp" 1
rg -q \
    '^BUS_RESULT port0=51 port1=1 accepted=52 timeout=0 write_while_busy=0 busy_min=190 busy_max=192 busy_hash=c46243ae1f792b2a$' \
    "$phase1c_tmp/ch1-run-1.log"
rg -q \
    'steady_hash=8aadd7a6819038e5.*mute_hash=28c31cf8df2ec325.*frequency_hash=00c6bce80cda4ce1.*keyoff_hash=28c31cf8df2ec325' \
    "$phase1c_tmp/ch1-run-1.log"
rg -q '^PHASE1A_PASS run=1$' "$phase1c_tmp/ch1-run-1.log"
echo "PHASE1A_REGRESSION PASS"

echo "== Phase 1B encoding-5 regression =="
run_fixture "ch5-run-1" "$phase1c_tmp/ch5.vvp" 1
rg -q \
    '^BUS_RESULT port0=11 port1=37 accepted=48 timeout=0 write_while_busy=0 busy_min=190 busy_max=192 busy_hash=99b902b786403dfa$' \
    "$phase1c_tmp/ch5-run-1.log"
rg -q \
    'attack_hash=c8bafcdd6f79173d.*steady_hash=8aadd7a6819038e5.*mute_hash=28c31cf8df2ec325.*frequency_hash=3877bd297ab451fd.*keyoff_hash=28c31cf8df2ec325' \
    "$phase1c_tmp/ch5-run-1.log"
rg -q '^PHASE1B_PASS run=1$' "$phase1c_tmp/ch5-run-1.log"
echo "PHASE1B_REGRESSION PASS"

echo "== Phase 1C encoding-2 three-run determinism =="
for run_id in 1 2 3; do
    echo "-- ENCODING=2 RUN_ID=$run_id"
    run_fixture "ch2-run-$run_id" "$phase1c_tmp/ch2.vvp" "$run_id"
    rg -q \
        '^BUS_RESULT port0=48 port1=0 accepted=48 timeout=0 write_while_busy=0 busy_min=190 busy_max=192 busy_hash=99b902b786403dfa$' \
        "$phase1c_tmp/ch2-run-$run_id.log"
    rg -q \
        'attack_hash=c8bafcdd6f79173d.*steady_hash=8aadd7a6819038e5.*mute_hash=28c31cf8df2ec325.*frequency_hash=3877bd297ab451fd.*keyoff_hash=28c31cf8df2ec325' \
        "$phase1c_tmp/ch2-run-$run_id.log"
    rg -q \
        '^ACCUMULATOR_TRACE target_encoding=2 .*selector_mismatches=0 ' \
        "$phase1c_tmp/ch2-run-$run_id.log"
    rg -q \
        "^PHASE1C_PASS run=$run_id target_encoding=2$" \
        "$phase1c_tmp/ch2-run-$run_id.log"
    normalize_fixture "$phase1c_tmp/ch2-run-$run_id.log" \
        > "$phase1c_tmp/ch2-run-$run_id.normalized"
done
diff -u "$phase1c_tmp/ch2-run-1.normalized" \
    "$phase1c_tmp/ch2-run-2.normalized"
diff -u "$phase1c_tmp/ch2-run-1.normalized" \
    "$phase1c_tmp/ch2-run-3.normalized"
echo "ENCODING2_HASH_AND_LANDMARK_REPEATABILITY runs=3 result=PASS"

echo "== Phase 1C encoding-6 three-run determinism =="
for run_id in 1 2 3; do
    echo "-- ENCODING=6 RUN_ID=$run_id"
    run_fixture "ch6-run-$run_id" "$phase1c_tmp/ch6.vvp" "$run_id"
    rg -q \
        '^BUS_RESULT port0=11 port1=37 accepted=48 timeout=0 write_while_busy=0 busy_min=190 busy_max=192 busy_hash=99b902b786403dfa$' \
        "$phase1c_tmp/ch6-run-$run_id.log"
    rg -q \
        'attack_hash=c8bafcdd6f79173d.*steady_hash=8aadd7a6819038e5.*mute_hash=28c31cf8df2ec325.*frequency_hash=3877bd297ab451fd.*keyoff_hash=28c31cf8df2ec325' \
        "$phase1c_tmp/ch6-run-$run_id.log"
    rg -q \
        '^ACCUMULATOR_TRACE target_encoding=6 .*selector_mismatches=0 ' \
        "$phase1c_tmp/ch6-run-$run_id.log"
    rg -q \
        "^PHASE1C_PASS run=$run_id target_encoding=6$" \
        "$phase1c_tmp/ch6-run-$run_id.log"
    normalize_fixture "$phase1c_tmp/ch6-run-$run_id.log" \
        > "$phase1c_tmp/ch6-run-$run_id.normalized"
done
diff -u "$phase1c_tmp/ch6-run-1.normalized" \
    "$phase1c_tmp/ch6-run-2.normalized"
diff -u "$phase1c_tmp/ch6-run-1.normalized" \
    "$phase1c_tmp/ch6-run-3.normalized"
echo "ENCODING6_HASH_AND_LANDMARK_REPEATABILITY runs=3 result=PASS"

echo "== four-channel primary waveform comparison =="
for encoding in 1 2 5 6; do
    source_log="$phase1c_tmp/ch${encoding}-run-1.log"
    echo "FOUR_CHANNEL encoding=$encoding steady_hash=$(tone_field "$source_log" steady_hash) peak=$(tone_field "$source_log" peak) min=$(tone_field "$source_log" min) max=$(tone_field "$source_log" max) zero_crossings=$(tone_field "$source_log" zero_crossings) dc_sum=$(tone_field "$source_log" dc_sum)"
done
ch1_hash="$(tone_field "$phase1c_tmp/ch1-run-1.log" steady_hash)"
ch2_hash="$(tone_field "$phase1c_tmp/ch2-run-1.log" steady_hash)"
ch5_hash="$(tone_field "$phase1c_tmp/ch5-run-1.log" steady_hash)"
ch6_hash="$(tone_field "$phase1c_tmp/ch6-run-1.log" steady_hash)"
[[ "$ch1_hash" == "$ch2_hash" ]]
[[ "$ch1_hash" == "$ch5_hash" ]]
[[ "$ch1_hash" == "$ch6_hash" ]]
echo "FOUR_CHANNEL_WAVEFORM_MATCH hash=$ch1_hash alignment=0 polarity=same phase=same result=PASS"

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

echo "== Icarus SIMULATION four-fixture comparison =="
set +e
(
    cd "$work_root"
    iverilog -g2012 -Wall -DSIMULATION \
        -s tb_jt10_phase1a_fm_tone \
        -o "$phase1c_tmp/ch1-sim.vvp" \
        -f "$source_manifest" -f "$phase1a_manifest"
    iverilog -g2012 -Wall -DSIMULATION \
        -s tb_jt10_phase1b_fm_tone \
        -o "$phase1c_tmp/ch5-sim.vvp" \
        -f "$source_manifest" -f "$phase1a_manifest" \
        -f "$phase1b_manifest"
    iverilog -g2012 -Wall -DSIMULATION \
        -s tb_jt10_phase1c_ch2_fm_tone \
        -o "$phase1c_tmp/ch2-sim.vvp" \
        -f "$source_manifest" -f "$phase1a_manifest" \
        -f "$phase1c_manifest"
    iverilog -g2012 -Wall -DSIMULATION \
        -s tb_jt10_phase1c_ch6_fm_tone \
        -o "$phase1c_tmp/ch6-sim.vvp" \
        -f "$source_manifest" -f "$phase1a_manifest" \
        -f "$phase1c_manifest"
) > "$phase1c_tmp/iverilog-simulation.log" 2>&1
sim_rc=$?
set -e
if [[ "$sim_rc" -ne 0 ]]; then
    cat "$phase1c_tmp/iverilog-simulation.log"
    exit "$sim_rc"
fi
sim_warning_count="$(
    rg -c 'warning:' "$phase1c_tmp/iverilog-simulation.log" || true
)"
echo "ICARUS_SIM_WARNING_COUNT $sim_warning_count"
sed -n '/warning:/p' "$phase1c_tmp/iverilog-simulation.log"

for encoding in 1 2 5 6; do
    run_fixture "ch${encoding}-simulation" \
        "$phase1c_tmp/ch${encoding}-sim.vvp" 1
    ready_result "$phase1c_tmp/ch${encoding}-run-1.log" \
        > "$phase1c_tmp/ch${encoding}-nonsim-ready.txt"
    ready_result "$phase1c_tmp/ch${encoding}-simulation.log" \
        > "$phase1c_tmp/ch${encoding}-sim-ready.txt"
    diff -u "$phase1c_tmp/ch${encoding}-nonsim-ready.txt" \
        "$phase1c_tmp/ch${encoding}-sim-ready.txt"
    echo "SIMULATION_READY_MATCH encoding=$encoding result=PASS"
done

echo "== Verilator lint/elaboration =="
set +e
(
    cd "$work_root"
    verilator --lint-only --timing -Wall -Wno-fatal \
        --top-module tb_jt10_phase1c_ch2_fm_tone \
        -f "$source_manifest" -f "$phase1a_manifest" \
        -f "$phase1c_manifest"
    ch2_rc=$?
    verilator --lint-only --timing -Wall -Wno-fatal \
        --top-module tb_jt10_phase1c_ch6_fm_tone \
        -f "$source_manifest" -f "$phase1a_manifest" \
        -f "$phase1c_manifest"
    ch6_rc=$?
    exit $((ch2_rc | ch6_rc))
) > "$phase1c_tmp/verilator.log" 2>&1
verilator_rc=$?
set -e
verilator_warning_count="$(
    rg -c '^%Warning-' "$phase1c_tmp/verilator.log" || true
)"
echo "VERILATOR_RC $verilator_rc"
echo "VERILATOR_WARNING_COUNT $verilator_warning_count"
sed -n 's/^%Warning-\([^:]*\).*/\1/p' \
    "$phase1c_tmp/verilator.log" | sort | uniq -c | sort -k2
if [[ "$verilator_rc" -ne 0 ]]; then
    tail -80 "$phase1c_tmp/verilator.log"
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
    'standard_jt10|jt10_phase0_warmup_wrapper|jt10_phase1a|jt10_phase1b|jt10_phase1c|jt10_cpu_bus_bfm|tb/jt10_pinned' \
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

artifact_digest > "$phase1c_tmp/repo-artifacts-after.sha256"
diff -u "$phase1c_tmp/repo-artifacts-before.sha256" \
    "$phase1c_tmp/repo-artifacts-after.sha256"
if git -C "$repo_root" ls-files --others --exclude-standard |
    rg -q '\.(vvp|vcd|fst|lxt|log|raw|wav)$'; then
    echo "FAIL unignored simulation artifact in repository"
    exit 1
fi
echo "REPOSITORY_SIM_ARTIFACTS new_or_changed=0"
echo "PHASE1C_REGRESSION PASS"
