#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
base_head="48df6033e104c3685488f068f9fe9e4c83c34c01"
final_subject="Fix JT10 ADPCM-B lifecycle contracts"
pinned_root="$repo_root/tb/jt10_pinned/6d51e0b6"
blob_manifest="$repo_root/tb/jt10_compat/pristine_blobs.tsv"
overlay_root="$repo_root/rtl/genesis_audio/jt10_ym2610/adpcm"
v1_generator="$repo_root/tb/generate_jt10_phase4ax_variants.py"
pc_generator="$repo_root/tb/generate_jt10_phase4ap_variants.py"
phase0_manifest="$repo_root/tb/jt10_phase0_sources.f"
phase4ap_manifest="$repo_root/tb/jt10_phase4ap_sources.f"
phase4afix_manifest="$repo_root/tb/jt10_phase4afix_sources.f"
top="tb_jt10_phase4afix_adpcmb_lifecycle"

mkdir -p /tmp/jt10_phase4afix_sources \
    /tmp/jt10_phase4afix_build /tmp/jt10_phase4afix_logs
source_root="$(mktemp -d /tmp/jt10_phase4afix_sources/run.XXXXXX)"
build_root="$(mktemp -d /tmp/jt10_phase4afix_build/run.XXXXXX)"
log_root="$(mktemp -d /tmp/jt10_phase4afix_logs/run.XXXXXX)"

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
        "$repo_root/tb/tb_jt10_phase4afix_adpcmb_audit_base.sv" \
        "$repo_root/tb/tb_jt10_phase4afix_adpcmb_lifecycle.sv" \
        "$repo_root/tb/tb_jt10_phase4ar_adpcmb_stop_contract.sv" \
        "$repo_root/tb/tb_jt10_phase4ap_adpcmb_patch_matrix.sv" \
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

tree_digest() {
    (
        cd "$1"
        find . -type f -print0 | sort -z | xargs -0 shasum -a 256
    )
}

protected_digest() {
    local file
    for file in "${protected[@]}"; do
        shasum -a 256 "$repo_root/$file"
        stat -f '%N size=%z mtime=%m inode=%i' "$repo_root/$file"
    done
}

summary() {
    rg '^(PHASE4AFIX_(INACTIVE|ACTIVE|RESTART|TRANSPORT|SAMPLE|CLASS|PASS))' \
        "$1"
}

normalize() {
    summary "$1" | sed -E 's/run=[0-9]+/run=N/g'
}

echo "== Phase 4A-FIX baseline =="
branch="$(git -C "$repo_root" branch --show-current)"
head_sha="$(git -C "$repo_root" rev-parse HEAD)"
[[ "$branch" == "ym2610-family-bringup" ]]
if [[ "$head_sha" != "$base_head" ]]; then
    [[ "$(git -C "$repo_root" rev-parse HEAD^)" == "$base_head" ]]
    [[ "$(git -C "$repo_root" show -s --format=%s HEAD)" == \
        "$final_subject" ]]
fi
git -C "$repo_root" diff --cached --quiet
echo "BASELINE branch=$branch head=$head_sha base=$base_head"

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
echo "PROTECTED_UNTRACKED count=23 sacred=MATCH"

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
echo "PRISTINE_PINNED count=$pinned_count result=MATCH"

echo "== independent PC-GATE regeneration =="
for name in base-a base-b v1-a v1-b pc-a pc-b; do
    copy_sources "$source_root/$name"
    apply_compatibility "$source_root/$name" \
        > "$log_root/$name-compat.log"
done
tree_digest "$source_root/base-a" > "$log_root/base-a.sha256"
tree_digest "$source_root/base-b" > "$log_root/base-b.sha256"
diff -u "$log_root/base-a.sha256" "$log_root/base-b.sha256"
for name in v1-a v1-b pc-a pc-b; do
    python3 "$v1_generator" "$source_root/$name" V1 \
        > "$log_root/$name-v1.log"
done
python3 "$pc_generator" "$source_root/pc-a" PC_GATE \
    > "$log_root/pc-a.log"
python3 "$pc_generator" "$source_root/pc-b" PC_GATE \
    > "$log_root/pc-b.log"
tree_digest "$source_root/v1-a" > "$log_root/v1-a.sha256"
tree_digest "$source_root/v1-b" > "$log_root/v1-b.sha256"
tree_digest "$source_root/pc-a" > "$log_root/pc-a.sha256"
tree_digest "$source_root/pc-b" > "$log_root/pc-b.sha256"
diff -u "$log_root/v1-a.sha256" "$log_root/v1-b.sha256"
diff -u "$log_root/pc-a.sha256" "$log_root/pc-b.sha256"
diff -u "$log_root/pc-a.log" "$log_root/pc-b.log"
diff -ru "$source_root/v1-a" "$source_root/pc-a" \
    > "$log_root/pc-gate.diff" || [[ "$?" -eq 1 ]]
diff -ru "$source_root/base-a" "$source_root/pc-a" \
    > "$log_root/pc-gate-from-base.diff" || [[ "$?" -eq 1 ]]
[[ "$(wc -l < "$log_root/pc-gate.diff" | tr -d ' ')" == 168 ]]
[[ "$(rg -c '^diff -ru ' "$log_root/pc-gate.diff")" == 4 ]]
[[ "$(rg '^\+' "$log_root/pc-gate.diff" | rg -v '^\+\+\+' | wc -l | tr -d ' ')" == 45 ]]
[[ "$(rg '^-' "$log_root/pc-gate.diff" | rg -v '^---' | wc -l | tr -d ' ')" == 9 ]]
echo "PC_GATE_REGEN runs=2 v1=MATCH candidate=MATCH diff=168/+45/-9"

declare -a generated=(
    "rtl/genesis_audio/jt12/adpcm/jt10_adpcm_div.v"
    "rtl/genesis_audio/jt12/standard_jt10/adpcm/jt10_adpcm_drvB.v"
    "rtl/genesis_audio/jt12/standard_jt10/adpcm/jt10_adpcmb_cnt.v"
    "rtl/genesis_audio/jt12/standard_jt10/adpcm/jt10_adpcmb_gain.v"
    "rtl/genesis_audio/jt12/standard_jt10/adpcm/jt10_adpcmb_interpol.v"
)
declare -a overlay=(
    "jt10_adpcm_div.v"
    "jt10_adpcm_drvB.v"
    "jt10_adpcmb_cnt.v"
    "jt10_adpcmb_gain.v"
    "jt10_adpcmb_interpol.v"
)
actual_overlay_list="$(
    find "$overlay_root" -maxdepth 1 -type f -name '*.v' -print |
        sed 's#.*/##' | sort
)"
expected_overlay_list="$(printf '%s\n' "${overlay[@]}" | sort)"
diff -u <(printf '%s\n' "$expected_overlay_list") \
    <(printf '%s\n' "$actual_overlay_list")
for index in "${!overlay[@]}"; do
    cmp "$source_root/pc-a/${generated[$index]}" \
        "$overlay_root/${overlay[$index]}"
done
! rg -n 'stop_clr|^[[:space:]]*(`ifdef[[:space:]]+SIMULATION|initial\b|force\b|release\b)' \
    "$overlay_root"/*.v
echo "OVERLAY_COMPARE files=5 byte_exact=PASS pc_clear=ABSENT synth_only=PASS"

echo "== F0 source separation =="
work_root="$source_root/work"
copy_sources "$work_root"
apply_compatibility "$work_root" > "$log_root/work-compat.log"
"$repo_root/tb/jt10_phase4afix_apply_overlay.sh" \
    "$work_root" "$overlay_root" > "$log_root/overlay-apply.log"
while IFS= read -r source; do
    [[ -z "$source" || "$source" == \#* ]] && continue
    perl -ne \
        'print "$1\n" if /^\s*module\s+([A-Za-z_][A-Za-z0-9_]*)/' \
        "$work_root/$source"
done < <(cat "$phase0_manifest" "$phase4afix_manifest") |
    sort > "$log_root/modules.txt"
uniq -d "$log_root/modules.txt" > "$log_root/duplicates.txt"
[[ ! -s "$log_root/duplicates.txt" ]]
echo "PHASE4AFIX_F0 pinned=15 overlay=5 duplicate=0 result=PASS"

echo "== Icarus Phase 4A-FIX non-SIMULATION three-run =="
(
    cd "$work_root"
    iverilog -g2012 -Wall -I tb -s "$top" \
        -o "$build_root/phase4afix.vvp" \
        -f "$phase0_manifest" -f "$phase4afix_manifest"
) > "$log_root/iverilog.log" 2>&1
pids=()
for run in 1 2 3; do
    (
        cd "$work_root"
        stdbuf -oL vvp "$build_root/phase4afix.vvp" \
            +VARIANT=PC_GATE +VARIANT_ID=6 +RUN_ID="$run"
    ) > "$log_root/run-$run.log" 2>&1 &
    pids+=("$!")
done
for pid in "${pids[@]}"; do wait "$pid"; done
for run in 1 2 3; do
    ! rg -q '^PHASE4AFIX_FAIL|^FATAL:' "$log_root/run-$run.log"
    rg -q "^PHASE4AFIX_PASS variant=PC_GATE run=$run$" \
        "$log_root/run-$run.log"
    normalize "$log_root/run-$run.log" > "$log_root/run-$run.norm"
done
diff -u "$log_root/run-1.norm" "$log_root/run-2.norm"
diff -u "$log_root/run-1.norm" "$log_root/run-3.norm"
summary "$log_root/run-1.log"
echo "PHASE4AFIX_DETERMINISM runs=3 result=MATCH"

echo "== Icarus Phase 4A-FIX SIMULATION =="
(
    cd "$work_root"
    iverilog -g2012 -Wall -DSIMULATION -I tb -s "$top" \
        -o "$build_root/phase4afix-sim.vvp" \
        -f "$phase0_manifest" -f "$phase4afix_manifest"
) > "$log_root/iverilog-sim.log" 2>&1
(
    cd "$work_root"
    stdbuf -oL vvp "$build_root/phase4afix-sim.vvp" \
        +VARIANT=PC_GATE +VARIANT_ID=6 +RUN_ID=1
) > "$log_root/sim.log" 2>&1
normalize "$log_root/sim.log" > "$log_root/sim.norm"
diff -u "$log_root/run-1.norm" "$log_root/sim.norm"
echo "PHASE4AFIX_SIMULATION result=MATCH"

echo "== Phase 4A-P selected-candidate smoke =="
(
    cd "$work_root"
    iverilog -g2012 -Wall -I tb \
        -s tb_jt10_phase4ap_adpcmb_patch_matrix \
        -o "$build_root/phase4ap-smoke.vvp" \
        -f "$phase0_manifest" -f "$phase4ap_manifest"
    vvp "$build_root/phase4ap-smoke.vvp" \
        +VARIANT=PC_GATE +VARIANT_ID=6 +RUN_ID=1 +QUICK
) > "$log_root/phase4ap-smoke.log" 2>&1
rg -q '^PHASE4AP_PASS variant=PC_GATE run=1$' \
    "$log_root/phase4ap-smoke.log"
rg -q '^PHASE4AP_CLASS .*output=ZERO request=GATED restart=REPLAY integrated=1 selected=1 rejected=0 failures=0$' \
    "$log_root/phase4ap-smoke.log"
echo "PHASE4AP_PC_GATE_SMOKE result=PASS"

echo "== Verilator Phase 4A-FIX =="
set +e
(
    cd "$work_root"
    verilator --lint-only --timing -Wall -Wno-fatal -Itb \
        --top-module "$top" \
        -f "$phase0_manifest" -f "$phase4afix_manifest"
) > "$log_root/verilator.log" 2>&1
verilator_rc="$?"
set -e
[[ "$verilator_rc" -eq 0 ]]
sed -n 's/^%Warning-\([^:]*\).*/\1/p' "$log_root/verilator.log" |
    sort | uniq -c > "$log_root/verilator-warnings.txt"
echo "PHASE4AFIX_VERILATOR rc=$verilator_rc warnings=$(rg -c '^%Warning-' "$log_root/verilator.log" || true) result=PASS"

echo "== Phase 3C through Phase 1C overlay regression =="
export JT10_PHASE4AFIX_REGRESSION=1
export JT10_OVERLAY_ROOT="$overlay_root"
bash "$repo_root/tb/run_jt10_phase3c.sh" \
    > "$log_root/phase3c-regression.log" 2>&1
rg -q '^PHASE3C_REGRESSION PASS$' "$log_root/phase3c-regression.log"
rg -q '^PHASE3B_REGRESSION PASS$' "$log_root/phase3c-regression.log"
rg -q '^PHASE3A_VOICE0_REGRESSION PASS$' "$log_root/phase3c-regression.log"
rg -q '^PHASE2B_SSG_REGRESSION PASS$' "$log_root/phase3c-regression.log"
rg -q '^PHASE1C_FM_REGRESSION PASS$' "$log_root/phase3c-regression.log"
rg '^(PHASE3C_(SCENARIO|PASS)|PHASE3B_CANONICAL_HASHES|VOICE0_5_ALIGNED_WAVEFORM_MATCH|PHASE3B_REGRESSION|PHASE3A_VOICE0_REGRESSION|PHASE2B_SSG_REGRESSION|PHASE1C_FM_REGRESSION)' \
    "$log_root/phase3c-regression.log" > "$log_root/regression-summary.txt"
cat "$log_root/regression-summary.txt"

echo "== production isolation =="
git -C "$repo_root" diff --check
git -C "$repo_root" diff --quiet "$base_head" -- \
    rtl/genesis_audio/jt12 rtl/genesis_audio/jt49 \
    rtl/vgm_loaded_player.sv rtl/mister_vgm_md_top.sv \
    rtl/vgm_ddram_backend.sv rtl/md_sound_module.sv \
    rtl/ym2203_sound_module.sv rtl/emu.sv sys/sys_top.v \
    rtl/genesis_audio/jtoutrun rtl/segapcm_sound_module.sv \
    rtl/audio_mixer.sv files.qip VGM_MD_MiSTer.qsf \
    tb/jt10_pinned tb/jt10_compat \
    tb/jt10_phase0_warmup_wrapper.sv tb/jt10_cpu_bus_bfm.sv
if rg -n \
    'jt10_ym2610|phase4afix|phase4ap|phase4arv1|phase4ax|phase4ar|phase3cr|tb_jt10_phase|jt10_pinned|standard_jt10' \
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
if git -C "$repo_root" ls-files --others --exclude-standard |
    rg -q '\.(vvp|vcd|fst|lxt|log|raw|wav|dec)$'; then
    echo "FAIL repository simulation artifact"
    exit 1
fi
echo "PRODUCTION_ISOLATION result=PASS protected=23 build_refs=0"
echo "PHASE4AFIX_LOCAL_AUDIT PASS sources=$source_root build=$build_root logs=$log_root"
