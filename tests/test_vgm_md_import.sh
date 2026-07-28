#!/bin/sh

set -eu

LC_ALL=C
export LC_ALL

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
HELPER=$REPO_ROOT/scripts/vgm_md_import.sh
TEST_ROOT=${TMPDIR:-/tmp}/vgm_md_import_test.$$
TRAILER_SIZE=128
MAX_PREPARED_SIZE=4194304
tests_run=0

cleanup() {
	rm -rf "$TEST_ROOT"
}
trap cleanup EXIT HUP INT TERM

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

pass() {
	tests_run=$((tests_run + 1))
	echo "PASS: $1"
}

file_size() {
	fs_value=$(wc -c < "$1") || return 1
	printf '%d\n' "$((fs_value + 0))"
}

make_body() {
	mb_file=$1
	mb_size=${2:-260}
	awk -v size="$mb_size" 'BEGIN {
		printf "Vgm "
		for (i = 4; i < size; i++) printf "%c", (i % 251)
	}' > "$mb_file"
}

read_decimal_bytes() {
	rdb_file=$1
	rdb_offset=$2
	rdb_count=$3
	dd if="$rdb_file" bs=1 skip="$rdb_offset" count="$rdb_count" 2>/dev/null |
		od -An -v -tu1 |
		awk '{
			for (i = 1; i <= NF; i++) {
				if (seen++) printf " "
				printf "%d", $i
			}
		}
		END { printf "\n" }'
}

read_u32_le() {
	rul_bytes=$(read_decimal_bytes "$1" "$2" 4)
	set -- $rul_bytes
	[ "$#" -eq 4 ] || fail "could not read four-byte integer from $1 at $2"
	printf '%d\n' "$(($1 + ($2 * 256) + ($3 * 65536) + ($4 * 16777216)))"
}

assert_eq() {
	ae_expected=$1
	ae_actual=$2
	ae_label=$3
	[ "$ae_actual" = "$ae_expected" ] ||
		fail "$ae_label: expected '$ae_expected', got '$ae_actual'"
}

assert_zero_region() {
	azr_file=$1
	azr_offset=$2
	azr_count=$3
	azr_label=$4
	if ! dd if="$azr_file" bs=1 skip="$azr_offset" count="$azr_count" 2>/dev/null |
		od -An -v -tu1 |
		awk -v expected="$azr_count" '
			{
				for (i = 1; i <= NF; i++) {
					if ($i != 0) exit 1
					count++
				}
			}
			END {
				if (count != expected) exit 1
			}
		'; then
		fail "$azr_label is not all zero"
	fi
}

assert_prepared() {
	ap_label=$1
	ap_output=$2
	ap_body=$3
	ap_directory=$4
	ap_basename=$5

	ap_body_size=$(file_size "$ap_body")
	ap_output_size=$(file_size "$ap_output")
	ap_trailer_offset=$((ap_output_size - TRAILER_SIZE))
	assert_eq "$((ap_body_size + TRAILER_SIZE))" "$ap_output_size" \
		"$ap_label physical size"
	assert_eq "$ap_body_size" "$ap_trailer_offset" "$ap_label trailer offset"

	ap_magic=$(read_decimal_bytes "$ap_output" "$ap_trailer_offset" 8)
	assert_eq "77 86 71 77 84 84 76 0" "$ap_magic" "$ap_label magic"

	ap_fixed=$(read_decimal_bytes "$ap_output" "$((ap_trailer_offset + 8))" 8)
	set -- $ap_fixed
	[ "$#" -eq 8 ] || fail "$ap_label fixed header is short"
	assert_eq "1" "$1" "$ap_label version"
	ap_expected_flags=0
	[ -n "$ap_directory" ] && ap_expected_flags=$((ap_expected_flags | 1))
	[ -n "$ap_basename" ] && ap_expected_flags=$((ap_expected_flags | 2))
	assert_eq "$ap_expected_flags" "$2" "$ap_label flags"
	assert_eq "${#ap_directory}" "$3" "$ap_label directory length"
	assert_eq "${#ap_basename}" "$4" "$ap_label basename length"
	assert_eq "128" "$5" "$ap_label trailer-size low byte"
	assert_eq "0" "$6" "$ap_label trailer-size high byte"
	assert_eq "0" "$7" "$ap_label reserved 0x0e"
	assert_eq "0" "$8" "$ap_label reserved 0x0f"

	ap_stored_size=$(read_u32_le "$ap_output" "$((ap_trailer_offset + 16))")
	assert_eq "$ap_body_size" "$ap_stored_size" "$ap_label original size"

	ap_actual_directory=$(dd if="$ap_output" bs=1 \
		skip=$((ap_trailer_offset + 32)) count="${#ap_directory}" 2>/dev/null)
	ap_actual_basename=$(dd if="$ap_output" bs=1 \
		skip=$((ap_trailer_offset + 64)) count="${#ap_basename}" 2>/dev/null)
	assert_eq "$ap_directory" "$ap_actual_directory" "$ap_label directory"
	assert_eq "$ap_basename" "$ap_actual_basename" "$ap_label basename"

	assert_zero_region "$ap_output" "$((ap_trailer_offset + 20))" 12 \
		"$ap_label reserved 0x14"
	assert_zero_region "$ap_output" \
		"$((ap_trailer_offset + 32 + ${#ap_directory}))" \
		"$((32 - ${#ap_directory}))" "$ap_label directory padding"
	assert_zero_region "$ap_output" \
		"$((ap_trailer_offset + 64 + ${#ap_basename}))" \
		"$((48 - ${#ap_basename}))" "$ap_label basename padding"
	assert_zero_region "$ap_output" "$((ap_trailer_offset + 112))" 16 \
		"$ap_label future area"

	ap_prefix=$TEST_ROOT/prefix.$$
	dd if="$ap_output" of="$ap_prefix" bs=1 count="$ap_body_size" 2>/dev/null
	cmp -s "$ap_body" "$ap_prefix" ||
		fail "$ap_label changed bytes before the trailer"
	rm -f "$ap_prefix"
	pass "$ap_label"
}

run_helper() {
	rh_source=$1
	rh_destination=$2
	rh_log=$TEST_ROOT/helper.log
	if ! sh "$HELPER" "$rh_source" "$rh_destination" >"$rh_log" 2>&1; then
		sed 's/^/  /' "$rh_log" >&2
		fail "helper failed for $rh_source"
	fi
}

sha256_file() {
	if command -v shasum >/dev/null 2>&1; then
		shasum -a 256 "$1" | awk '{print $1}'
	else
		sha256sum "$1" | awk '{print $1}'
	fi
}

for test_tool in awk cmp dd gzip mkdir mv od rm sed touch unzip wc zip; do
	command -v "$test_tool" >/dev/null 2>&1 ||
		fail "required test tool not found: $test_tool"
done

mkdir -p "$TEST_ROOT"

# Raw .vgm, printable ASCII, normal .vgm stripping, and body preservation.
case_root=$TEST_ROOT/raw_ascii
mkdir -p "$case_root/inbox/Out Run"
raw_body=$case_root/inbox/Out\ Run/01_Magical\ Sound\ Shower.vgm
make_body "$raw_body"
run_helper "$case_root/inbox" "$case_root/out"
assert_prepared "raw ASCII .vgm" \
	"$case_root/out/Out Run/01_Magical Sound Shower.vgm" \
	"$raw_body" "Out Run" "01_Magical Sound Shower"

# Exact limits.
directory_32=12345678901234567890123456789012
basename_48=123456789012345678901234567890123456789012345678
case_root=$TEST_ROOT/exact_limits
mkdir -p "$case_root/inbox/$directory_32"
limit_body=$case_root/inbox/$directory_32/$basename_48.vgm
make_body "$limit_body"
run_helper "$case_root/inbox" "$case_root/out"
assert_prepared "32/48-character boundaries" \
	"$case_root/out/$directory_32/$basename_48.vgm" \
	"$limit_body" "$directory_32" "$basename_48"

# Truncation and uppercase .VGM stripping.
directory_long=12345678901234567890123456789012EXTRA
basename_long=123456789012345678901234567890123456789012345678EXTRA
case_root=$TEST_ROOT/truncate_upper
mkdir -p "$case_root/inbox/$directory_long"
truncate_body=$case_root/inbox/$directory_long/$basename_long.VGM
make_body "$truncate_body"
run_helper "$case_root/inbox" "$case_root/out"
assert_prepared "truncate and .VGM" \
	"$case_root/out/$directory_long/$basename_long.vgm" \
	"$truncate_body" "$directory_32" "$basename_48"

# Standalone VGZ expansion.
case_root=$TEST_ROOT/vgz
mkdir -p "$case_root/inbox/VGZ Game"
vgz_body=$case_root/vgz_body.vgm
make_body "$vgz_body"
gzip -c "$vgz_body" > "$case_root/inbox/VGZ Game/Compressed Track.vgz"
run_helper "$case_root/inbox" "$case_root/out"
assert_prepared "VGZ input" \
	"$case_root/out/VGZ Game/Compressed Track.vgm" \
	"$vgz_body" "VGZ Game" "Compressed Track"

# ZIP containing a VGM.
case_root=$TEST_ROOT/zip_vgm
mkdir -p "$case_root/inbox" "$case_root/archive/Zip Game"
zip_vgm_body=$case_root/archive/Zip\ Game/Zip\ Track.vgm
make_body "$zip_vgm_body"
(CDPATH= cd -- "$case_root/archive" &&
	zip -q "$case_root/inbox/Zip Collection.zip" "Zip Game/Zip Track.vgm")
run_helper "$case_root/inbox" "$case_root/out"
assert_prepared "ZIP VGM input" \
	"$case_root/out/Zip Collection/Zip Game/Zip Track.vgm" \
	"$zip_vgm_body" "Zip Game" "Zip Track"

# ZIP containing a VGZ.
case_root=$TEST_ROOT/zip_vgz
mkdir -p "$case_root/inbox" "$case_root/archive/Zip GZ Game"
zip_vgz_body=$case_root/zip_vgz_body.vgm
make_body "$zip_vgz_body"
gzip -c "$zip_vgz_body" > "$case_root/archive/Zip GZ Game/Zip Compressed.vgz"
(CDPATH= cd -- "$case_root/archive" &&
	zip -q "$case_root/inbox/Zip VGZ Collection.zip" \
	"Zip GZ Game/Zip Compressed.vgz")
run_helper "$case_root/inbox" "$case_root/out"
assert_prepared "ZIP VGZ input" \
	"$case_root/out/Zip VGZ Collection/Zip GZ Game/Zip Compressed.vgm" \
	"$zip_vgz_body" "Zip GZ Game" "Zip Compressed"

# A newer legacy cache file without metadata must not be skipped.
case_root=$TEST_ROOT/legacy_cache
mkdir -p "$case_root/inbox/Legacy Game" "$case_root/out/Legacy Game"
legacy_source=$case_root/inbox/Legacy\ Game/Legacy\ Track.vgm
legacy_output=$case_root/out/Legacy\ Game/Legacy\ Track.vgm
make_body "$legacy_source"
cp "$legacy_source" "$legacy_output"
touch -t 202607281200 "$legacy_source"
touch -t 202607281201 "$legacy_output"
run_helper "$case_root/inbox" "$case_root/out"
assert_prepared "legacy cache regeneration" "$legacy_output" \
	"$legacy_source" "Legacy Game" "Legacy Track"

# A valid existing trailer is replaced, not duplicated. A second run is
# byte-for-byte and size idempotent.
case_root=$TEST_ROOT/replace
mkdir -p "$case_root/first/inbox/Old Game"
replace_body=$case_root/first/inbox/Old\ Game/Old\ Track.vgm
make_body "$replace_body"
run_helper "$case_root/first/inbox" "$case_root/first/out"
first_prepared=$case_root/first/out/Old\ Game/Old\ Track.vgm
mkdir -p "$case_root/second/inbox/New Game"
replace_source=$case_root/second/inbox/New\ Game/New\ Track.vgm
cp "$first_prepared" "$replace_source"
run_helper "$case_root/second/inbox" "$case_root/second/out"
replace_output=$case_root/second/out/New\ Game/New\ Track.vgm
assert_prepared "valid trailer replacement" "$replace_output" \
	"$replace_body" "New Game" "New Track"
replace_size_before=$(file_size "$replace_output")
replace_hash_before=$(sha256_file "$replace_output")
run_helper "$case_root/second/inbox" "$case_root/second/out"
replace_size_after=$(file_size "$replace_output")
replace_hash_after=$(sha256_file "$replace_output")
assert_eq "$replace_size_before" "$replace_size_after" "double-run size"
assert_eq "$replace_hash_before" "$replace_hash_after" "double-run SHA-256"
pass "double-run idempotency"

# Trailer-like data with a bad magic is ordinary input data and is preserved.
case_root=$TEST_ROOT/invalid_magic
mkdir -p "$case_root/inbox/Magic Game"
invalid_magic_source=$case_root/inbox/Magic\ Game/Magic\ Track.vgm
cp "$first_prepared" "$invalid_magic_source"
invalid_magic_offset=$(($(file_size "$invalid_magic_source") - TRAILER_SIZE))
printf 'X' | dd of="$invalid_magic_source" bs=1 \
	seek="$invalid_magic_offset" conv=notrunc 2>/dev/null
run_helper "$case_root/inbox" "$case_root/out"
assert_prepared "invalid magic preserved" \
	"$case_root/out/Magic Game/Magic Track.vgm" \
	"$invalid_magic_source" "Magic Game" "Magic Track"

# An unknown version is not stripped.
case_root=$TEST_ROOT/unknown_version
mkdir -p "$case_root/inbox/Version Game"
unknown_version_source=$case_root/inbox/Version\ Game/Version\ Track.vgm
cp "$first_prepared" "$unknown_version_source"
unknown_version_offset=$(($(file_size "$unknown_version_source") - TRAILER_SIZE + 8))
printf '\002' | dd of="$unknown_version_source" bs=1 \
	seek="$unknown_version_offset" conv=notrunc 2>/dev/null
run_helper "$case_root/inbox" "$case_root/out"
assert_prepared "unknown version preserved" \
	"$case_root/out/Version Game/Version Track.vgm" \
	"$unknown_version_source" "Version Game" "Version Track"

# A version 1 trailer with an original-size mismatch is not stripped.
case_root=$TEST_ROOT/size_mismatch
mkdir -p "$case_root/inbox/Size Game"
size_mismatch_source=$case_root/inbox/Size\ Game/Size\ Track.vgm
cp "$first_prepared" "$size_mismatch_source"
size_mismatch_offset=$(($(file_size "$size_mismatch_source") - TRAILER_SIZE + 16))
printf '\000\000\000\000' | dd of="$size_mismatch_source" bs=1 \
	seek="$size_mismatch_offset" conv=notrunc 2>/dev/null
run_helper "$case_root/inbox" "$case_root/out"
assert_prepared "original-size mismatch preserved" \
	"$case_root/out/Size Game/Size Track.vgm" \
	"$size_mismatch_source" "Size Game" "Size Track"

# Each valid non-ASCII UTF-8 code point becomes one '?'.
case_root=$TEST_ROOT/non_ascii
mkdir -p "$case_root/inbox/Gáme 音"
non_ascii_source=$case_root/inbox/Gáme\ 音/01_曲_Tün.vgm
make_body "$non_ascii_source"
run_helper "$case_root/inbox" "$case_root/out"
assert_prepared "UTF-8 replacement" \
	"$case_root/out/Gáme 音/01_曲_Tün.vgm" \
	"$non_ascii_source" "G?me ?" "01_?_T?n"

# The physical 4 MiB limit includes the trailer.
case_root=$TEST_ROOT/size_limit
mkdir -p "$case_root/inbox/Limit Game"
limit_source=$case_root/inbox/Limit\ Game/Exact.vgm
dd if=/dev/zero of="$limit_source" bs=1 \
	count=$((MAX_PREPARED_SIZE - TRAILER_SIZE)) 2>/dev/null
run_helper "$case_root/inbox" "$case_root/out"
assert_prepared "exact 4 MiB prepared limit" \
	"$case_root/out/Limit Game/Exact.vgm" \
	"$limit_source" "Limit Game" "Exact"
assert_eq "$MAX_PREPARED_SIZE" \
	"$(file_size "$case_root/out/Limit Game/Exact.vgm")" \
	"exact maximum physical size"

oversize_source=$case_root/inbox/Limit\ Game/Too\ Large.vgm
dd if=/dev/zero of="$oversize_source" bs=1 \
	count=$((MAX_PREPARED_SIZE - TRAILER_SIZE + 1)) 2>/dev/null
if sh "$HELPER" "$oversize_source" "$case_root/oversize_out" \
	>"$TEST_ROOT/oversize.log" 2>&1; then
	fail "oversize input unexpectedly succeeded"
fi
[ ! -e "$case_root/oversize_out/Too Large/Too Large.vgm" ] ||
	fail "oversize helper left a final output"
pass "physical-size overflow rejection"

echo "All $tests_run helper metadata tests passed."
