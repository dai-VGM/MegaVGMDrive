#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
base_head="0434e480836013c62aaf878fb6c25991249a443b"
phase3b_subject="Cover all JT10 ADPCM-A voices"
tmp_root="$(mktemp -d /private/tmp/jt10-phase3b.XXXXXX)"
trap 'rm -rf "$tmp_root"' EXIT

work_root="$tmp_root/work"
repeat_root="$tmp_root/repeat"
pinned_root="$repo_root/tb/jt10_pinned/6d51e0b6"
blob_manifest="$repo_root/tb/jt10_compat/pristine_blobs.tsv"
phase0_manifest="$repo_root/tb/jt10_phase0_sources.f"
phase3b_manifest="$repo_root/tb/jt10_phase3b_sources.f"
sacred_tb="$repo_root/tb/tb_jt49_audio_compare.sv"

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
        "$repo_root/tb/tb_jt10_phase3a_adpcma_voice0.sv" \
        "$repo_root/tb/tb_jt10_phase3b_adpcma_voices.sv" \
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
    rg \
        '^(MAPPING_SENTINEL|BUS_RESULT|SAMPLE_RESULT|ADPCMA_LANDMARKS|ADPCMA_PRIMARY|ADPCMA_CONTROLS|ADPCMA_STOP|ISOLATION_RESULT|ADPCMA_RESULT|ADPCMA_ALIGNMENT|PHASE3B_MAPPING|PHASE3B_SCHEDULER|PHASE3B_PRIMARY|PHASE3B_CONTROLS|PHASE3B_STOP|PHASE3B_ISOLATION|PHASE3B_RESULT|ADPCMA_VOICE_PASS)' \
        "$1"
}

normalized_summary() {
    summary_lines "$1" | sed -E 's/run=[0-9]+/run=N/g'
}

check_voice() {
    local log="$1"
    local voice="$2"
    local run_id="$3"
    local level_reg start_low start_high end_low end_high
    local keyon keyoff unique_first target_phase sentinel

    level_reg="$(printf '%02x' $((8 + voice)))"
    start_low="$(printf '%02x' $((16 + voice)))"
    start_high="$(printf '%02x' $((24 + voice)))"
    end_low="$(printf '%02x' $((32 + voice)))"
    end_high="$(printf '%02x' $((40 + voice)))"
    keyon="$(printf '%02x' $((1 << voice)))"
    keyoff="$(printf '%02x' $((128 | (1 << voice))))"
    unique_first="$(printf '%08x' $((voice * 256)))"
    target_phase=$((230 - ((voice - 1) * 60)))
    if ((target_phase < 0)); then
        target_phase=$((target_phase + 432))
    fi

    ! rg -q '^FAIL|FATAL:' "$log"
    rg -q \
        "^BUS_RESULT port0=17 port1=88 accepted=105 adpcma_register_writes=88 adpcma_command_updates=29 timeout=0 write_while_busy=0 busy_min=190 busy_max=192 busy_hash=d8a9137523a7206d$" \
        "$log"
    rg -q \
        '^SAMPLE_RESULT cadence=144 width=6 ready_cycle=662 first_public_cycle=799 .*cadence_errors=0 width_errors=0 drops=0 duplicates=0 mismatches=0$' \
        "$log"
    rg -q \
        "^PHASE3B_MAPPING voice=$voice level_reg=$level_reg start_low=$start_low start_high=$start_high end_low=$end_low end_high=$end_high keyon=$keyon keyoff=$keyoff scheduler_slot=$voice " \
        "$log"
    rg -q \
        "^PHASE3B_SCHEDULER voice=$voice period=432 target_issue_phase=$target_phase .*target_slot_delay=221 .*first_fetch_cycle=[0-9]+ first_decode_cycle=[0-9]+ first_lane_cycle=[0-9]+ first_final_cycle=[0-9]+$" \
        "$log"
    rg -q \
        "^PHASE3B_PRIMARY voice=$voice run=$run_id fetch_count=1365 unique_addresses=683 first_address=00000000 first_bank=00000000 fetch_hash=0395a9d360fa7ca4 address_hash=ee97dacc6be4aac1 rom_hash=8a7e8727bcc15bea decode_hash=f04661980311a408 .*aligned_samples=2048 .*nonzero=[1-9][0-9]* " \
        "$log"
    rg -q \
        "^PHASE3B_CONTROLS voice=$voice .*mute_audio=28c31cf8df2ec325 .*unique_first=$unique_first .*unique_address=[0-9a-f]{16} .*unique_audio=[0-9a-f]{16}$" \
        "$log"
    rg -q \
        "^PHASE3B_STOP voice=$voice .*keyoff_zero=28c31cf8df2ec325 .*natural_fetch_count=512 natural_last_address=000000ff .*natural_zero=28c31cf8df2ec325 .*retrigger_audio=[0-9a-f]{16}$" \
        "$log"
    rg -q \
        "^PHASE3B_ISOLATION voice=$voice other_active=0 other_keyon=0 other_fetch=0 other_decode=0 target_decode=[1-9][0-9]* target_accumulator_nonidle=[1-9][0-9]* command_mask_errors=0 adpcmb_fetch=0 adpcmb_nonidle=0 fm_nonidle=0 ssg_nonidle=0 noise_enable=0 envelope_enable=0 x_count=0 clipping=0 drops=0 duplicates=0$" \
        "$log"
    rg -q \
        "^PHASE3B_RESULT voice=$voice run=$run_id failures=0 accepted=105 port0=17 port1=88 busy_hash=d8a9137523a7206d ready_cycle=662 first_public_cycle=799 cadence_errors=0 width_errors=0 result=PASS$" \
        "$log"
    rg -q "^ADPCMA_VOICE_PASS voice=$voice run=$run_id$" "$log"

    for sentinel in 0 1 2 3 4 5; do
        rg -q \
            "^MAPPING_SENTINEL voice=$sentinel .*first_address=$(printf '%06x' $((sentinel * 4096))) .*result=PASS$" \
            "$log"
    done
}

echo "== Phase 3B baseline =="
branch="$(git -C "$repo_root" branch --show-current)"
head_sha="$(git -C "$repo_root" rev-parse HEAD)"
[[ "$branch" == "ym2610-family-bringup" ]]
if [[ "${JT10_PHASE4AFIX_REGRESSION:-0}" != 1 &&
      "$head_sha" != "$base_head" ]]; then
    [[ "$(git -C "$repo_root" rev-parse HEAD^)" == "$base_head" ]]
    [[ "$(git -C "$repo_root" show -s --format=%s HEAD)" == \
        "$phase3b_subject" ]]
fi
echo "BASELINE branch=$branch head=$head_sha base=$base_head"
git -C "$repo_root" status --short --untracked-files=all

sacred_sha_before="$(shasum -a 256 "$sacred_tb" | awk '{print $1}')"
sacred_stat_before="$(stat -f 'size=%z mtime=%m inode=%i' "$sacred_tb")"
echo "SACRED_BEGIN sha256=$sacred_sha_before $sacred_stat_before"
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

echo "== pinned mapping and scheduler contract =="
rg -Fq '6'\''h8, 6'\''h9, 6'\''hA, 6'\''hB, 6'\''hC, 6'\''hD' \
    "$work_root/rtl/genesis_audio/jt12/jt12_mmr.v"
rg -Fq '{up_end, up_start } <= selected_register[5:4];' \
    "$work_root/rtl/genesis_audio/jt12/jt12_mmr.v"
rg -Fq 'up_addr <= selected_register[2:0];' \
    "$work_root/rtl/genesis_audio/jt12/jt12_mmr.v"
rg -Fq 'aon_sr  <= ~{6{aon_cmd_cpy[7]}} & aon_cmd_cpy[5:0];' \
    "$work_root/rtl/genesis_audio/jt12/standard_jt10/adpcm/jt10_adpcm_drvA.v"
rg -Fq 'aoff_sr <=  {6{aon_cmd_cpy[7]}} & aon_cmd_cpy[5:0];' \
    "$work_root/rtl/genesis_audio/jt12/standard_jt10/adpcm/jt10_adpcm_drvA.v"
rg -Fq 'cur_ch <= cur_next;' \
    "$work_root/rtl/genesis_audio/jt12/standard_jt10/adpcm/jt10_adpcm_drvA.v"
rg -Fq 'if( cur_ch[5] ) en_ch <= en_next;' \
    "$work_root/rtl/genesis_audio/jt12/standard_jt10/adpcm/jt10_adpcm_drvA.v"
echo "REGISTER_KEY_SCHEDULER_CONTRACT result=PASS"

while IFS= read -r source; do
    [[ -z "$source" || "$source" == \#* ]] && continue
    perl -ne 'print "$1\n" if /^\s*module\s+([A-Za-z_][A-Za-z0-9_]*)/' \
        "$work_root/$source"
done < <(cat "$phase0_manifest" "$phase3b_manifest") |
    sort > "$tmp_root/modules.txt"
uniq -d "$tmp_root/modules.txt" > "$tmp_root/duplicates.txt"
[[ ! -s "$tmp_root/duplicates.txt" ]]
echo "DUPLICATE_MODULES 0"

echo "== Icarus non-SIMULATION voice 1-5 three-run =="
for voice in 1 2 3 4 5; do
    top="tb_jt10_phase3b_adpcma_voice$voice"
    set +e
    (
        cd "$work_root"
        iverilog -g2012 -Wall -s "$top" \
            -o "$tmp_root/voice-$voice.vvp" \
            -f "$phase0_manifest" -f "$phase3b_manifest"
    ) > "$tmp_root/iverilog-$voice.log" 2>&1
    compile_rc=$?
    set -e
    [[ "$compile_rc" -eq 0 ]] || {
        cat "$tmp_root/iverilog-$voice.log"
        exit "$compile_rc"
    }
    echo "ICARUS_NON_SIM_WARNING_COUNT voice=$voice count=$(rg -c 'warning:|sorry:' "$tmp_root/iverilog-$voice.log" || true)"
    echo "ICARUS_NON_SIM_ELABORATION voice=$voice result=PASS"

    for run in 1 2 3; do
        (cd "$work_root"; vvp "$tmp_root/voice-$voice.vvp" \
            +RUN_ID="$run") > "$tmp_root/voice-$voice-run-$run.log" 2>&1 &
        eval "pid_run_$run=$!"
    done
    for run in 1 2 3; do
        eval "wait \$pid_run_$run"
        check_voice "$tmp_root/voice-$voice-run-$run.log" \
            "$voice" "$run"
        normalized_summary "$tmp_root/voice-$voice-run-$run.log" \
            > "$tmp_root/voice-$voice-run-$run.norm"
    done
    diff -u "$tmp_root/voice-$voice-run-1.norm" \
        "$tmp_root/voice-$voice-run-2.norm"
    diff -u "$tmp_root/voice-$voice-run-1.norm" \
        "$tmp_root/voice-$voice-run-3.norm"
    summary_lines "$tmp_root/voice-$voice-run-1.log"
    echo "PHASE3B_DETERMINISM voice=$voice runs=3 result=PASS"
done
echo "UNDEFINED_MODULES 0"

echo "== six-voice waveform comparison =="
for voice in 1 2 3 4 5; do
    rg '^PHASE3B_PRIMARY ' "$tmp_root/voice-$voice-run-1.log"
    rg '^ADPCMA_ALIGNMENT ' "$tmp_root/voice-$voice-run-1.log"
done
aligned_unique="$(
    for voice in 1 2 3 4 5; do
        sed -n 's/^ADPCMA_ALIGNMENT .*aligned_hash=\([0-9a-f]*\).*/\1/p' \
            "$tmp_root/voice-$voice-run-1.log"
    done | sort -u | wc -l | tr -d ' '
)"
[[ "$aligned_unique" -eq 1 ]]
echo "VOICE1_5_ALIGNED_WAVEFORM_MATCH samples=2048 polarity=same result=PASS"

echo "== Icarus SIMULATION voice 1-5 comparison =="
for voice in 1 2 3 4 5; do
    top="tb_jt10_phase3b_adpcma_voice$voice"
    set +e
    (
        cd "$work_root"
        iverilog -g2012 -Wall -DSIMULATION -s "$top" \
            -o "$tmp_root/voice-$voice-sim.vvp" \
            -f "$phase0_manifest" -f "$phase3b_manifest"
    ) > "$tmp_root/iverilog-$voice-sim.log" 2>&1
    compile_rc=$?
    set -e
    [[ "$compile_rc" -eq 0 ]] || {
        cat "$tmp_root/iverilog-$voice-sim.log"
        exit "$compile_rc"
    }
    echo "ICARUS_SIM_WARNING_COUNT voice=$voice count=$(rg -c 'warning:|sorry:' "$tmp_root/iverilog-$voice-sim.log" || true)"
    (cd "$work_root"; vvp "$tmp_root/voice-$voice-sim.vvp" \
        +RUN_ID=1) > "$tmp_root/voice-$voice-sim.log" 2>&1
    check_voice "$tmp_root/voice-$voice-sim.log" "$voice" 1
    normalized_summary "$tmp_root/voice-$voice-sim.log" \
        > "$tmp_root/voice-$voice-sim.norm"
    diff -u "$tmp_root/voice-$voice-run-1.norm" \
        "$tmp_root/voice-$voice-sim.norm"
    echo "SIMULATION_READY_MATCH voice=$voice result=PASS"
done

echo "== Verilator lint/elaboration =="
for voice in 1 2 3 4 5; do
    top="tb_jt10_phase3b_adpcma_voice$voice"
    set +e
    (
        cd "$work_root"
        verilator --lint-only --timing -Wall -Wno-fatal \
            --top-module "$top" \
            -f "$phase0_manifest" -f "$phase3b_manifest"
    ) > "$tmp_root/verilator-$voice.log" 2>&1
    verilator_rc=$?
    set -e
    echo "VERILATOR_RC voice=$voice rc=$verilator_rc"
    echo "VERILATOR_WARNING_COUNT voice=$voice count=$(rg -c '^%Warning-' "$tmp_root/verilator-$voice.log" || true)"
    [[ "$verilator_rc" -eq 0 ]]
done
sed -n 's/^%Warning-\([^:]*\).*/\1/p' \
    "$tmp_root"/verilator-*.log |
    sort | uniq -c | sort -k2
echo "VERILATOR_ELABORATION voices=1,2,3,4,5 result=PASS"

echo "== Phase 3A, Phase 2B, and Phase 1C regression =="
bash "$repo_root/tb/run_jt10_phase3a.sh" \
    > "$tmp_root/phase3a.log" 2>&1
rg -q '^PHASE3A_REGRESSION PASS$' "$tmp_root/phase3a.log"
rg -q '^PHASE2B_SSG_REGRESSION PASS$' "$tmp_root/phase3a.log"
rg -q '^PHASE1C_FM_REGRESSION PASS$' "$tmp_root/phase3a.log"
rg '^ADPCMA_ALIGNMENT voice=0 ' "$tmp_root/phase3a.log"
voice0_aligned="$(
    sed -n 's/^ADPCMA_ALIGNMENT voice=0 .*aligned_hash=\([0-9a-f]*\).*/\1/p' \
        "$tmp_root/phase3a.log"
)"
voice1_aligned="$(
    sed -n 's/^ADPCMA_ALIGNMENT voice=1 .*aligned_hash=\([0-9a-f]*\).*/\1/p' \
        "$tmp_root/voice-1-run-1.log"
)"
[[ "$voice0_aligned" == "$voice1_aligned" ]]
echo "VOICE0_5_ALIGNED_WAVEFORM_MATCH samples=2048 hash=$voice0_aligned polarity=same result=PASS"
echo "PHASE3A_VOICE0_REGRESSION PASS"
echo "PHASE2B_SSG_REGRESSION PASS"
echo "PHASE1C_FM_REGRESSION PASS"

echo "== production isolation =="
git -C "$repo_root" diff --check
git -C "$repo_root" diff --quiet "$base_head" -- \
    rtl/genesis_audio/jt12 rtl/genesis_audio/jt49 \
    rtl/vgm_loaded_player.sv rtl/mister_vgm_md_top.sv \
    rtl/vgm_ddram_backend.sv rtl/md_sound_module.sv \
    rtl/ym2203_sound_module.sv rtl/emu.sv sys/sys_top.v \
    rtl/genesis_audio/jtoutrun rtl/segapcm_sound_module.sv \
    rtl/audio_mixer.sv files.qip VGM_MD_MiSTer.qsf
echo "PRODUCTION_BLOBS MATCH"
if rg -n \
    'standard_jt10|jt10_phase0_warmup_wrapper|jt10_phase1|jt10_phase2|jt10_phase3|jt10_cpu_bus_bfm|tb/jt10_pinned' \
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
artifact_digest > "$tmp_root/artifacts-after.sha256"
diff -u "$tmp_root/artifacts-before.sha256" "$tmp_root/artifacts-after.sha256"
echo "REPOSITORY_SIM_ARTIFACTS new_or_changed=0"
echo "OPTIONAL_WAV generated=0"
echo "PHASE3B_REGRESSION PASS"
