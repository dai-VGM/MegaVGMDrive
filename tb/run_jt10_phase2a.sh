#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
base_head="bee41751e46c2032ecb8288d15746c44d8bc3ae2"
phase2a_head="517f5c2af12527c71b63e819857b9f4221584dec"
phase2a_subject="Add standalone JT10 SSG tone bring-up"
phase2b_subject="Cover all JT10 SSG tone channels"
phase2a_tmp="$(mktemp -d /private/tmp/jt10-phase2a.XXXXXX)"
trap 'rm -rf "$phase2a_tmp"' EXIT

work_root="$phase2a_tmp/work"
repeat_root="$phase2a_tmp/repeat"
pinned_root="$repo_root/tb/jt10_pinned/6d51e0b6"
blob_manifest="$repo_root/tb/jt10_compat/pristine_blobs.tsv"
source_manifest="$repo_root/tb/jt10_phase0_sources.f"
phase2a_manifest="$repo_root/tb/jt10_phase2a_sources.f"
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
        "$repo_root/tb/tb_jt10_phase2a_ssg_chA_tone.sv" \
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
    ) > "$phase2a_tmp/$name.log"
    rg \
        '^(WARMUP_READY|FIRST_PUBLIC|SSG_WINDOW|SSG_ZERO_SETTLE|MIXER_DC_LOCK|BUS_RESULT|SAMPLE_RESULT|SSG_RESULT|IDLE_RESULT|SSG_TONE_PASS|FAIL)' \
        "$phase2a_tmp/$name.log"
}

normalize_fixture() {
    local source_log="$1"
    rg \
        '^(BUS_WRITE|SSG_TRANSPORT|WARMUP_READY|FIRST_PUBLIC|SSG_WINDOW|SSG_ZERO_SETTLE|MIXER_DC_LOCK|BUS_RESULT|SAMPLE_RESULT|SSG_RESULT|IDLE_RESULT)' \
        "$source_log" |
        sed -E 's/run=[0-9]+/run=N/'
}

ready_result() {
    local source_log="$1"
    rg \
        '^(BUS_RESULT|SAMPLE_RESULT|SSG_RESULT|IDLE_RESULT)' \
        "$source_log"
}

echo "== Phase 2A baseline =="
branch="$(git -C "$repo_root" branch --show-current)"
head_sha="$(git -C "$repo_root" rev-parse HEAD)"
[[ "$branch" == "ym2610-family-bringup" ]]
if [[ "$head_sha" != "$base_head" ]]; then
    if [[ "$head_sha" == "$phase2a_head" ]]; then
        [[ "$(git -C "$repo_root" rev-parse HEAD^)" == "$base_head" ]]
        [[ "$(git -C "$repo_root" show -s --format=%s HEAD)" == \
            "$phase2a_subject" ]]
    else
        [[ "$(git -C "$repo_root" rev-parse HEAD^)" == \
            "$phase2a_head" ]]
        [[ "$(git -C "$repo_root" show -s --format=%s HEAD)" == \
            "$phase2b_subject" ]]
    fi
fi
echo "BASELINE branch=$branch head=$head_sha base=$base_head"
git -C "$repo_root" status --short --untracked-files=all
artifact_digest > "$phase2a_tmp/repo-artifacts-before.sha256"

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
    "$repo_root/tb/jt10_cpu_bus_bfm.sv"; do
    fixture_name="$(basename "$fixture_file")"
    case "$fixture_name" in
        apply_icarus_syntax_compat.py)
            expected_fixture_sha=546441b9f757cab983fe185f79d1fc33ed54f5e5a11f1532034d1f9fbebaee36
            ;;
        apply_local_interface_compat.py)
            expected_fixture_sha=51548fe271061795af63d9d8c9b029595e03498af5c88ad2c6f2249b7f30a223
            ;;
        apply_jt10_counter_reset_compat.py)
            expected_fixture_sha=a47126debb59719cef63f2e4787dd5bccb8b45b80b1ee5a7c205ea4aca4b5c29
            ;;
        jt10_phase0_warmup_wrapper.sv)
            expected_fixture_sha=b5ec92841b2653b1e3615587aad4c1c06c9d4eb4de1334a32ce58fa7bb3e18f0
            ;;
        jt10_cpu_bus_bfm.sv)
            expected_fixture_sha=5879651fefbcac6f024aa489961eae859f3069178e6a4edc86550315c5e212c5
            ;;
        *)
            echo "FAIL unexpected fixture $fixture_name"
            exit 1
            ;;
    esac
    fixture_sha="$(
        shasum -a 256 "$fixture_file" | awk '{print $1}'
    )"
    [[ "$fixture_sha" == "$expected_fixture_sha" ]]
    echo "FIXTURE file=$fixture_name sha256=$fixture_sha result=MATCH"
done

for phase1_file in \
    "$repo_root/tb/tb_jt10_phase1a_fm_tone.sv" \
    "$repo_root/tb/tb_jt10_phase1b_fm_tone.sv" \
    "$repo_root/tb/tb_jt10_phase1c_ch2_fm_tone.sv" \
    "$repo_root/tb/tb_jt10_phase1c_ch6_fm_tone.sv" \
    "$repo_root/tb/run_jt10_phase1c.sh" \
    "$repo_root/tb/jt10_phase1c_fixture.md"; do
    [[ -f "$phase1_file" ]]
done
echo "PHASE1_FIXTURES result=PRESENT"

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

jt49_tree="$(git -C "$repo_root" rev-parse "$base_head:rtl/genesis_audio/jt49")"
[[ "$jt49_tree" == "63a434df533450acc14170bc3d2e91fa13faf806" ]]
rg -Fq '9d097f1eefad3530567b71f13016f6e8546a4bb5' \
    "$repo_root/rtl/genesis_audio/README.md"
rg -Fq '24c4a0cdb8b0ae1940593fd26ec547c16bd9a8cf' \
    "$repo_root/rtl/genesis_audio/README.md"
echo "JT49_PIN tree=$jt49_tree upstream=9d097f1eefad3530567b71f13016f6e8546a4bb5 local_reset=24c4a0cdb8b0ae1940593fd26ec547c16bd9a8cf result=MATCH"

copy_sources "$work_root"
copy_sources "$repeat_root"
apply_compatibility "$work_root"
apply_compatibility "$repeat_root"
tree_digest "$work_root" > "$phase2a_tmp/work-tree.sha256"
tree_digest "$repeat_root" > "$phase2a_tmp/repeat-tree.sha256"
diff -u "$phase2a_tmp/work-tree.sha256" \
    "$phase2a_tmp/repeat-tree.sha256"
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

echo "== source and SSG contract audit =="
mmr="$work_root/rtl/genesis_audio/jt12/jt12_mmr.v"
top="$work_root/rtl/genesis_audio/jt12/jt12_top.v"
jt49="$work_root/rtl/genesis_audio/jt49/jt49.v"
pinned_jt10="$work_root/rtl/genesis_audio/jt12/standard_jt10/jt10.v"
rg -Fq '8'\''h0?: psg_wr_n <= 1'\''b0;' "$mmr"
rg -Fq 'assign psg_addr = selected_register[3:0];' "$mmr"
rg -Fq '.JT49_DIV(3)' "$pinned_jt10"
rg -Fq 'jt49 #(.COMP(2'\''b01), .CLKDIV(JT49_DIV))' "$top"
rg -Fq 'assign snd_left  = fm_snd_left  + { 1'\''b0, psg_snd[9:0],5'\''d0};' "$top"
rg -Fq 'Amix <= (noise|use_noA) & (bitA|regarray[7][0]);' "$jt49"
rg -Fq 'logA <= !Amix ? 5'\''d0 : (use_envA ? envelope : volA );' "$jt49"
rg -Fq 'wire [4:0] volA = { regarray[ 8][3:0], regarray[ 8][3] };' "$jt49"
echo "SSG_CONTRACT port=0 range=00-0F periodA=00/01 noise=06 mixer=07 volumeA=08 divider=3 raw_width=8 combined_width=10 final_gain=32 result=PASS"
echo "MIXER_DC_CONTRACT r7=3F fixed_volume=0F rawA=255 psg=255 final=8160 silence_control=volume_zero result=PASS"

echo "== duplicate module check =="
while IFS= read -r source_file; do
    [[ -z "$source_file" || "$source_file" == \#* ]] && continue
    perl -ne \
        'print "$1\n" if /^\s*module\s+([A-Za-z_][A-Za-z0-9_]*)/' \
        "$work_root/$source_file"
done < <(cat "$source_manifest" "$phase2a_manifest") |
    sort > "$phase2a_tmp/modules.txt"
uniq -d "$phase2a_tmp/modules.txt" > "$phase2a_tmp/duplicates.txt"
[[ ! -s "$phase2a_tmp/duplicates.txt" ]]
echo "DUPLICATE_MODULES 0"

echo "== Icarus non-SIMULATION compile/elaboration =="
set +e
(
    cd "$work_root"
    iverilog -g2012 -Wall -s tb_jt10_standalone_elaboration \
        -o "$phase2a_tmp/standalone.vvp" -f "$source_manifest"
    iverilog -g2012 -Wall -s tb_jt10_phase2a_ssg_chA_tone \
        -o "$phase2a_tmp/phase2a.vvp" \
        -f "$source_manifest" -f "$phase2a_manifest"
) > "$phase2a_tmp/iverilog-nonsim.log" 2>&1
nonsim_rc=$?
set -e
if [[ "$nonsim_rc" -ne 0 ]]; then
    cat "$phase2a_tmp/iverilog-nonsim.log"
    exit "$nonsim_rc"
fi
nonsim_warning_count="$(
    rg -c 'warning:' "$phase2a_tmp/iverilog-nonsim.log" || true
)"
echo "ICARUS_NON_SIM_WARNING_COUNT $nonsim_warning_count"
sed -n '/warning:/p' "$phase2a_tmp/iverilog-nonsim.log"
echo "ICARUS_NON_SIM_ELABORATION PASS"
echo "UNDEFINED_MODULES 0"
(
    cd "$work_root"
    vvp "$phase2a_tmp/standalone.vvp"
) | tee "$phase2a_tmp/standalone.log"

echo "== Phase 2A three-run determinism =="
for run_id in 1 2 3; do
    echo "-- PHASE2A RUN_ID=$run_id"
    run_fixture "phase2a-run-$run_id" \
        "$phase2a_tmp/phase2a.vvp" "$run_id"
    rg -q \
        '^BUS_RESULT port0=28 port1=1 accepted=29 ssg_updates=17 timeout=0 write_while_busy=0 busy_min=190 busy_max=192 busy_hash=077f33fe691dd273$' \
        "$phase2a_tmp/phase2a-run-$run_id.log"
    rg -q \
        '^SAMPLE_RESULT cadence=144 width=6 ready_cycle=662 first_public_cycle=799 internal_pulses_at_first=6 tone_enable_cycle=9322 first_nonzero_index=0 public_samples=10342 cadence_errors=0 width_errors=0 drops=0 duplicates=0 mismatches=0$' \
        "$phase2a_tmp/phase2a-run-$run_id.log"
    rg -q \
        'target=0 failures=0.*primary_final_hash=54730095b12b6325 primary_raw_target_hash=a05a9500edbbca25 primary_psg_hash=3beb13acc8e83f25.*volume_mute_hash=28c31cf8df2ec325.*mixer_dc_hash=0f24568f5401b325 mixer_dc_raw_target_hash=be78bcdbd952dd25 mixer_dc_psg_hash=fbd6d46c9105fb25.*mixer_dc_nonzero=512 mixer_dc_peak=8160 mixer_dc_min=8160 mixer_dc_max=8160 mixer_dc_transitions=0.*changed_final_hash=ce0045fbf79de325 changed_raw_target_hash=198a0f033c98f725 changed_psg_hash=6524f6223fd9d325.*final_stop_hash=28c31cf8df2ec325.*x_count=0 clipping=0 drops=0 duplicates=0 fm_nonidle=0 adpcm_fetch=0' \
        "$phase2a_tmp/phase2a-run-$run_id.log"
    rg -q '^IDLE_RESULT .*noise_enable_events=0 .*fm_nonidle=0 adpcma_fetch=0 adpcmb_fetch=0 pcm_nonidle=0 adpcma_keyon=0 adpcmb_start=0$' \
        "$phase2a_tmp/phase2a-run-$run_id.log"
    rg -q "^SSG_TONE_PASS run=$run_id target=0$" \
        "$phase2a_tmp/phase2a-run-$run_id.log"
    normalize_fixture "$phase2a_tmp/phase2a-run-$run_id.log" \
        > "$phase2a_tmp/phase2a-run-$run_id.normalized"
done
diff -u "$phase2a_tmp/phase2a-run-1.normalized" \
    "$phase2a_tmp/phase2a-run-2.normalized"
diff -u "$phase2a_tmp/phase2a-run-1.normalized" \
    "$phase2a_tmp/phase2a-run-3.normalized"
echo "PHASE2A_HASH_AND_LANDMARK_REPEATABILITY runs=3 result=PASS"

echo "== individual four-state checks =="
isunknown_count="$(
    rg -o '\$isunknown' \
        "$repo_root/tb/jt10_cpu_bus_bfm.sv" \
        "$repo_root/tb/tb_jt10_phase2a_ssg_chA_tone.sv" |
        wc -l | tr -d ' '
)"
[[ "$isunknown_count" -ge 20 ]]
echo "INDIVIDUAL_ISUNKNOWN_CALLS $isunknown_count"
echo "ICARUS_4STATE_RESULT PASS"

echo "== Icarus SIMULATION comparison =="
set +e
(
    cd "$work_root"
    iverilog -g2012 -Wall -DSIMULATION \
        -s tb_jt10_phase2a_ssg_chA_tone \
        -o "$phase2a_tmp/phase2a-sim.vvp" \
        -f "$source_manifest" -f "$phase2a_manifest"
) > "$phase2a_tmp/iverilog-simulation.log" 2>&1
sim_rc=$?
set -e
if [[ "$sim_rc" -ne 0 ]]; then
    cat "$phase2a_tmp/iverilog-simulation.log"
    exit "$sim_rc"
fi
sim_warning_count="$(
    rg -c 'warning:' "$phase2a_tmp/iverilog-simulation.log" || true
)"
echo "ICARUS_SIM_WARNING_COUNT $sim_warning_count"
sed -n '/warning:/p' "$phase2a_tmp/iverilog-simulation.log"
run_fixture "phase2a-simulation" \
    "$phase2a_tmp/phase2a-sim.vvp" 1
ready_result "$phase2a_tmp/phase2a-run-1.log" \
    > "$phase2a_tmp/phase2a-nonsim-ready.txt"
ready_result "$phase2a_tmp/phase2a-simulation.log" \
    > "$phase2a_tmp/phase2a-sim-ready.txt"
diff -u "$phase2a_tmp/phase2a-nonsim-ready.txt" \
    "$phase2a_tmp/phase2a-sim-ready.txt"
echo "SIMULATION_READY_MATCH result=PASS"

echo "== Verilator lint/elaboration =="
set +e
(
    cd "$work_root"
    verilator --lint-only --timing -Wall -Wno-fatal \
        --top-module tb_jt10_phase2a_ssg_chA_tone \
        -f "$source_manifest" -f "$phase2a_manifest"
) > "$phase2a_tmp/verilator.log" 2>&1
verilator_rc=$?
set -e
verilator_warning_count="$(
    rg -c '^%Warning-' "$phase2a_tmp/verilator.log" || true
)"
echo "VERILATOR_RC $verilator_rc"
echo "VERILATOR_WARNING_COUNT $verilator_warning_count"
sed -n 's/^%Warning-\([^:]*\).*/\1/p' \
    "$phase2a_tmp/verilator.log" | sort | uniq -c | sort -k2
if [[ "$verilator_rc" -ne 0 ]]; then
    tail -100 "$phase2a_tmp/verilator.log"
    exit "$verilator_rc"
fi
echo "VERILATOR_ELABORATION PASS"

echo "== Phase 1C four-channel FM regression =="
bash "$repo_root/tb/run_jt10_phase1c.sh" \
    > "$phase2a_tmp/phase1c-regression.log" 2>&1
rg \
    '^(PHASE1A_REGRESSION|PHASE1B_REGRESSION|ENCODING2_HASH_AND_LANDMARK_REPEATABILITY|ENCODING6_HASH_AND_LANDMARK_REPEATABILITY|FOUR_CHANNEL_WAVEFORM_MATCH|SIMULATION_READY_MATCH encoding=|PHASE1C_REGRESSION)' \
    "$phase2a_tmp/phase1c-regression.log"
rg -q '^FOUR_CHANNEL_WAVEFORM_MATCH hash=8aadd7a6819038e5 alignment=0 polarity=same phase=same result=PASS$' \
    "$phase2a_tmp/phase1c-regression.log"
rg -q '^PHASE1C_REGRESSION PASS$' \
    "$phase2a_tmp/phase1c-regression.log"
echo "PHASE1C_FM_REGRESSION PASS"

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
    'standard_jt10|jt10_phase0_warmup_wrapper|jt10_phase1a|jt10_phase1b|jt10_phase1c|jt10_phase2a|jt10_cpu_bus_bfm|tb/jt10_pinned' \
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

artifact_digest > "$phase2a_tmp/repo-artifacts-after.sha256"
diff -u "$phase2a_tmp/repo-artifacts-before.sha256" \
    "$phase2a_tmp/repo-artifacts-after.sha256"
if git -C "$repo_root" ls-files --others --exclude-standard |
    rg -q '\.(vvp|vcd|fst|lxt|log|raw|wav)$'; then
    echo "FAIL unignored simulation artifact in repository"
    exit 1
fi
echo "REPOSITORY_SIM_ARTIFACTS new_or_changed=0"
echo "OPTIONAL_WAV generated=0"
echo "PHASE2A_REGRESSION PASS"
