#!/bin/sh

set -eu

LC_ALL=C
export LC_ALL

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
TEST_ROOT=${TMPDIR:-/tmp}/megavgm_title_integration.$$

cleanup() {
	rm -rf "$TEST_ROOT"
}
trap cleanup EXIT HUP INT TERM

for tool in awk gzip iverilog mkdir od rm vvp wc; do
	command -v "$tool" >/dev/null 2>&1 || {
		echo "required tool not found: $tool" >&2
		exit 1
	}
done

mkdir -p "$TEST_ROOT/inbox/Out Run" "$TEST_ROOT/out"
SOURCE_VGM=$TEST_ROOT/inbox/Out\ Run/01_Magical\ Sound\ Shower.vgm
PREPARED_VGM=$TEST_ROOT/out/Out\ Run/01_Magical\ Sound\ Shower.vgm
MEMORY_HEX=$TEST_ROOT/prepared.hex
SIMULATION=$TEST_ROOT/title_integration.vvp

awk 'BEGIN {
	printf "Vgm "
	for (i = 4; i < 260; i++) printf "%c", (i % 251)
}' > "$SOURCE_VGM"

sh "$REPO_ROOT/scripts/vgm_md_import.sh" \
	"$TEST_ROOT/inbox" "$TEST_ROOT/out" >/dev/null

[ -f "$PREPARED_VGM" ] || {
	echo "prepared VGM was not generated" >&2
	exit 1
}
PREPARED_SIZE=$(wc -c < "$PREPARED_VGM")
PREPARED_SIZE=$((PREPARED_SIZE + 0))
[ "$PREPARED_SIZE" -eq 388 ] || {
	echo "expected 388-byte prepared VGM, got $PREPARED_SIZE" >&2
	exit 1
}

od -An -v -tx1 "$PREPARED_VGM" > "$MEMORY_HEX"

iverilog -g2012 \
	-s tb_megavgm_title_helper_integration \
	-o "$SIMULATION" \
	"$REPO_ROOT/rtl/megavgm_title_receiver.sv" \
	"$REPO_ROOT/tb/tb_megavgm_title_helper_integration.sv"

vvp "$SIMULATION" \
	"+MEMORY_FILE=$MEMORY_HEX" \
	"+PREPARED_SIZE=$PREPARED_SIZE"
