#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
base_head="517f5c2af12527c71b63e819857b9f4221584dec"
phase2b_head="82290dc61912af144bbf5f0c291e9cbed4ee5ffd"
phase3a_head="0434e480836013c62aaf878fb6c25991249a443b"
phase2b_subject="Cover all JT10 SSG tone channels"
phase3a_subject="Add standalone JT10 ADPCM-A voice 0 bring-up"
phase3b_subject="Cover all JT10 ADPCM-A voices"
tmp_root="$(mktemp -d /private/tmp/jt10-phase2b.XXXXXX)"
trap 'rm -rf "$tmp_root"' EXIT

work_root="$tmp_root/work"
repeat_root="$tmp_root/repeat"
pinned_root="$repo_root/tb/jt10_pinned/6d51e0b6"
blob_manifest="$repo_root/tb/jt10_compat/pristine_blobs.tsv"
phase0_manifest="$repo_root/tb/jt10_phase0_sources.f"
phase2a_manifest="$repo_root/tb/jt10_phase2a_sources.f"
phase2b_manifest="$repo_root/tb/jt10_phase2b_sources.f"
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
        "$repo_root/tb/tb_jt10_phase2a_ssg_chA_tone.sv" \
        "$repo_root/tb/tb_jt10_phase2b_ssg_tones.sv" \
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
           -o -name '*.wav' \) -print |
        sort |
        while IFS= read -r file; do shasum -a 256 "$file"; done
}

summary_lines() {
    rg '^(BUS_RESULT|SAMPLE_RESULT|SSG_RESULT|IDLE_RESULT)' "$1"
}

normalized_summary() {
    summary_lines "$1" |
        sed -E 's/run=[0-9]+/run=N/; s/target=[0-2]/target=T/g'
}

check_fixture() {
    local log="$1"
    local run_id="$2"
    local target="$3"
    rg -q \
        '^BUS_RESULT port0=28 port1=1 accepted=29 ssg_updates=17 timeout=0 write_while_busy=0 busy_min=190 busy_max=192 busy_hash=077f33fe691dd273$' \
        "$log"
    rg -q \
        '^SAMPLE_RESULT cadence=144 width=6 ready_cycle=662 first_public_cycle=799 internal_pulses_at_first=6 tone_enable_cycle=9322 first_nonzero_index=0 public_samples=10342 cadence_errors=0 width_errors=0 drops=0 duplicates=0 mismatches=0$' \
        "$log"
    rg -q \
        "SSG_RESULT run=$run_id target=$target failures=0.*primary_final_hash=54730095b12b6325 primary_raw_target_hash=a05a9500edbbca25 primary_psg_hash=3beb13acc8e83f25.*peak=8160 min=0 max=8160 zero_transitions=576 dc_sum=16711680.*volume_mute_hash=28c31cf8df2ec325 volume_mute_settle=16.*mixer_dc_hash=0f24568f5401b325 mixer_dc_raw_target_hash=be78bcdbd952dd25 mixer_dc_psg_hash=fbd6d46c9105fb25.*mixer_dc_nonzero=512 mixer_dc_peak=8160 mixer_dc_min=8160 mixer_dc_max=8160 mixer_dc_transitions=0 mixer_dc_sum=4177920.*changed_final_hash=ce0045fbf79de325 changed_raw_target_hash=198a0f033c98f725 changed_psg_hash=6524f6223fd9d325.*changed_zero_transitions=1151 changed_dc_sum=16711680 final_stop_hash=28c31cf8df2ec325 final_stop_settle=16 x_count=0 clipping=0 drops=0 duplicates=0 fm_nonidle=0 adpcm_fetch=0 non_target_0_nonidle=0 non_target_1_nonidle=0 noise_enable_events=0 envelope_enable_events=0" \
        "$log"
    rg -q \
        "^IDLE_RESULT target=$target non_target_0_nonidle=0 non_target_1_nonidle=0 noise_enable_events=0 envelope_enable_events=0 fm_nonidle=0 adpcma_fetch=0 adpcmb_fetch=0 pcm_nonidle=0 adpcma_keyon=0 adpcmb_start=0$" \
        "$log"
    rg -q "^SSG_TONE_PASS run=$run_id target=$target$" "$log"
}

echo "== Phase 2B baseline =="
branch="$(git -C "$repo_root" branch --show-current)"
head_sha="$(git -C "$repo_root" rev-parse HEAD)"
[[ "$branch" == "ym2610-family-bringup" ]]
if [[ "${JT10_PHASE4AFIX_REGRESSION:-0}" != 1 &&
      "$head_sha" != "$base_head" ]]; then
    if [[ "$head_sha" == "$phase2b_head" ]]; then
        [[ "$(git -C "$repo_root" rev-parse HEAD^)" == "$base_head" ]]
        [[ "$(git -C "$repo_root" show -s --format=%s HEAD)" == \
            "$phase2b_subject" ]]
    elif [[ "$head_sha" == "$phase3a_head" ]]; then
        [[ "$(git -C "$repo_root" rev-parse HEAD^)" == \
            "$phase2b_head" ]]
        [[ "$(git -C "$repo_root" show -s --format=%s HEAD)" == \
            "$phase3a_subject" ]]
    else
        [[ "$(git -C "$repo_root" rev-parse HEAD^)" == \
            "$phase3a_head" ]]
        [[ "$(git -C "$repo_root" show -s --format=%s HEAD)" == \
            "$phase3b_subject" ]]
    fi
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

echo "== mapping and duplicate audit =="
rg -Fq '.period     ( {regarray[3][3:0], regarray[2][7:0] } )' \
    "$work_root/rtl/genesis_audio/jt49/jt49.v"
rg -Fq '.period     ( {regarray[5][3:0], regarray[4][7:0] } )' \
    "$work_root/rtl/genesis_audio/jt49/jt49.v"
rg -Fq 'Bmix <= (noise|use_noB) & (bitB|regarray[7][1]);' \
    "$work_root/rtl/genesis_audio/jt49/jt49.v"
rg -Fq 'Cmix <= (noise|use_noC) & (bitC|regarray[7][2]);' \
    "$work_root/rtl/genesis_audio/jt49/jt49.v"
while IFS= read -r source; do
    [[ -z "$source" || "$source" == \#* ]] && continue
    perl -ne 'print "$1\n" if /^\s*module\s+([A-Za-z_][A-Za-z0-9_]*)/' \
        "$work_root/$source"
done < <(cat "$phase0_manifest" "$phase2a_manifest" "$phase2b_manifest") |
    sort > "$tmp_root/modules.txt"
uniq -d "$tmp_root/modules.txt" > "$tmp_root/duplicates.txt"
[[ ! -s "$tmp_root/duplicates.txt" ]]
echo "CHANNEL_MAPPING B=02/03,09,bits1/4 C=04/05,0A,bits2/5 result=PASS"
echo "DUPLICATE_MODULES 0"

echo "== Icarus compile/elaboration =="
set +e
(
    cd "$work_root"
    iverilog -g2012 -Wall -s tb_jt10_standalone_elaboration \
        -o "$tmp_root/standalone.vvp" -f "$phase0_manifest"
    iverilog -g2012 -Wall -s tb_jt10_phase2a_ssg_chA_tone \
        -o "$tmp_root/a.vvp" -f "$phase0_manifest" -f "$phase2a_manifest"
    iverilog -g2012 -Wall -s tb_jt10_phase2b_ssg_chB_tone \
        -o "$tmp_root/b.vvp" -f "$phase0_manifest" -f "$phase2a_manifest" -f "$phase2b_manifest"
    iverilog -g2012 -Wall -s tb_jt10_phase2b_ssg_chC_tone \
        -o "$tmp_root/c.vvp" -f "$phase0_manifest" -f "$phase2a_manifest" -f "$phase2b_manifest"
) > "$tmp_root/iverilog.log" 2>&1
compile_rc=$?
set -e
[[ "$compile_rc" -eq 0 ]] || { cat "$tmp_root/iverilog.log"; exit "$compile_rc"; }
echo "ICARUS_NON_SIM_WARNING_COUNT $(rg -c 'warning:' "$tmp_root/iverilog.log" || true)"
echo "ICARUS_NON_SIM_ELABORATION PASS"
echo "UNDEFINED_MODULES 0"
(cd "$work_root"; vvp "$tmp_root/standalone.vvp") > "$tmp_root/standalone.log"
rg -q '^PASS tb_jt10_standalone_elaboration$' "$tmp_root/standalone.log"

echo "== A regression and B/C three-run determinism =="
(cd "$work_root"; vvp "$tmp_root/a.vvp" +RUN_ID=1) > "$tmp_root/a-1.log" &
pid_a=$!
for run in 1 2 3; do
    (cd "$work_root"; vvp "$tmp_root/b.vvp" +RUN_ID="$run") \
        > "$tmp_root/b-$run.log" &
    eval "pid_b_$run=$!"
    (cd "$work_root"; vvp "$tmp_root/c.vvp" +RUN_ID="$run") \
        > "$tmp_root/c-$run.log" &
    eval "pid_c_$run=$!"
done
wait "$pid_a"
for run in 1 2 3; do
    eval "wait \$pid_b_$run"
    eval "wait \$pid_c_$run"
done
check_fixture "$tmp_root/a-1.log" 1 0
for run in 1 2 3; do
    check_fixture "$tmp_root/b-$run.log" "$run" 1
    check_fixture "$tmp_root/c-$run.log" "$run" 2
    normalized_summary "$tmp_root/b-$run.log" > "$tmp_root/b-$run.norm"
    normalized_summary "$tmp_root/c-$run.log" > "$tmp_root/c-$run.norm"
done
diff -u "$tmp_root/b-1.norm" "$tmp_root/b-2.norm"
diff -u "$tmp_root/b-1.norm" "$tmp_root/b-3.norm"
diff -u "$tmp_root/c-1.norm" "$tmp_root/c-2.norm"
diff -u "$tmp_root/c-1.norm" "$tmp_root/c-3.norm"
normalized_summary "$tmp_root/a-1.log" > "$tmp_root/a.norm"
diff -u "$tmp_root/a.norm" "$tmp_root/b-1.norm"
diff -u "$tmp_root/a.norm" "$tmp_root/c-1.norm"
echo "PHASE2A_CHANNEL_A_REGRESSION PASS"
echo "CHANNEL_B_DETERMINISM runs=3 result=PASS"
echo "CHANNEL_C_DETERMINISM runs=3 result=PASS"
echo "THREE_CHANNEL_WAVEFORM_MATCH alignment=0 polarity=same phase=same result=PASS"

echo "== SIMULATION three-channel comparison =="
set +e
sim_compile_rc=0
for target in a b c; do
    case "$target" in
        a) top=tb_jt10_phase2a_ssg_chA_tone ;;
        b) top=tb_jt10_phase2b_ssg_chB_tone ;;
        c) top=tb_jt10_phase2b_ssg_chC_tone ;;
    esac
    (
        cd "$work_root"
        iverilog -g2012 -Wall -DSIMULATION -s "$top" \
            -o "$tmp_root/$target-sim.vvp" \
            -f "$phase0_manifest" -f "$phase2a_manifest" \
            -f "$phase2b_manifest"
    ) >> "$tmp_root/iverilog-sim.log" 2>&1 ||
        sim_compile_rc=$((sim_compile_rc | $?))
done
set -e
[[ "$sim_compile_rc" -eq 0 ]] || { cat "$tmp_root/iverilog-sim.log"; exit "$sim_compile_rc"; }
echo "ICARUS_SIM_WARNING_COUNT $(rg -c 'warning:' "$tmp_root/iverilog-sim.log" || true)"
for target in a b c; do
    (cd "$work_root"; vvp "$tmp_root/$target-sim.vvp" +RUN_ID=1) \
        > "$tmp_root/$target-sim.log" &
    eval "pid_sim_$target=$!"
done
wait "$pid_sim_a"
wait "$pid_sim_b"
wait "$pid_sim_c"
for target in a b c; do
    case "$target" in a) channel=0 ;; b) channel=1 ;; c) channel=2 ;; esac
    case "$target" in
        a) nonsim_norm="$tmp_root/a.norm" ;;
        b) nonsim_norm="$tmp_root/b-1.norm" ;;
        c) nonsim_norm="$tmp_root/c-1.norm" ;;
    esac
    check_fixture "$tmp_root/$target-sim.log" 1 "$channel"
    normalized_summary "$tmp_root/$target-sim.log" \
        > "$tmp_root/$target-sim.norm"
    diff -u "$nonsim_norm" "$tmp_root/$target-sim.norm"
done
echo "SIMULATION_READY_MATCH channels=A,B,C result=PASS"

echo "== Verilator lint/elaboration =="
set +e
(
    cd "$work_root"
    verilator --lint-only --timing -Wall -Wno-fatal \
        --top-module tb_jt10_phase2b_ssg_chB_tone \
        -f "$phase0_manifest" -f "$phase2a_manifest" -f "$phase2b_manifest"
    rc_b=$?
    verilator --lint-only --timing -Wall -Wno-fatal \
        --top-module tb_jt10_phase2b_ssg_chC_tone \
        -f "$phase0_manifest" -f "$phase2a_manifest" -f "$phase2b_manifest"
    rc_c=$?
    exit $((rc_b | rc_c))
) > "$tmp_root/verilator.log" 2>&1
verilator_rc=$?
set -e
echo "VERILATOR_RC $verilator_rc"
echo "VERILATOR_WARNING_COUNT $(rg -c '^%Warning-' "$tmp_root/verilator.log" || true)"
sed -n 's/^%Warning-\([^:]*\).*/\1/p' "$tmp_root/verilator.log" |
    sort | uniq -c | sort -k2
[[ "$verilator_rc" -eq 0 ]]
echo "VERILATOR_ELABORATION PASS"

echo "== Phase 1C FM regression =="
bash "$repo_root/tb/run_jt10_phase1c.sh" \
    > "$tmp_root/phase1c.log" 2>&1
rg -q '^FOUR_CHANNEL_WAVEFORM_MATCH hash=8aadd7a6819038e5 alignment=0 polarity=same phase=same result=PASS$' \
    "$tmp_root/phase1c.log"
rg -q '^PHASE1C_REGRESSION PASS$' "$tmp_root/phase1c.log"
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
    'standard_jt10|jt10_phase0_warmup_wrapper|jt10_phase1|jt10_phase2|jt10_cpu_bus_bfm|tb/jt10_pinned' \
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
echo "PHASE2B_REGRESSION PASS"
