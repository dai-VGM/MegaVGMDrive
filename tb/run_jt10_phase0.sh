#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
phase0_tmp="$(mktemp -d /private/tmp/jt10-phase0-run.XXXXXX)"
trap 'rm -rf "$phase0_tmp"' EXIT

pristine_root="$phase0_tmp/pristine"
patched_root="$phase0_tmp/patched"
repeat_root="$phase0_tmp/repeat"
pinned_root="$repo_root/tb/jt10_pinned/6d51e0b6"
blob_manifest="$repo_root/tb/jt10_compat/pristine_blobs.tsv"
source_manifest="$repo_root/tb/jt10_phase0_sources.f"

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
}

apply_compatibility() {
    local source_root="$1"
    python3 "$repo_root/tb/jt10_compat/apply_icarus_syntax_compat.py" \
        "$source_root"
    python3 "$repo_root/tb/jt10_compat/apply_local_interface_compat.py" \
        "$source_root"
    python3 "$repo_root/tb/jt10_compat/apply_jt10_counter_reset_compat.py" \
        "$source_root"
}

echo "== pristine pinned-source verification =="
while IFS=$'\t' read -r relative expected_blob expected_sha; do
    [[ -z "$relative" || "$relative" == \#* ]] && continue
    source_file="$pinned_root/$relative"
    actual_blob="$(git -C "$repo_root" hash-object "$source_file")"
    actual_sha="$(shasum -a 256 "$source_file" | awk '{print $1}')"
    [[ "$actual_blob" == "$expected_blob" ]]
    [[ "$actual_sha" == "$expected_sha" ]]
    printf '%-34s blob=%s sha256=%s\n' \
        "$relative" "$actual_blob" "$actual_sha"
done < "$blob_manifest"

copy_sources "$pristine_root"
copy_sources "$patched_root"
copy_sources "$repeat_root"
apply_compatibility "$patched_root"
apply_compatibility "$repeat_root"

echo "== patch reproducibility =="
(
    cd "$patched_root"
    find rtl tb -type f -print0 | sort -z | xargs -0 shasum -a 256
) > "$phase0_tmp/patched.sha256"
(
    cd "$repeat_root"
    find rtl tb -type f -print0 | sort -z | xargs -0 shasum -a 256
) > "$phase0_tmp/repeat.sha256"
diff -u "$phase0_tmp/patched.sha256" "$phase0_tmp/repeat.sha256"
echo "PATCH_REPRODUCIBILITY PASS"

echo "== patched pinned-source SHA-256 =="
while IFS=$'\t' read -r relative _expected_blob _expected_sha; do
    [[ -z "$relative" || "$relative" == \#* ]] && continue
    patched_file="$patched_root/rtl/genesis_audio/jt12/standard_jt10/$relative"
    printf '%-34s sha256=%s\n' \
        "$relative" "$(shasum -a 256 "$patched_file" | awk '{print $1}')"
done < "$blob_manifest"

echo "== duplicate module check =="
while IFS= read -r source_file; do
    [[ -z "$source_file" || "$source_file" == \#* ]] && continue
    perl -ne 'print "$1\n" if /^\s*module\s+([A-Za-z_][A-Za-z0-9_]*)/' \
        "$patched_root/$source_file"
done < "$source_manifest" | sort > "$phase0_tmp/modules.txt"
uniq -d "$phase0_tmp/modules.txt" > "$phase0_tmp/duplicate_modules.txt"
if [[ -s "$phase0_tmp/duplicate_modules.txt" ]]; then
    echo "Duplicate modules:"
    sed -n '1,100p' "$phase0_tmp/duplicate_modules.txt"
    exit 1
fi
echo "DUPLICATE_MODULES 0"

echo "== Verilator pristine comparison =="
(
    cd "$pristine_root"
    verilator --lint-only --timing -Wall -Wno-fatal \
        --top-module tb_jt10_standalone_elaboration \
        -f "$source_manifest"
) 2>&1 | tee "$phase0_tmp/verilator-pristine.log"

echo "== Icarus compile/elaboration =="
(
    cd "$patched_root"
    iverilog -g2012 -Wall -s tb_jt10_standalone_elaboration \
        -f "$source_manifest" -o "$phase0_tmp/tb_jt10.vvp"
) 2>&1 | tee "$phase0_tmp/iverilog-compile.log"

echo "== Icarus simulation =="
(
    cd "$patched_root"
    vvp "$phase0_tmp/tb_jt10.vvp"
) 2>&1 | tee "$phase0_tmp/iverilog-sim.log"

echo "== Verilator patched lint/elaboration =="
(
    cd "$patched_root"
    verilator --lint-only --timing -Wall -Wno-fatal \
        --top-module tb_jt10_standalone_elaboration \
        -f "$source_manifest"
) 2>&1 | tee "$phase0_tmp/verilator-patched.log"

echo "== production isolation =="
git -C "$repo_root" diff --quiet \
    5ecce555edb80bdcb010a322ee46ba8837a6ee27 -- \
    rtl/emu.sv \
    rtl/vgm_loaded_player.sv \
    rtl/mister_vgm_md_top.sv \
    rtl/vgm_ddram_backend.sv \
    rtl/md_sound_module.sv \
    rtl/ym2203_sound_module.sv \
    sys/sys_top.v \
    rtl/genesis_audio/jt12 \
    rtl/genesis_audio/jt49 \
    rtl/genesis_audio/jtoutrun \
    rtl/segapcm_sound_module.sv \
    VGM_MD_MiSTer.qsf \
    files.qip
echo "PRODUCTION_BLOBS MATCH"
echo "PHASE0_RUNNER PASS"
