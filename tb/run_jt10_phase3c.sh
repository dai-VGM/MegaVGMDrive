#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
base_head="9c71fa03d9c19c41f226458b046142f153e6ad54"
phase3c_subject="Validate simultaneous JT10 ADPCM-A voices"
tmp_root="$(mktemp -d /private/tmp/jt10-phase3c.XXXXXX)"
trap 'rm -rf "$tmp_root"' EXIT

work_root="$tmp_root/work"
repeat_root="$tmp_root/repeat"
pinned_root="$repo_root/tb/jt10_pinned/6d51e0b6"
blob_manifest="$repo_root/tb/jt10_compat/pristine_blobs.tsv"
phase0_manifest="$repo_root/tb/jt10_phase0_sources.f"
phase3c_manifest="$repo_root/tb/jt10_phase3c_sources.f"
sacred_tb="$repo_root/tb/tb_jt49_audio_compare.sv"
phase3cr_files=(
    tb/tb_jt10_phase3cr_clear_boundary_audit.sv
    tb/run_jt10_phase3cr.sh
    tb/jt10_phase3cr_sources.f
    tb/jt10_phase3cr_fixture.md
)
top="tb_jt10_phase3c_adpcma_multivoice"

copy_sources() {
    local dst="$1"
    mkdir -p \
        "$dst/rtl/genesis_audio/jt12/standard_jt10/adpcm" \
        "$dst/rtl/genesis_audio/jt12/adpcm" \
        "$dst/rtl/genesis_audio/jt12/mixer" \
        "$dst/rtl/genesis_audio/jt49" "$dst/tb"
    cp "$pinned_root"/*.v \
        "$dst/rtl/genesis_audio/jt12/standard_jt10/"
    cp "$pinned_root/adpcm"/*.v \
        "$dst/rtl/genesis_audio/jt12/standard_jt10/adpcm/"
    cp "$repo_root/rtl/genesis_audio/jt12"/*.v \
        "$dst/rtl/genesis_audio/jt12/"
    cp "$repo_root/rtl/genesis_audio/jt12/adpcm/jt10_adpcm_div.v" \
        "$dst/rtl/genesis_audio/jt12/adpcm/"
    cp "$repo_root/rtl/genesis_audio/jt12/mixer"/*.v \
        "$dst/rtl/genesis_audio/jt12/mixer/"
    cp "$repo_root/rtl/genesis_audio/jt49"/*.v \
        "$dst/rtl/genesis_audio/jt49/"
    cp "$repo_root/tb/tb_jt10_standalone_elaboration.sv" \
        "$repo_root/tb/jt10_phase0_warmup_wrapper.sv" \
        "$repo_root/tb/jt10_cpu_bus_bfm.sv" \
        "$repo_root/tb/jt10_phase3a_adpcma_rom.sv" \
        "$repo_root/tb/jt10_phase3c_arithmetic_reference.sv" \
        "$repo_root/tb/tb_jt10_phase3c_adpcma_multivoice.sv" \
        "$dst/tb/"
}

apply_compatibility() {
    local src="$1"
    python3 "$repo_root/tb/jt10_compat/apply_icarus_syntax_compat.py" \
        "$src"
    python3 "$repo_root/tb/jt10_compat/apply_local_interface_compat.py" \
        "$src"
    python3 \
        "$repo_root/tb/jt10_compat/apply_jt10_counter_reset_compat.py" \
        "$src"
}

tree_digest() {
    local src="$1"
    (
        cd "$src"
        while IFS= read -r file; do
            shasum -a 256 "$file"
        done < <(find . -type f | sort)
    )
}

artifact_digest() {
    find "$repo_root" -type f \
        \( -name '*.vvp' -o -name '*.vcd' -o -name '*.fst' \
           -o -name '*.lxt' -o -name '*.log' -o -name '*.raw' \
           -o -name '*.wav' -o -name '*.dec' \) -print |
        sort |
        while IFS= read -r file; do shasum -a 256 "$file"; done
}

summary_lines() {
    rg '^(PHASE3C_(TRANSPORT|SAMPLE|VOICE|MIX|EVENTS|ARITH|OWNERSHIP|CLASS|COMMANDS|IDLE|SCENARIO|PASS))' "$1"
}

normalized_summary() {
    summary_lines "$1" | sed -E 's/run=[0-9]+/run=N/g'
}

check_scenario() {
    local log="$1"
    local scenario="$2"
    local run="$3"
    ! rg -q '^FAIL|FATAL:' "$log"
    rg -q "^PHASE3C_TRANSPORT scenario=$scenario run=$run .* timeout=0 busy_write=0$" "$log"
    rg -q "^PHASE3C_SAMPLE scenario=$scenario run=$run .* cadence_errors=0 width_errors=0 drops=0 duplicates=0 x=0$" "$log"
    rg -q "^PHASE3C_ARITH scenario=$scenario run=$run compare=[1-9][0-9]* mismatch=0 " "$log"
    rg -q "^PHASE3C_EVENTS scenario=$scenario run=$run raw=[1-9][0-9]* dummy=[0-9]+ logical=[1-9][0-9]* .*" "$log"
    rg -q "^PHASE3C_OWNERSHIP scenario=$scenario run=$run .*owner_unknown=0 owner_inactive=0 duplicate_cycle=0 capture_mismatch=0 ownership_mismatch=0 range=0 progression=0 .*starvation=0 .*pan_leak=0 raw_owner_unknown=0 capture_owner_mismatch=0 logical_owner_unknown=0 decoder_owner_mismatch=0 cursor_cross=0 rom_contamination=0 contribution_owner_mismatch=0$" "$log"
    rg -q "^PHASE3C_CLASS scenario=$scenario run=$run class=C .*state_commit_clr=0 logical_cursor_clr=0 .*logical_contribution_clr=0 dummy_audible=0 violations=0 state_tag_mismatch=0 contribution_tag_mismatch=0 tag_age_errors=0$" "$log"
    ! rg -q '^PHASE3C_VOICE .* repeated=[1-9][0-9]*|^PHASE3C_VOICE .* range=[1-9][0-9]*|^PHASE3C_VOICE .* owner_mismatch=[1-9][0-9]*|^PHASE3C_VOICE .* cross_owner=[1-9][0-9]*|^PHASE3C_VOICE .* dummy_audible=[1-9][0-9]*' "$log"
    rg -q "^PHASE3C_IDLE scenario=$scenario run=$run adpcmb_fetch=0 adpcmb_nonidle=0 fm_nonidle=0 ssg_nonidle=0 noise_enable=0 envelope_enable=0$" "$log"
    rg -q "^PHASE3C_SCENARIO scenario=$scenario run=$run failures=0 .* result=PASS$" "$log"
    rg -q "^PHASE3C_PASS scenario=$scenario run=$run$" "$log"
    if [[ "$scenario" == A ]]; then
        rg -q '^PHASE3C_COMMANDS scenario=A .*seen_03=1 seen_07=1 seen_0f=1 seen_3f=1 seen_81=1 seen_82=1 seen_84=1 seen_88=1 seen_90=1 seen_a0=1 seen_bf=1 seen_reserved=1 missed=0 duplicate=0 mask_errors=0 active_errors=0$' "$log"
    fi
    if [[ "$scenario" == G ]]; then
        rg -q '^PHASE3C_ARITH scenario=G .*aggregate_saturation=0 aggregate_wrap=0 .*final_saturation=0 final_wrap=0$' "$log"
        rg -q '^PHASE3C_OWNERSHIP scenario=G .*missed_slot=0 duplicate_slot=0 starvation=0 ' "$log"
    fi
}

echo "== Phase 3C baseline =="
branch="$(git -C "$repo_root" branch --show-current)"
head_sha="$(git -C "$repo_root" rev-parse HEAD)"
[[ "$branch" == "ym2610-family-bringup" ]]
if [[ "${JT10_PHASE4AFIX_REGRESSION:-0}" != 1 &&
      "$head_sha" != "$base_head" ]]; then
    [[ "$(git -C "$repo_root" rev-parse HEAD^)" == "$base_head" ]]
    [[ "$(git -C "$repo_root" show -s --format=%s HEAD)" == \
        "$phase3c_subject" ]]
fi
echo "BASELINE branch=$branch head=$head_sha base=$base_head"
git -C "$repo_root" status --short --untracked-files=all
if [[ "${JT10_PHASE4AFIX_REGRESSION:-0}" != 1 ]]; then
    git -C "$repo_root" diff --quiet
    git -C "$repo_root" diff --cached --quiet
fi

sacred_sha_before="$(shasum -a 256 "$sacred_tb" | awk '{print $1}')"
sacred_stat_before="$(stat -f 'size=%z mtime=%m inode=%i' "$sacred_tb")"
[[ "$sacred_sha_before" == \
    35cbd96d057e9889815229f2c0e154614eea7956ae895afdb74f6ace2b65406c ]]
[[ "$sacred_stat_before" == 'size=4939 mtime=1784686524 inode=21984214' ]]
echo "SACRED_BEGIN sha256=$sacred_sha_before $sacred_stat_before"
for protected_file in "${phase3cr_files[@]}"; do
    shasum -a 256 "$repo_root/$protected_file"
    stat -f '%N size=%z mtime=%m inode=%i' "$repo_root/$protected_file"
done > "$tmp_root/phase3cr-before.txt"
rg -q '^6d5a9dbe541036c6cede174d89825727b5f9944323cd5ce9affebf19d30c16c2 ' "$tmp_root/phase3cr-before.txt"
rg -q '^3232c45a5d792836bd3500f0cbaabb638fb4dabffc7ebba42631911f77d6aa73 ' "$tmp_root/phase3cr-before.txt"
rg -q '^20aaa483f095cdd8893f8d8f42e9faca6a6c7e4d42d413bc7cba1fb551b532a3 ' "$tmp_root/phase3cr-before.txt"
rg -q '^69f6b34de80b613846b41b6b59e54d851cacd9e4f9fed83f0a4ce76e08e99cd5 ' "$tmp_root/phase3cr-before.txt"
rg -q 'tb_jt10_phase3cr_clear_boundary_audit.sv size=66122 mtime=1785510646 inode=23091111$' "$tmp_root/phase3cr-before.txt"
rg -q 'run_jt10_phase3cr.sh size=15188 mtime=1785511001 inode=23091838$' "$tmp_root/phase3cr-before.txt"
rg -q 'jt10_phase3cr_sources.f size=130 mtime=1785508919 inode=23091109$' "$tmp_root/phase3cr-before.txt"
rg -q 'jt10_phase3cr_fixture.md size=13869 mtime=1785511396 inode=23092116$' "$tmp_root/phase3cr-before.txt"
echo "PHASE3CR_DIAGNOSTICS_BEGIN files=4 result=MATCH"
artifact_digest > "$tmp_root/artifacts-before.sha256"

files_blob="$(git -C "$repo_root" hash-object "$repo_root/files.qip")"
qsf_blob="$(git -C "$repo_root" hash-object "$repo_root/VGM_MD_MiSTer.qsf")"
[[ "$files_blob" == "$(git -C "$repo_root" rev-parse "$base_head:files.qip")" ]]
[[ "$qsf_blob" == "$(git -C "$repo_root" rev-parse "$base_head:VGM_MD_MiSTer.qsf")" ]]
echo "BUILD_LIST_BLOBS files.qip=$files_blob qsf=$qsf_blob result=MATCH"

pinned_count=0
while IFS=$'\t' read -r relative expected_blob expected_sha; do
    [[ -z "$relative" || "$relative" == \#* ]] && continue
    file="$pinned_root/$relative"
    [[ "$(git -C "$repo_root" hash-object "$file")" == "$expected_blob" ]]
    [[ "$(shasum -a 256 "$file" | awk '{print $1}')" == "$expected_sha" ]]
    pinned_count=$((pinned_count + 1))
done < "$blob_manifest"
[[ "$pinned_count" -eq 15 ]]
jt49_tree="$(git -C "$repo_root" rev-parse "$base_head:rtl/genesis_audio/jt49")"
[[ "$jt49_tree" == "63a434df533450acc14170bc3d2e91fa13faf806" ]]
echo "PINNED_SOURCES jt10=$pinned_count jt49_tree=$jt49_tree result=MATCH"

[[ "$(shasum -a 256 "$repo_root/tb/jt10_compat/apply_icarus_syntax_compat.py" | awk '{print $1}')" == \
    546441b9f757cab983fe185f79d1fc33ed54f5e5a11f1532034d1f9fbebaee36 ]]
[[ "$(shasum -a 256 "$repo_root/tb/jt10_compat/apply_local_interface_compat.py" | awk '{print $1}')" == \
    51548fe271061795af63d9d8c9b029595e03498af5c88ad2c6f2249b7f30a223 ]]
[[ "$(shasum -a 256 "$repo_root/tb/jt10_compat/apply_jt10_counter_reset_compat.py" | awk '{print $1}')" == \
    a47126debb59719cef63f2e4787dd5bccb8b45b80b1ee5a7c205ea4aca4b5c29 ]]
[[ "$(shasum -a 256 "$repo_root/tb/jt10_phase0_warmup_wrapper.sv" | awk '{print $1}')" == \
    b5ec92841b2653b1e3615587aad4c1c06c9d4eb4de1334a32ce58fa7bb3e18f0 ]]
echo "COMPATIBILITY_FIXTURES result=MATCH"

copy_sources "$work_root"
copy_sources "$repeat_root"
apply_compatibility "$work_root"
apply_compatibility "$repeat_root"
if [[ -n "${JT10_OVERLAY_ROOT:-}" ]]; then
    "$repo_root/tb/jt10_phase4afix_apply_overlay.sh" \
        "$work_root" "$JT10_OVERLAY_ROOT"
    "$repo_root/tb/jt10_phase4afix_apply_overlay.sh" \
        "$repeat_root" "$JT10_OVERLAY_ROOT"
fi
tree_digest "$work_root" > "$tmp_root/work.sha256"
tree_digest "$repeat_root" > "$tmp_root/repeat.sha256"
diff -u "$tmp_root/work.sha256" "$tmp_root/repeat.sha256"
echo "GENERATOR_REPRODUCIBILITY PASS"

echo "== pinned source contracts =="
rg -Fq 'aon_sr  <= ~{6{aon_cmd_cpy[7]}} & aon_cmd_cpy[5:0];' \
    "$work_root/rtl/genesis_audio/jt12/standard_jt10/adpcm/jt10_adpcm_drvA.v"
rg -Fq 'aoff_sr <=  {6{aon_cmd_cpy[7]}} & aon_cmd_cpy[5:0];' \
    "$work_root/rtl/genesis_audio/jt12/standard_jt10/adpcm/jt10_adpcm_drvA.v"
rg -Fq 'wire overflow = |pcm_full[17:15] & ~&pcm_full[17:15];' \
    "$work_root/rtl/genesis_audio/jt12/standard_jt10/adpcm/jt10_adpcm_acc.v"
rg -Fq 'pcm3    <= match2 ? pcm2_mul[24:9] : pcm2;' \
    "$work_root/rtl/genesis_audio/jt12/standard_jt10/adpcm/jt10_adpcm_gain.v"
rg -Fq 'acc_input_l = (adpcmA_l <<< 2) + (adpcmA_l <<< 1);' \
    "$work_root/rtl/genesis_audio/jt12/standard_jt10/jt10_acc.v"
rg -Fq 'acc <= overflow ? (acc[wout-1] ? minus_inf : plus_inf) : next;' \
    "$work_root/rtl/genesis_audio/jt12/jt12_single_acc.v"
echo "SOURCE_ARITHMETIC_CONTRACT result=PASS"

while IFS= read -r source; do
    [[ -z "$source" || "$source" == \#* ]] && continue
    perl -ne 'print "$1\n" if /^\s*module\s+([A-Za-z_][A-Za-z0-9_]*)/' \
        "$work_root/$source"
done < <(cat "$phase0_manifest" "$phase3c_manifest") |
    sort > "$tmp_root/modules.txt"
uniq -d "$tmp_root/modules.txt" > "$tmp_root/duplicates.txt"
[[ ! -s "$tmp_root/duplicates.txt" ]]
echo "DUPLICATE_MODULES 0"

echo "== Icarus non-SIMULATION compile/elaboration =="
set +e
(
    cd "$work_root"
    iverilog -g2012 -Wall -s "$top" \
        -o "$tmp_root/phase3c.vvp" \
        -f "$phase0_manifest" -f "$phase3c_manifest"
) > "$tmp_root/iverilog.log" 2>&1
compile_rc=$?
set -e
if [[ "$compile_rc" -ne 0 ]]; then
    cat "$tmp_root/iverilog.log"
    exit "$compile_rc"
fi
echo "ICARUS_NON_SIM_WARNING_COUNT count=$(rg -c 'warning:|sorry:' "$tmp_root/iverilog.log" || true)"
sed -n '/warning:/p; /sorry:/p' "$tmp_root/iverilog.log" |
    sort | uniq -c
echo "ICARUS_NON_SIM_ELABORATION result=PASS"

scenarios=(A B C D E F G H I J K L)
if [[ "${PHASE3C_QUICK:-0}" == 1 ]]; then
    scenarios=(A)
fi
if [[ -n "${PHASE3C_SCENARIOS:-}" ]]; then
    read -r -a scenarios <<< "$PHASE3C_SCENARIOS"
fi

echo "== Phase 3C non-SIMULATION three-run =="
run_total=3
if [[ "${PHASE3C_QUICK:-0}" == 1 ]]; then
    run_total=1
fi
if [[ -n "${PHASE3C_RUNS:-}" ]]; then
    run_total="$PHASE3C_RUNS"
fi
scenario_number=0
for scenario in A B C D E F G H I J K L; do
    scenario_number=$((scenario_number + 1))
    if [[ ! " ${scenarios[*]} " =~ " $scenario " ]]; then
        continue
    fi
    for run in $(seq 1 "$run_total"); do
        if [[ "${PHASE3C_QUICK:-0}" == 1 ]]; then
            if [[ -n "${PHASE3C_COMMAND_PHASE:-}" ]]; then
                (cd "$work_root"; stdbuf -oL vvp "$tmp_root/phase3c.vvp" \
                    +SCENARIO="$scenario_number" +RUN_ID="$run" \
                    +QUICK=1 +COMMAND_PHASE="$PHASE3C_COMMAND_PHASE") \
                    > "$tmp_root/$scenario-run-$run.log" 2>&1 &
            else
                (cd "$work_root"; stdbuf -oL vvp "$tmp_root/phase3c.vvp" \
                    +SCENARIO="$scenario_number" +RUN_ID="$run" \
                    +QUICK=1) \
                    > "$tmp_root/$scenario-run-$run.log" 2>&1 &
            fi
        else
            if [[ -n "${PHASE3C_COMMAND_PHASE:-}" ]]; then
                (cd "$work_root"; stdbuf -oL vvp "$tmp_root/phase3c.vvp" \
                    +SCENARIO="$scenario_number" +RUN_ID="$run" \
                    +COMMAND_PHASE="$PHASE3C_COMMAND_PHASE") \
                    > "$tmp_root/$scenario-run-$run.log" 2>&1 &
            else
                (cd "$work_root"; stdbuf -oL vvp "$tmp_root/phase3c.vvp" \
                    +SCENARIO="$scenario_number" +RUN_ID="$run") \
                    > "$tmp_root/$scenario-run-$run.log" 2>&1 &
            fi
        fi
        eval "pid_run_$run=$!"
    done
    for run in $(seq 1 "$run_total"); do
        set +e
        eval "wait \$pid_run_$run"
        run_rc=$?
        set -e
        if [[ "$run_rc" -ne 0 ]]; then
            cat "$tmp_root/$scenario-run-$run.log"
            exit "$run_rc"
        fi
        check_scenario "$tmp_root/$scenario-run-$run.log" \
            "$scenario" "$run"
        normalized_summary "$tmp_root/$scenario-run-$run.log" \
            > "$tmp_root/$scenario-run-$run.norm"
    done
    if [[ "$run_total" -eq 3 ]]; then
        diff -u "$tmp_root/$scenario-run-1.norm" \
            "$tmp_root/$scenario-run-2.norm"
        diff -u "$tmp_root/$scenario-run-1.norm" \
            "$tmp_root/$scenario-run-3.norm"
    fi
    summary_lines "$tmp_root/$scenario-run-1.log"
    echo "PHASE3C_DETERMINISM scenario=$scenario runs=$run_total result=PASS"
done
echo "UNDEFINED_MODULES 0"

if [[ "${PHASE3C_QUICK:-0}" != 1 && \
      "${PHASE3C_CORE_ONLY:-0}" != 1 ]]; then
    echo "== Icarus SIMULATION comparison =="
    set +e
    (
        cd "$work_root"
        iverilog -g2012 -Wall -DSIMULATION -s "$top" \
            -o "$tmp_root/phase3c-sim.vvp" \
            -f "$phase0_manifest" -f "$phase3c_manifest"
    ) > "$tmp_root/iverilog-sim.log" 2>&1
    compile_rc=$?
    set -e
    if [[ "$compile_rc" -ne 0 ]]; then
        cat "$tmp_root/iverilog-sim.log"
        exit "$compile_rc"
    fi
    echo "ICARUS_SIM_WARNING_COUNT count=$(rg -c 'warning:|sorry:' "$tmp_root/iverilog-sim.log" || true)"
    scenario_number=0
    for scenario in A B C D E F G H I J K L; do
        scenario_number=$((scenario_number + 1))
        if [[ -n "${PHASE3C_COMMAND_PHASE:-}" ]]; then
            (cd "$work_root"; stdbuf -oL vvp "$tmp_root/phase3c-sim.vvp" \
                +SCENARIO="$scenario_number" +RUN_ID=1 \
                +COMMAND_PHASE="$PHASE3C_COMMAND_PHASE") \
                > "$tmp_root/$scenario-sim.log" 2>&1
        else
            (cd "$work_root"; stdbuf -oL vvp "$tmp_root/phase3c-sim.vvp" \
                +SCENARIO="$scenario_number" +RUN_ID=1) \
                > "$tmp_root/$scenario-sim.log" 2>&1
        fi
        check_scenario "$tmp_root/$scenario-sim.log" "$scenario" 1
        normalized_summary "$tmp_root/$scenario-sim.log" \
            > "$tmp_root/$scenario-sim.norm"
        diff -u "$tmp_root/$scenario-run-1.norm" \
            "$tmp_root/$scenario-sim.norm"
        echo "PHASE3C_SIMULATION_MATCH scenario=$scenario result=PASS"
    done

    echo "== Verilator lint/elaboration =="
    set +e
    (
        cd "$work_root"
        verilator --lint-only --timing -Wall -Wno-fatal \
            --top-module "$top" \
            -f "$phase0_manifest" -f "$phase3c_manifest"
    ) > "$tmp_root/verilator.log" 2>&1
    verilator_rc=$?
    set -e
    echo "VERILATOR_RC rc=$verilator_rc"
    echo "VERILATOR_WARNING_COUNT count=$(rg -c '^%Warning-' "$tmp_root/verilator.log" || true)"
    sed -n 's/^%Warning-\([^:]*\).*/\1/p' "$tmp_root/verilator.log" |
        sort | uniq -c | sort -k2
    [[ "$verilator_rc" -eq 0 ]]
    echo "VERILATOR_ELABORATION result=PASS"

    echo "== Phase 3B/3A/2B/1C complete regression =="
    bash "$repo_root/tb/run_jt10_phase3b.sh" \
        > "$tmp_root/phase3b.log" 2>&1
    rg -q '^PHASE3B_REGRESSION PASS$' "$tmp_root/phase3b.log"
    rg -q '^PHASE3A_VOICE0_REGRESSION PASS$' "$tmp_root/phase3b.log"
    rg -q '^PHASE2B_SSG_REGRESSION PASS$' "$tmp_root/phase3b.log"
    rg -q '^PHASE1C_FM_REGRESSION PASS$' "$tmp_root/phase3b.log"
    rg -q '^PHASE3B_PRIMARY voice=1 .*audio_hash=17e3063b8387e235 ' "$tmp_root/phase3b.log"
    rg -q '^PHASE3B_PRIMARY voice=2 .*audio_hash=a4240e15b4fa2d55 ' "$tmp_root/phase3b.log"
    rg -q '^PHASE3B_PRIMARY voice=3 .*audio_hash=a4240e15b4fa2d55 ' "$tmp_root/phase3b.log"
    rg -q '^PHASE3B_PRIMARY voice=4 .*audio_hash=baa7fbb9cf648ced ' "$tmp_root/phase3b.log"
    rg -q '^PHASE3B_PRIMARY voice=5 .*audio_hash=baa7fbb9cf648ced ' "$tmp_root/phase3b.log"
    [[ "$(rg -c 'aligned_hash=5b52746e5b1c3d75' "$tmp_root/phase3b.log")" -ge 10 ]]
    rg -q '^VOICE0_5_ALIGNED_WAVEFORM_MATCH samples=2048 hash=5b52746e5b1c3d75 polarity=same result=PASS$' "$tmp_root/phase3b.log"
    echo "PHASE3B_CANONICAL_HASHES result=PASS"
    rg '^VOICE0_5_ALIGNED_WAVEFORM_MATCH|^PHASE3B_REGRESSION PASS|^PHASE3A_VOICE0_REGRESSION PASS|^PHASE2B_SSG_REGRESSION PASS|^PHASE1C_FM_REGRESSION PASS' "$tmp_root/phase3b.log"
fi

echo "== production isolation =="
git -C "$repo_root" diff --check
git -C "$repo_root" diff --quiet "$base_head" -- \
    rtl/genesis_audio/jt12 rtl/genesis_audio/jt49 \
    rtl/vgm_loaded_player.sv rtl/mister_vgm_md_top.sv \
    rtl/vgm_ddram_backend.sv rtl/md_sound_module.sv \
    rtl/ym2203_sound_module.sv rtl/emu.sv sys/sys_top.v \
    rtl/genesis_audio/jtoutrun rtl/segapcm_sound_module.sv \
    rtl/audio_mixer.sv files.qip VGM_MD_MiSTer.qsf
git -C "$repo_root" diff --quiet "$base_head" -- \
    tb/jt10_pinned tb/jt10_compat \
    tb/jt10_phase0_warmup_wrapper.sv tb/jt10_cpu_bus_bfm.sv
echo "PRODUCTION_BLOBS MATCH"
if rg -n \
    'standard_jt10|jt10_phase0_warmup_wrapper|jt10_phase1|jt10_phase2|jt10_phase3|jt10_cpu_bus_bfm|tb/jt10_pinned|phase3c_arithmetic|phase3c_adpcma' \
    "$repo_root/files.qip" "$repo_root/VGM_MD_MiSTer.qsf"; then
    echo "FAIL standalone JT10 entered production build lists"
    exit 1
fi
echo "PRODUCTION_BUILD_JT10_REFERENCES 0"

sacred_sha_after="$(shasum -a 256 "$sacred_tb" | awk '{print $1}')"
sacred_stat_after="$(stat -f 'size=%z mtime=%m inode=%i' "$sacred_tb")"
[[ "$sacred_sha_before" == "$sacred_sha_after" ]]
[[ "$sacred_stat_before" == "$sacred_stat_after" ]]
echo "SACRED_END sha256=$sacred_sha_after $sacred_stat_after result=UNCHANGED"
for protected_file in "${phase3cr_files[@]}"; do
    shasum -a 256 "$repo_root/$protected_file"
    stat -f '%N size=%z mtime=%m inode=%i' "$repo_root/$protected_file"
done > "$tmp_root/phase3cr-after.txt"
diff -u "$tmp_root/phase3cr-before.txt" "$tmp_root/phase3cr-after.txt"
echo "PHASE3CR_DIAGNOSTICS_END files=4 result=UNCHANGED"
artifact_digest > "$tmp_root/artifacts-after.sha256"
diff -u "$tmp_root/artifacts-before.sha256" "$tmp_root/artifacts-after.sha256"
echo "REPOSITORY_SIM_ARTIFACTS new_or_changed=0"
echo "OPTIONAL_WAV generated=0"
if [[ "${PHASE3C_QUICK:-0}" == 1 ]]; then
    echo "PHASE3C_QUICK PASS"
elif [[ "${PHASE3C_CORE_ONLY:-0}" == 1 ]]; then
    echo "PHASE3C_CORE_ONLY PASS"
else
    echo "PHASE3C_REGRESSION PASS"
fi
