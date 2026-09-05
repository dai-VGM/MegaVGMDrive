#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
audit_tmp="$(mktemp -d "${TMPDIR:-/tmp}/mode5-stop-diag-source.XXXXXX")"
trap 'rm -rf "$audit_tmp"' EXIT
cd "$repo_root"

base=9f30ca68b288cb394cb720af0a4d3718000396c7
git show "$base:rtl/mister_vgm_md_top.sv" > "$audit_tmp/base_top.sv"
git show "$base:rtl/emu.sv" > "$audit_tmp/base_emu.sv"

# With the diagnostic macro absent, the shared production source preprocesses
# to the exact 9f30ca6 functional text (ignoring blank-line placement).
iverilog -E -I . -o "$audit_tmp/base_top.pp" "$audit_tmp/base_top.sv"
iverilog -E -I . -o "$audit_tmp/work_top.pp" rtl/mister_vgm_md_top.sv
iverilog -E -I . -I tb -o "$audit_tmp/base_emu.pp" "$audit_tmp/base_emu.sv"
iverilog -E -I . -I tb -o "$audit_tmp/work_emu.pp" rtl/emu.sv
diff -w -B "$audit_tmp/base_top.pp" "$audit_tmp/work_top.pp"
diff -w -B "$audit_tmp/base_emu.pp" "$audit_tmp/work_emu.pp"

# The diagnostic revision inherits the production lab and adds exactly one
# observer source plus one macro. The observer has no control output.
grep -qx 'source MegaVGMPlayer_PlaylistLoopLab_MiSTer.qsf' \
    MegaVGMPlayer_PlaylistStopDiag_MiSTer.qsf
grep -qx 'set_global_assignment -name SYSTEMVERILOG_FILE rtl/megavgm_mode5_stop_diagnostic.sv' \
    MegaVGMPlayer_PlaylistStopDiag_MiSTer.qsf
grep -qx 'set_global_assignment -name VERILOG_MACRO "MEGAVGMDRIVE_MODE5_STOP_DIAGNOSTIC=1"' \
    MegaVGMPlayer_PlaylistStopDiag_MiSTer.qsf
if grep -Eq '^\s*output logic' rtl/megavgm_mode5_stop_diagnostic.sv | \
   grep -v 'snapshot_bus'; then
    echo "unexpected diagnostic control output" >&2
    exit 1
fi

diag_refs="$(rg -l 'mode5_stop_diag_bus' rtl)"
test "$diag_refs" = $'rtl/emu.sv\nrtl/mister_vgm_md_top.sv'

# Parse/elaborate the complete diagnostic overlay function while treating its
# board-facing child modules as black boxes. Functional top integration is
# covered separately by run_mode5_stop_diagnostic_integration.sh.
iverilog -g2012 -i -I tb \
    -DMEGAVGMDRIVE_MODE5_STOP_DIAGNOSTIC \
    -DMEGAVGMDRIVE_PLAYLIST_STATUS_PHASE1B \
    -DMEGAVGMDRIVE_PLAYLIST_LOOP_PHASE1E \
    -DMISTER_FB -DFIXED_REGION_MODE=5 \
    -s emu -t null rtl/emu.sv

echo "PASS run_mode5_stop_diagnostic_source_audit"
