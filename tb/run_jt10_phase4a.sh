#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
base_head="7ae45b1b11a1fe8b43c6d214d56639a4c1bd71be"
final_subject="Add standalone JT10 ADPCM-B single-shot bring-up"
pinned_root="$repo_root/tb/jt10_pinned/6d51e0b6"
blob_manifest="$repo_root/tb/jt10_compat/pristine_blobs.tsv"
overlay_root="$repo_root/rtl/genesis_audio/jt10_ym2610/adpcm"
phase0_manifest="$repo_root/tb/jt10_phase0_sources.f"
phase4a_manifest="$repo_root/tb/jt10_phase4a_sources.f"
top="tb_jt10_phase4a_adpcmb_single_shot"

mkdir -p /tmp/jt10_phase4a_sources /tmp/jt10_phase4a_build \
    /tmp/jt10_phase4a_logs
source_root="$(mktemp -d /tmp/jt10_phase4a_sources/run.XXXXXX)"
build_root="$(mktemp -d /tmp/jt10_phase4a_build/run.XXXXXX)"
log_root="$(mktemp -d /tmp/jt10_phase4a_logs/run.XXXXXX)"

protected=(
    tb/tb_jt49_audio_compare.sv
    tb/tb_jt10_phase3cr_clear_boundary_audit.sv
    tb/run_jt10_phase3cr.sh
    tb/jt10_phase3cr_sources.f
    tb/jt10_phase3cr_fixture.md
    tb/tb_jt10_phase4ar_adpcmb_stop_contract.sv
    tb/run_jt10_phase4ar.sh
    tb/jt10_phase4ar_sources.f
    tb/jt10_phase4ar_fixture.md
    tb/tb_jt10_phase4ax_adpcmb_reset_coverage.sv
    tb/run_jt10_phase4ax.sh
    tb/generate_jt10_phase4ax_variants.py
    tb/jt10_phase4ax_sources.f
    tb/jt10_phase4ax_fixture.md
    tb/tb_jt10_phase4arv1_adpcmb_stop_contract.sv
    tb/run_jt10_phase4arv1.sh
    tb/jt10_phase4arv1_sources.f
    tb/jt10_phase4arv1_fixture.md
    tb/tb_jt10_phase4ap_adpcmb_patch_matrix.sv
    tb/run_jt10_phase4ap.sh
    tb/generate_jt10_phase4ap_variants.py
    tb/jt10_phase4ap_sources.f
    tb/jt10_phase4ap_fixture.md
)

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
        "$repo_root/tb/jt10_phase4a_adpcmb_reference.sv" \
        "$repo_root/tb/jt10_phase4a_adpcmb_rom.sv" \
        "$repo_root/tb/tb_jt10_phase4a_adpcmb_single_shot.sv" \
        "$dst/tb/"
}

apply_compatibility() {
    local dst="$1"
    python3 "$repo_root/tb/jt10_compat/apply_icarus_syntax_compat.py" \
        "$dst"
    python3 "$repo_root/tb/jt10_compat/apply_local_interface_compat.py" \
        "$dst"
    python3 \
        "$repo_root/tb/jt10_compat/apply_jt10_counter_reset_compat.py" \
        "$dst"
}

protected_digest() {
    local file
    for file in "${protected[@]}"; do
        shasum -a 256 "$repo_root/$file"
        stat -f '%N size=%z mtime=%m inode=%i' "$repo_root/$file"
    done
}

summary() {
    rg '^(PHASE4A_(CASE|AUX|INACTIVE|RETRIGGER|PRIMARY|ANCHOR|TRANSPORT|SAMPLE|STATUS|PASS))' \
        "$1"
}

normalize() {
    summary "$1" | sed -E 's/run=[0-9]+/run=N/g'
}

echo "== Phase 4A baseline =="
branch="$(git -C "$repo_root" branch --show-current)"
head_sha="$(git -C "$repo_root" rev-parse HEAD)"
[[ "$branch" == "ym2610-family-bringup" ]]
if [[ "$head_sha" != "$base_head" ]]; then
    [[ "$(git -C "$repo_root" rev-parse HEAD^)" == "$base_head" ]]
    [[ "$(git -C "$repo_root" show -s --format=%s HEAD)" == \
        "$final_subject" ]]
fi
git -C "$repo_root" diff --cached --quiet
protected_digest > "$log_root/protected-before.txt"
for file in "${protected[@]}"; do
    [[ -f "$repo_root/$file" ]]
    ! git -C "$repo_root" ls-files --error-unmatch "$file" \
        >/dev/null 2>&1
done
[[ "$(shasum -a 256 "$repo_root/tb/tb_jt49_audio_compare.sv" | awk '{print $1}')" == \
    35cbd96d057e9889815229f2c0e154614eea7956ae895afdb74f6ace2b65406c ]]
[[ "$(stat -f '%z/%m/%i' "$repo_root/tb/tb_jt49_audio_compare.sv")" == \
    4939/1784686524/21984214 ]]
echo "PHASE4A_BASELINE branch=$branch head=$head_sha protected=23"

pinned_count=0
while IFS=$'\t' read -r relative expected_blob expected_sha; do
    [[ -z "$relative" || "$relative" == \#* ]] && continue
    file="$pinned_root/$relative"
    [[ "$(git -C "$repo_root" hash-object "$file")" == \
        "$expected_blob" ]]
    [[ "$(shasum -a 256 "$file" | awk '{print $1}')" == \
        "$expected_sha" ]]
    pinned_count=$((pinned_count + 1))
done < "$blob_manifest"
[[ "$pinned_count" -eq 15 ]]
for file in jt10_adpcm_div.v jt10_adpcm_drvB.v jt10_adpcmb_cnt.v \
    jt10_adpcmb_gain.v jt10_adpcmb_interpol.v; do
    cmp "$overlay_root/$file" \
        <(git -C "$repo_root" show "$base_head:rtl/genesis_audio/jt10_ym2610/adpcm/$file")
done
cmp "$repo_root/rtl/genesis_audio/jt10_ym2610/PC_GATE_PROVENANCE.md" \
    <(git -C "$repo_root" show "$base_head:rtl/genesis_audio/jt10_ym2610/PC_GATE_PROVENANCE.md")
echo "PHASE4A_SOURCE pinned=15 overlay=5 provenance=MATCH"

work_root="$source_root/work"
copy_sources "$work_root"
apply_compatibility "$work_root" > "$log_root/compat.log"
"$repo_root/tb/jt10_phase4afix_apply_overlay.sh" \
    "$work_root" "$overlay_root" > "$log_root/overlay.log"

while IFS= read -r source; do
    [[ -z "$source" || "$source" == \#* ]] && continue
    perl -ne \
        'print "$1\n" if /^\s*module\s+([A-Za-z_][A-Za-z0-9_]*)/' \
        "$work_root/$source"
done < <(cat "$phase0_manifest" "$phase4a_manifest") | \
    sort > "$log_root/modules.txt"
uniq -d "$log_root/modules.txt" > "$log_root/duplicates.txt"
[[ ! -s "$log_root/duplicates.txt" ]]

echo "== Icarus non-SIMULATION three-run =="
(
    cd "$work_root"
    iverilog -g2012 -Wall -I tb -s "$top" \
        -o "$build_root/phase4a.vvp" \
        -f "$phase0_manifest" -f "$phase4a_manifest"
) > "$log_root/iverilog.log" 2>&1
pids=()
for run in 1 2 3; do
    (
        cd "$work_root"
        stdbuf -oL vvp "$build_root/phase4a.vvp" +RUN_ID="$run"
    ) > "$log_root/run-$run.log" 2>&1 &
    pids+=("$!")
done
for pid in "${pids[@]}"; do wait "$pid"; done
for run in 1 2 3; do
    ! rg -q '^PHASE4A_FAIL|^FATAL:' "$log_root/run-$run.log"
    rg -q "^PHASE4A_PASS run=$run$" "$log_root/run-$run.log"
    normalize "$log_root/run-$run.log" > "$log_root/run-$run.norm"
done
diff -u "$log_root/run-1.norm" "$log_root/run-2.norm"
diff -u "$log_root/run-1.norm" "$log_root/run-3.norm"
summary "$log_root/run-1.log"
echo "PHASE4A_DETERMINISM runs=3 result=MATCH"

echo "== Icarus SIMULATION =="
(
    cd "$work_root"
    iverilog -g2012 -Wall -DSIMULATION -I tb -s "$top" \
        -o "$build_root/phase4a-sim.vvp" \
        -f "$phase0_manifest" -f "$phase4a_manifest"
) > "$log_root/iverilog-sim.log" 2>&1
(
    cd "$work_root"
    vvp "$build_root/phase4a-sim.vvp" +RUN_ID=1
) > "$log_root/sim.log" 2>&1
normalize "$log_root/sim.log" > "$log_root/sim.norm"
diff -u "$log_root/run-1.norm" "$log_root/sim.norm"
echo "PHASE4A_SIMULATION result=MATCH"

echo "== Verilator Phase 4A =="
set +e
(
    cd "$work_root"
    verilator --lint-only --timing -Wall -Wno-fatal -Itb \
        --top-module "$top" \
        -f "$phase0_manifest" -f "$phase4a_manifest"
) > "$log_root/verilator.log" 2>&1
verilator_rc="$?"
set -e
[[ "$verilator_rc" -eq 0 ]]
sed -n 's/^%Warning-\([^:]*\).*/\1/p' "$log_root/verilator.log" | \
    sort | uniq -c > "$log_root/verilator-warnings.txt"
echo "PHASE4A_VERILATOR rc=$verilator_rc warnings=$(rg -c '^%Warning-' "$log_root/verilator.log" || true) result=PASS"

echo "== Phase 4A-FIX and Phase 1-3 regressions =="
bash "$repo_root/tb/run_jt10_phase4afix.sh" \
    > "$log_root/phase4afix-regression.log" 2>&1
rg -q '^PHASE4AFIX_LOCAL_AUDIT PASS' \
    "$log_root/phase4afix-regression.log"
rg '^(PHASE4AFIX_(ACTIVE|INACTIVE|RESTART|TRANSPORT|SAMPLE|CLASS|PASS|LOCAL_AUDIT)|PHASE3C_(SCENARIO|PASS|REGRESSION)|PHASE3B_(CANONICAL_HASHES|REGRESSION)|PHASE3A_VOICE0_REGRESSION|PHASE2B_SSG_REGRESSION|PHASE1C_FM_REGRESSION)' \
    "$log_root/phase4afix-regression.log" \
    > "$log_root/regression-summary.txt"
cat "$log_root/regression-summary.txt"

echo "== production isolation =="
git -C "$repo_root" diff --check
git -C "$repo_root" diff --quiet "$base_head" -- \
    rtl/genesis_audio/jt10_ym2610 \
    rtl/genesis_audio/jt12 rtl/genesis_audio/jt49 \
    rtl/vgm_loaded_player.sv rtl/mister_vgm_md_top.sv \
    rtl/vgm_ddram_backend.sv rtl/md_sound_module.sv \
    rtl/ym2203_sound_module.sv rtl/emu.sv sys/sys_top.v \
    rtl/genesis_audio/jtoutrun rtl/segapcm_sound_module.sv \
    rtl/audio_mixer.sv files.qip VGM_MD_MiSTer.qsf \
    tb/jt10_pinned tb/jt10_compat \
    tb/jt10_phase0_warmup_wrapper.sv tb/jt10_cpu_bus_bfm.sv
if rg -n \
    'jt10_ym2610|phase4afix|phase4ap|phase4arv1|phase4ax|phase4ar|phase4a_adpcmb|phase3cr|tb_jt10_phase|jt10_pinned|standard_jt10' \
    "$repo_root/files.qip" "$repo_root/VGM_MD_MiSTer.qsf" \
    "$repo_root/rtl" "$repo_root/sys" \
    -g '!rtl/genesis_audio/jt10_ym2610/**'; then
    exit 1
fi
[[ "$(git -C "$repo_root" rev-parse "$base_head:files.qip")" == \
    71d98974f2672207467eac493c06bbc23c74e45b ]]
[[ "$(git -C "$repo_root" rev-parse "$base_head:VGM_MD_MiSTer.qsf")" == \
    898ae5a61d7c1f94d9f824a9007fcadff65383f9 ]]
protected_digest > "$log_root/protected-after.txt"
diff -u "$log_root/protected-before.txt" "$log_root/protected-after.txt"
if git -C "$repo_root" ls-files --others --exclude-standard | \
    rg -q '\.(vvp|vcd|fst|lxt|log|raw|wav|dec)$'; then
    echo "FAIL repository simulation artifact"
    exit 1
fi
echo "PHASE4A_PRODUCTION result=PASS protected=23 build_refs=0"
echo "PHASE4A_LOCAL_AUDIT PASS sources=$source_root build=$build_root logs=$log_root"
