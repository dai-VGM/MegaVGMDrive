#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
SIMULATION=${TMPDIR:-/tmp}/supervisor_early_load_boundary.$$
trap 'rm -f "$SIMULATION"' EXIT HUP INT TERM

# Supervisor waits for the exported status record before starting the first
# scripted load. Keep that record under the same extended reset as md_sound.
STATUS_EXPORT_BLOCK=$(sed -n \
	'/megavgm_playlist_status_export playlist_status_export (/,/^[[:space:]]*);/p' \
	"$REPO_ROOT/rtl/emu.sv")
printf '%s\n' "$STATUS_EXPORT_BLOCK" | \
	grep -Eq '\.reset[[:space:]]*\(vgm_reset\),'

iverilog -g2012 -DMEGAVGMDRIVE_PLAYLIST_LOOP_PHASE1E=1 \
	-s tb_supervisor_early_load_boundary \
	-o "$SIMULATION" \
	"$REPO_ROOT/rtl/megavgm_title_receiver.sv" \
	"$REPO_ROOT/rtl/megavgm_playlist_status_export.sv" \
	"$REPO_ROOT/rtl/vgm_ddram_backend.sv" \
	"$REPO_ROOT/tb/tb_supervisor_early_load_boundary.sv"
vvp "$SIMULATION"
