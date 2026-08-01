#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
base_head="82290dc61912af144bbf5f0c291e9cbed4ee5ffd"
phase3a_head="0434e480836013c62aaf878fb6c25991249a443b"
phase3a_subject="Add standalone JT10 ADPCM-A voice 0 bring-up"
phase3b_subject="Cover all JT10 ADPCM-A voices"
tmp_root="$(mktemp -d /private/tmp/jt10-phase3a.XXXXXX)"
trap 'rm -rf "$tmp_root"' EXIT

work_root="$tmp_root/work"
repeat_root="$tmp_root/repeat"
pinned_root="$repo_root/tb/jt10_pinned/6d51e0b6"
blob_manifest="$repo_root/tb/jt10_compat/pristine_blobs.tsv"
phase0_manifest="$repo_root/tb/jt10_phase0_sources.f"
phase3a_manifest="$repo_root/tb/jt10_phase3a_sources.f"
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
        '^(BUS_RESULT|SAMPLE_RESULT|ADPCMA_LANDMARKS|ADPCMA_PRIMARY|ADPCMA_CONTROLS|ADPCMA_STOP|ISOLATION_RESULT|ADPCMA_RESULT|ADPCMA_ALIGNMENT|ADPCMA_VOICE0_PASS)' \
        "$1"
}

normalized_summary() {
    summary_lines "$1" | sed -E 's/run=[0-9]+/run=N/g'
}

check_fixture() {
    local log="$1"
    local run_id="$2"
    rg -q \
        '^BUS_RESULT port0=17 port1=39 accepted=56 adpcma_register_writes=39 adpcma_command_updates=19 timeout=0 write_while_busy=0 busy_min=190 busy_max=192 busy_hash=80297fb16a1adc9b$' \
        "$log"
    rg -q \
        '^SAMPLE_RESULT cadence=144 width=6 ready_cycle=662 first_public_cycle=799 internal_pulses_at_first=6 public_samples=28521 cadence_errors=0 width_errors=0 drops=0 duplicates=0 mismatches=0$' \
        "$log"
    rg -q \
        '^ADPCMA_LANDMARKS keyon_issue_cycle=13190 active_cycle=13267 first_fetch_cycle=13483 first_capture_cycle=13483 first_decode_cycle=13483 first_lane_cycle=15055 first_final_cycle=15343 first_nonzero_index=14 first_address=00000000 first_bank=00000000$' \
        "$log"
    rg -q \
        '^ADPCMA_PRIMARY fetch_count=1365 unique_addresses=683 fetch_hash=0395a9d360fa7ca4 address_hash=ee97dacc6be4aac1 rom_hash=8a7e8727bcc15bea decode_hash=f04661980311a408 attack_hash=36784cc91dfa2989 audio_hash=adf8cc2f2f81c1b9 left_hash=06b83a22ddc44a2c right_hash=06b83a22ddc44a2c nonzero=4075 peak=5172 min=-5172 max=5166 zero_crossings=775 dc_l=407970 dc_r=407970$' \
        "$log"
    rg -q \
        '^ADPCMA_CONTROLS left_audio=e02cc3dd3283d8dc left_l=06b83a22ddc44a2c left_r=b9d103fd6854a325 right_audio=3e94dce690020fd4 right_l=b9d103fd6854a325 right_r=06b83a22ddc44a2c mute_audio=28c31cf8df2ec325 mute_fetch=fc2bcd4a6aee3812 mute_decode=4de486c5e9639dd8 shifted_first=00000100 shifted_fetch=1dfec186fce43463 shifted_address=50358c40044f639d shifted_rom=52f3358dd7d3cc9f shifted_decode=865963f1d82c6d9b shifted_audio=4410e3ada11cc1b1 changed_fetch=0395a9d360fa7ca4 changed_address=ee97dacc6be4aac1 changed_rom=c640dfb7311d8f5e changed_decode=27d9d84a7e400d87 changed_audio=375d69862aef9499$' \
        "$log"
    rg -q \
        '^ADPCMA_STOP keyoff_issue=3135398 keyoff_active_clear=3135475 keyoff_fetch_stop=3135115 keyoff_additional_fetches=0 keyoff_settle=30 keyoff_zero_hash=28c31cf8df2ec325 natural_active_clear=3434995 natural_fetch_stop=3434923 natural_fetch_count=512 natural_last_address=000000ff natural_settle=28 natural_playback_hash=c49846023a4d9f25 natural_zero_hash=28c31cf8df2ec325 retrigger_fetch=0395a9d360fa7ca4 retrigger_address=ee97dacc6be4aac1 retrigger_rom=8a7e8727bcc15bea retrigger_decode=f04661980311a408 retrigger_audio=adf8cc2f2f81c1b9$' \
        "$log"
    rg -q \
        '^ISOLATION_RESULT voice_other_keyon=0 voice_other_fetch=0 voice_other_decode_nonzero=0 adpcmb_fetch=0 adpcmb_nonidle=0 fm_nonidle=0 ssg_nonidle=0 noise_enable=0 envelope_enable=0 x_count=0 clipping=0$' \
        "$log"
    rg -q "^ADPCMA_RESULT run=$run_id failures=0 .*x_count=0 clipping=0 drops=0 duplicates=0$" \
        "$log"
    rg -q "^ADPCMA_VOICE0_PASS run=$run_id$" "$log"
}

echo "== Phase 3A baseline =="
branch="$(git -C "$repo_root" branch --show-current)"
head_sha="$(git -C "$repo_root" rev-parse HEAD)"
[[ "$branch" == "ym2610-family-bringup" ]]
if [[ "${JT10_PHASE4AFIX_REGRESSION:-0}" != 1 &&
      "$head_sha" != "$base_head" ]]; then
    if [[ "$head_sha" == "$phase3a_head" ]]; then
        [[ "$(git -C "$repo_root" rev-parse HEAD^)" == "$base_head" ]]
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

python3 -c 'import hashlib; p=bytes((((i&255)*73+((i>>8)&15)*29+41)&255) for i in range(4096)); c=bytes((((i&255)*151+((i>>8)&15)*67+109)&255) for i in range(4096)); assert hashlib.sha256(p).hexdigest()=="2972dcd165c94f9ddfd9371d8999beab00e7b08b0b10ac0644454fa6071ad0da"; assert hashlib.sha256(c).hexdigest()=="de9b607745cfdf9c4d2a2983b3d244ce502ac5d50228228510b8be1dbf6ca5fd"'
echo "ROM_PATTERNS bytes=4096 period=4096 primary_sha256=2972dcd165c94f9ddfd9371d8999beab00e7b08b0b10ac0644454fa6071ad0da changed_sha256=de9b607745cfdf9c4d2a2983b3d244ce502ac5d50228228510b8be1dbf6ca5fd result=PASS"

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

echo "== pinned source contract and module audit =="
rg -Fq 'if(part && selected_register[7:6]==2'\''b0)' \
    "$work_root/rtl/genesis_audio/jt12/jt12_mmr.v"
rg -Fq 'assign addr_out = addr1[20:1];' \
    "$work_root/rtl/genesis_audio/jt12/standard_jt10/adpcm/jt10_adpcm_cnt.v"
rg -Fq 'assign sel      = addr1[0];' \
    "$work_root/rtl/genesis_audio/jt12/standard_jt10/adpcm/jt10_adpcm_cnt.v"
rg -Fq 'done5  <= addr4[20:9] == end4 && addr4[8:0]==~9'\''b0' \
    "$work_root/rtl/genesis_audio/jt12/standard_jt10/adpcm/jt10_adpcm_cnt.v"
rg -Fq 'data <= !nibble_sel ? datain[7:4] : datain[3:0];' \
    "$work_root/rtl/genesis_audio/jt12/standard_jt10/adpcm/jt10_adpcm_drvA.v"
while IFS= read -r source; do
    [[ -z "$source" || "$source" == \#* ]] && continue
    perl -ne 'print "$1\n" if /^\s*module\s+([A-Za-z_][A-Za-z0-9_]*)/' \
        "$work_root/$source"
done < <(cat "$phase0_manifest" "$phase3a_manifest") |
    sort > "$tmp_root/modules.txt"
uniq -d "$tmp_root/modules.txt" > "$tmp_root/duplicates.txt"
[[ ! -s "$tmp_root/duplicates.txt" ]]
echo "REGISTER_FETCH_NIBBLE_CONTRACT result=PASS"
echo "DUPLICATE_MODULES 0"

echo "== Icarus non-SIMULATION compile/elaboration =="
set +e
(
    cd "$work_root"
    iverilog -g2012 -Wall -s tb_jt10_phase3a_adpcma_voice0 \
        -o "$tmp_root/phase3a.vvp" \
        -f "$phase0_manifest" -f "$phase3a_manifest"
) > "$tmp_root/iverilog.log" 2>&1
compile_rc=$?
set -e
[[ "$compile_rc" -eq 0 ]] || { cat "$tmp_root/iverilog.log"; exit "$compile_rc"; }
echo "ICARUS_NON_SIM_WARNING_COUNT $(rg -c 'warning:|sorry:' "$tmp_root/iverilog.log" || true)"
echo "ICARUS_NON_SIM_ELABORATION PASS"
echo "UNDEFINED_MODULES 0"

echo "== primary three-run determinism and controls =="
for run in 1 2 3; do
    (cd "$work_root"; vvp "$tmp_root/phase3a.vvp" +RUN_ID="$run") \
        > "$tmp_root/run-$run.log" 2>&1 &
    eval "pid_run_$run=$!"
done
for run in 1 2 3; do
    eval "wait \$pid_run_$run"
    check_fixture "$tmp_root/run-$run.log" "$run"
    normalized_summary "$tmp_root/run-$run.log" \
        > "$tmp_root/run-$run.norm"
done
diff -u "$tmp_root/run-1.norm" "$tmp_root/run-2.norm"
diff -u "$tmp_root/run-1.norm" "$tmp_root/run-3.norm"
summary_lines "$tmp_root/run-1.log"
echo "ADPCMA_DETERMINISM runs=3 result=PASS"

echo "== Icarus SIMULATION comparison =="
set +e
(
    cd "$work_root"
    iverilog -g2012 -Wall -DSIMULATION \
        -s tb_jt10_phase3a_adpcma_voice0 \
        -o "$tmp_root/phase3a-sim.vvp" \
        -f "$phase0_manifest" -f "$phase3a_manifest"
) > "$tmp_root/iverilog-sim.log" 2>&1
sim_compile_rc=$?
set -e
[[ "$sim_compile_rc" -eq 0 ]] || {
    cat "$tmp_root/iverilog-sim.log"
    exit "$sim_compile_rc"
}
echo "ICARUS_SIM_WARNING_COUNT $(rg -c 'warning:|sorry:' "$tmp_root/iverilog-sim.log" || true)"
(cd "$work_root"; vvp "$tmp_root/phase3a-sim.vvp" +RUN_ID=1) \
    > "$tmp_root/sim.log" 2>&1
check_fixture "$tmp_root/sim.log" 1
normalized_summary "$tmp_root/sim.log" > "$tmp_root/sim.norm"
diff -u "$tmp_root/run-1.norm" "$tmp_root/sim.norm"
echo "SIMULATION_READY_MATCH result=PASS"

echo "== Verilator lint/elaboration =="
set +e
(
    cd "$work_root"
    verilator --lint-only --timing -Wall -Wno-fatal \
        --top-module tb_jt10_phase3a_adpcma_voice0 \
        -f "$phase0_manifest" -f "$phase3a_manifest"
) > "$tmp_root/verilator.log" 2>&1
verilator_rc=$?
set -e
echo "VERILATOR_RC $verilator_rc"
echo "VERILATOR_WARNING_COUNT $(rg -c '^%Warning-' "$tmp_root/verilator.log" || true)"
sed -n 's/^%Warning-\([^:]*\).*/\1/p' "$tmp_root/verilator.log" |
    sort | uniq -c | sort -k2
[[ "$verilator_rc" -eq 0 ]]
echo "VERILATOR_ELABORATION PASS"

echo "== Phase 1C and Phase 2B regression =="
bash "$repo_root/tb/run_jt10_phase2b.sh" \
    > "$tmp_root/phase2b.log" 2>&1
rg -q '^PHASE1C_FM_REGRESSION PASS$' "$tmp_root/phase2b.log"
rg -q '^PHASE2B_REGRESSION PASS$' "$tmp_root/phase2b.log"
echo "PHASE1C_FM_REGRESSION PASS"
echo "PHASE2B_SSG_REGRESSION PASS"

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
echo "PHASE3A_REGRESSION PASS"
