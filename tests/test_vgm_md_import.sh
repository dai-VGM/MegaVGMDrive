#!/bin/sh

set -eu

LC_ALL=C
export LC_ALL

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
HELPER=$REPO_ROOT/scripts/vgm_md_import.sh
TEST_ROOT=${TMPDIR:-/tmp}/vgm_md_import_test.$$
TRAILER_SIZE=128
MAX_PREPARED_SIZE=8388608
MAX_ORIGINAL_SIZE=$((MAX_PREPARED_SIZE - TRAILER_SIZE))
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

make_sized_body() {
	msb_file=$1
	msb_size=$2
	dd if=/dev/zero of="$msb_file" bs=1 count="$msb_size" 2>/dev/null
	printf 'Vgm ' | dd of="$msb_file" bs=1 conv=notrunc 2>/dev/null
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
	ap_actual_trailer_size=$((ap_output_size - ap_body_size))
	assert_eq "$TRAILER_SIZE" "$ap_actual_trailer_size" \
		"$ap_label actual trailer size"
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
	assert_eq "$(sha256_file "$ap_body")" "$(sha256_file "$ap_prefix")" \
		"$ap_label body SHA-256"
	rm -f "$ap_prefix"
	pass "$ap_label"
}

sha256_file() {
	if command -v shasum >/dev/null 2>&1; then
		shasum -a 256 < "$1" | awk '{print $1}'
	else
		sha256sum < "$1" | awk '{print $1}'
	fi
}

write_output_manifest() {
	wom_directory=$1
	wom_output=$2

	: > "$wom_output"
	if [ ! -d "$wom_directory" ]; then
		return 0
	fi
	find "$wom_directory" -type f -print |
		LC_ALL=C sort |
		while IFS= read -r wom_file; do
			printf '%s|%s|%s\n' \
				"$wom_file" \
				"$(file_size "$wom_file")" \
				"$(sha256_file "$wom_file")"
		done > "$wom_output"
}

run_helper() {
	rh_source=$1
	rh_destination=$2
	rh_awk_path=${3:-}
	rh_log=$TEST_ROOT/helper.log
	rh_before=$TEST_ROOT/helper.before.$$
	rh_after=$TEST_ROOT/helper.after.$$

	if [ -n "$rh_awk_path" ]; then
		if PATH="$rh_awk_path:$PATH" sh "$HELPER" \
			"$rh_source" "$rh_destination" >"$rh_log" 2>&1; then
			rh_status=0
		else
			rh_status=$?
		fi
	else
		if sh "$HELPER" "$rh_source" "$rh_destination" >"$rh_log" 2>&1; then
			rh_status=0
		else
			rh_status=$?
		fi
	fi
	if [ "$rh_status" -ne 0 ]; then
		sed 's/^/  /' "$rh_log" >&2
		fail "helper failed for $rh_source"
	fi

	write_output_manifest "$rh_destination" "$rh_before"
	if [ -n "$rh_awk_path" ]; then
		if PATH="$rh_awk_path:$PATH" sh "$HELPER" \
			"$rh_source" "$rh_destination" >"$rh_log" 2>&1; then
			rh_status=0
		else
			rh_status=$?
		fi
	else
		if sh "$HELPER" "$rh_source" "$rh_destination" >"$rh_log" 2>&1; then
			rh_status=0
		else
			rh_status=$?
		fi
	fi
	if [ "$rh_status" -ne 0 ]; then
		sed 's/^/  /' "$rh_log" >&2
		fail "second helper run failed for $rh_source"
	fi
	write_output_manifest "$rh_destination" "$rh_after"
	cmp -s "$rh_before" "$rh_after" ||
		fail "second helper run changed output size or SHA-256 for $rh_source"
	rm -f "$rh_before" "$rh_after"
}

for test_tool in awk cmp dd find grep gzip mkdir mv od rm sed sort touch tr unzip wc zip; do
	command -v "$test_tool" >/dev/null 2>&1 ||
		fail "required test tool not found: $test_tool"
done
if ! command -v shasum >/dev/null 2>&1 &&
   ! command -v sha256sum >/dev/null 2>&1; then
	fail "shasum or sha256sum is required"
fi

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

# Info-ZIP interprets entry operands as wildcard patterns. Every path returned
# by `unzip -Z1` must instead be extracted literally, including nested paths,
# whitespace, quotes, parentheses, brackets, '*'/'?', and backslashes.
case_root=$TEST_ROOT/zip_literal_names
mkdir -p "$case_root/inbox" "$case_root/archive/Special [Set] (Live)"
literal_vgm_rel="Special [Set] (Live)/01 O'Brien [Intro] * ? \\ Mix.vgm"
literal_vgz_rel="Special [Set] (Live)/02 O'Brien [Voice] * ? \\ Mix.vgz"
literal_vgm_body=$case_root/archive/$literal_vgm_rel
literal_vgz_body=$case_root/literal_vgz_body.vgm
make_body "$literal_vgm_body" 317
make_body "$literal_vgz_body" 509
gzip -c "$literal_vgz_body" > "$case_root/archive/$literal_vgz_rel"
(CDPATH= cd -- "$case_root/archive" &&
	zip -q "$case_root/inbox/Literal [Archive].zip" \
		"$literal_vgm_rel" "$literal_vgz_rel")
run_helper "$case_root/inbox" "$case_root/out"
assert_prepared "ZIP literal-name VGM" \
	"$case_root/out/Literal [Archive]/${literal_vgm_rel%.[vV][gG][mM]}.vgm" \
	"$literal_vgm_body" "Special [Set] (Live)" \
	"01 O'Brien [Intro] * ? \\ Mix"
assert_prepared "ZIP literal-name VGZ" \
	"$case_root/out/Literal [Archive]/${literal_vgz_rel%.[vV][gG][zZ]}.vgm" \
	"$literal_vgz_body" "Special [Set] (Live)" \
	"02 O'Brien [Voice] * ? \\ Mix"
if find "$case_root/out" -type f -name '*.tmp.*' -print |
	grep . >/dev/null 2>&1; then
	fail "literal ZIP extraction left a temporary file"
fi
pass "ZIP literal-name cleanup"

# A bad VGZ body must fail without replacing an existing destination or
# leaving either the extracted VGZ or destination-side temporary file behind.
case_root=$TEST_ROOT/zip_bad_vgz_cleanup
mkdir -p "$case_root/inbox" "$case_root/archive/Bad [Set]" \
	"$case_root/out/Bad [Archive]/Bad [Set]"
bad_vgz_rel='Bad [Set]/03 Bad [Voice].vgz'
printf 'not a gzip stream\n' > "$case_root/archive/$bad_vgz_rel"
(CDPATH= cd -- "$case_root/archive" &&
	zip -q "$case_root/inbox/Bad [Archive].zip" "$bad_vgz_rel")
bad_vgz_output="$case_root/out/Bad [Archive]/Bad [Set]/03 Bad [Voice].vgm"
printf 'existing destination remains intact\n' > "$bad_vgz_output"
bad_vgz_existing_hash=$(sha256_file "$bad_vgz_output")
if sh "$HELPER" "$case_root/inbox/Bad [Archive].zip" "$case_root/out" \
	>"$TEST_ROOT/bad_vgz.log" 2>&1; then
	fail "bad ZIP VGZ unexpectedly succeeded"
fi
grep -F "failed to expand zip vgz entry:" "$TEST_ROOT/bad_vgz.log" >/dev/null ||
	fail "bad ZIP VGZ did not report decompression failure"
assert_eq "$bad_vgz_existing_hash" "$(sha256_file "$bad_vgz_output")" \
	"bad ZIP VGZ preserves existing destination"
if find "$case_root/out" -type f \( -name '*.tmp.*' -o -name '*.vgz' \) -print |
	grep . >/dev/null 2>&1; then
	fail "bad ZIP VGZ left an extracted or destination-side temporary file"
fi
pass "failed ZIP VGZ cleanup preserves existing output"

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

# Reproduce the utility behavior that caused 110/111-byte trailers in real
# use. This wrapper removes every NUL emitted by awk. Metadata generation must
# still work because binary bytes must never pass through awk.
nul_drop_bin=$TEST_ROOT/nul_drop_bin
mkdir -p "$nul_drop_bin"
REAL_AWK_FOR_METADATA_TEST=$(command -v awk)
export REAL_AWK_FOR_METADATA_TEST
printf '%s\n' \
	'#!/bin/sh' \
	'"$REAL_AWK_FOR_METADATA_TEST" "$@" | tr -d "\\000"' \
	> "$nul_drop_bin/awk"
chmod +x "$nul_drop_bin/awk"

# A 260-byte original-size field contains two NUL bytes. Together with the
# fixed zero fields, the old awk path lost 18 bytes and produced 110.
case_root=$TEST_ROOT/nul_drop_110
mkdir -p "$case_root/inbox/Nul Drop Short"
nul_drop_110_body=$case_root/inbox/Nul\ Drop\ Short/short_case.vgm
make_body "$nul_drop_110_body" 260
run_helper "$case_root/inbox" "$case_root/out" "$nul_drop_bin"
assert_prepared "110-byte NUL-drop regression" \
	"$case_root/out/Nul Drop Short/short_case.vgm" \
	"$nul_drop_110_body" "Nul Drop Short" "short_case"

# A 70,000-byte original-size field contains one NUL byte. The old path lost
# 17 bytes in total and produced 111.
case_root=$TEST_ROOT/nul_drop_111
mkdir -p "$case_root/inbox/Nul Drop Longer"
nul_drop_111_body=$case_root/inbox/Nul\ Drop\ Longer/long_case.vgm
make_body "$nul_drop_111_body" 70000
run_helper "$case_root/inbox" "$case_root/out" "$nul_drop_bin"
assert_prepared "111-byte NUL-drop regression" \
	"$case_root/out/Nul Drop Longer/long_case.vgm" \
	"$nul_drop_111_body" "Nul Drop Longer" "long_case"

# The production 23-bit byte-address contract accepts an exact 8 MiB
# physical prepared file. The 128-byte trailer is included in that limit.
case_root=$TEST_ROOT/size_boundaries
mkdir -p "$case_root/inbox/Limit Game"

below_4m_source=$case_root/inbox/Limit\ Game/Below\ 4MiB.vgm
make_sized_body "$below_4m_source" $((4194304 - TRAILER_SIZE - 1))
run_helper "$below_4m_source" "$case_root/below_4m_out"
below_4m_output=$case_root/below_4m_out/Below\ 4MiB/Below\ 4MiB.vgm
assert_prepared "prepared file below 4 MiB" "$below_4m_output" \
	"$below_4m_source" "Below 4MiB" "Below 4MiB"

original_4m_source=$case_root/inbox/Limit\ Game/Original\ 4MiB.vgm
make_sized_body "$original_4m_source" 4194304
run_helper "$original_4m_source" "$case_root/original_4m_out"
original_4m_output=$case_root/original_4m_out/Original\ 4MiB/Original\ 4MiB.vgm
assert_prepared "exact 4 MiB original body" "$original_4m_output" \
	"$original_4m_source" "Original 4MiB" "Original 4MiB"
assert_eq "4194432" "$(file_size "$original_4m_output")" \
	"4 MiB body prepared physical size"

splash_size=4613734
splash_source=$case_root/inbox/Limit\ Game/02\ -\ Splash\ Wave.vgm
make_sized_body "$splash_source" "$splash_size"
run_helper "$splash_source" "$case_root/splash_out"
splash_output=$case_root/splash_out/02\ -\ Splash\ Wave/02\ -\ Splash\ Wave.vgm
assert_prepared "4.4 MB Splash Wave equivalent" "$splash_output" \
	"$splash_source" "02 - Splash Wave" "02 - Splash Wave"
assert_eq "$((splash_size + TRAILER_SIZE))" "$(file_size "$splash_output")" \
	"Splash Wave equivalent physical size"

max_source=$case_root/inbox/Limit\ Game/Maximum.vgm
make_sized_body "$max_source" "$MAX_ORIGINAL_SIZE"
run_helper "$max_source" "$case_root/max_out"
max_output=$case_root/max_out/Maximum/Maximum.vgm
assert_prepared "maximum original body" "$max_output" \
	"$max_source" "Maximum" "Maximum"
assert_eq "$MAX_PREPARED_SIZE" "$(file_size "$max_output")" \
	"exact maximum prepared physical size"
pass "exact 8 MiB prepared limit"

# A valid near-limit trailer is stripped and replaced without growing the
# file. The helper's own second-run check also proves size/hash idempotency.
near_trailer_root=$TEST_ROOT/near_limit_existing_trailer
mkdir -p "$near_trailer_root/inbox/Near Limit"
near_trailer_source=$near_trailer_root/inbox/Near\ Limit/Maximum.vgm
cp "$max_output" "$near_trailer_source"
near_input_size=$(file_size "$near_trailer_source")
run_helper "$near_trailer_root/inbox" "$near_trailer_root/out"
near_trailer_output=$near_trailer_root/out/Near\ Limit/Maximum.vgm
assert_prepared "near-limit valid trailer replacement" \
	"$near_trailer_output" "$max_source" "Near Limit" "Maximum"
assert_eq "$near_input_size" "$(file_size "$near_trailer_output")" \
	"near-limit replacement size"
near_hash_before=$(sha256_file "$near_trailer_output")
run_helper "$near_trailer_root/inbox" "$near_trailer_root/out"
assert_eq "$near_hash_before" "$(sha256_file "$near_trailer_output")" \
	"near-limit repeated conversion SHA-256"
pass "near-limit repeated conversion is size/hash idempotent"

oversize_one_source=$case_root/inbox/Limit\ Game/Too\ Large\ By\ One.vgm
make_sized_body "$oversize_one_source" $((MAX_ORIGINAL_SIZE + 1))
if sh "$HELPER" "$oversize_one_source" "$case_root/oversize_one_out" \
	>"$TEST_ROOT/oversize_one.log" 2>&1; then
	fail "one-byte-over input unexpectedly succeeded"
fi
grep -F "prepared VGM size $((MAX_PREPARED_SIZE + 1)) bytes exceeds maximum supported size $MAX_PREPARED_SIZE bytes" \
	"$TEST_ROOT/oversize_one.log" >/dev/null ||
	fail "one-byte-over error does not report actual and maximum sizes"
[ ! -e "$case_root/oversize_one_out/Too Large By One/Too Large By One.vgm" ] ||
	fail "one-byte-over helper left a final output"
pass "one-byte physical-size overflow rejection"

oversize_128_source=$case_root/inbox/Limit\ Game/Too\ Large\ By\ 128.vgm
make_sized_body "$oversize_128_source" $((MAX_ORIGINAL_SIZE + 128))
if sh "$HELPER" "$oversize_128_source" "$case_root/oversize_128_out" \
	>"$TEST_ROOT/oversize_128.log" 2>&1; then
	fail "128-byte-over input unexpectedly succeeded"
fi
grep -F "prepared VGM size $((MAX_PREPARED_SIZE + 128)) bytes exceeds maximum supported size $MAX_PREPARED_SIZE bytes" \
	"$TEST_ROOT/oversize_128.log" >/dev/null ||
	fail "128-byte-over error does not report actual and maximum sizes"
[ ! -e "$case_root/oversize_128_out/Too Large By 128/Too Large By 128.vgm" ] ||
	fail "128-byte-over helper left a final output"
pass "128-byte physical-size overflow rejection"

mkdir -p "$case_root/oversize_one_out/Too Large By One"
oversize_existing=$case_root/oversize_one_out/Too\ Large\ By\ One/Too\ Large\ By\ One.vgm
printf 'existing destination remains intact\n' > "$oversize_existing"
oversize_existing_hash=$(sha256_file "$oversize_existing")
if sh "$HELPER" "$oversize_one_source" "$case_root/oversize_one_out" \
	>"$TEST_ROOT/oversize_existing.log" 2>&1; then
	fail "oversize input with an existing destination unexpectedly succeeded"
fi
assert_eq "$oversize_existing_hash" "$(sha256_file "$oversize_existing")" \
	"failed conversion preserves existing destination"
if find "$case_root/oversize_one_out" -type f -name '*.tmp.*' -print |
	grep . >/dev/null 2>&1; then
	fail "failed conversion left a destination-side temporary file"
fi
pass "atomic failure preserves existing output"

echo "All $tests_run helper metadata tests passed."
