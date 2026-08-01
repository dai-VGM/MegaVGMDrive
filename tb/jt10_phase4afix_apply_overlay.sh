#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 2 ]]; then
    echo "usage: jt10_phase4afix_apply_overlay.sh TEMP_SOURCE_ROOT OVERLAY_ROOT" >&2
    exit 2
fi

source_root="$1"
overlay_root="$2"
standard_adpcm="$source_root/rtl/genesis_audio/jt12/standard_jt10/adpcm"
divider_adpcm="$source_root/rtl/genesis_audio/jt12/adpcm"

expected=(
    jt10_adpcm_div.v
    jt10_adpcm_drvB.v
    jt10_adpcmb_cnt.v
    jt10_adpcmb_gain.v
    jt10_adpcmb_interpol.v
)

actual_list="$(
    find "$overlay_root" -maxdepth 1 -type f -name '*.v' -print |
        sed 's#.*/##' | sort
)"
wanted_list="$(printf '%s\n' "${expected[@]}" | sort)"
diff -u <(printf '%s\n' "$wanted_list") \
    <(printf '%s\n' "$actual_list")

cp "$overlay_root/jt10_adpcm_div.v" "$divider_adpcm/"
for file in jt10_adpcm_drvB.v jt10_adpcmb_cnt.v \
    jt10_adpcmb_gain.v jt10_adpcmb_interpol.v; do
    cp "$overlay_root/$file" "$standard_adpcm/"
done

echo "PHASE4AFIX_OVERLAY_APPLIED root=$overlay_root files=5 result=PASS"
