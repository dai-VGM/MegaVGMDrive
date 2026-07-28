#!/bin/sh
#
# Import loose .vgm/.vgz files and .zip archives into the VGM_MD cache.
#
# Usage:
#   scripts/vgm_md_import.sh [SRC] [DST_DIR]
#
# Defaults:
#   SRC=/media/fat/VGM_MD/inbox
#   DST_DIR=/media/fat/VGM_MD/vgm_cache
#
# Windows/Samba workflow:
#   Copy zip/vgz/vgm files to:
#     \\mister\sdcard\VGM_MD\inbox
#   Then run on MiSTer:
#     sh /media/fat/Scripts/vgm_md_import.sh
#
# The FPGA core loads plain .vgm files from the cache. It does not natively
# load .vgz/.zip and does not do gzip decompression in hardware.
#
# Prepared outputs end with a MegaVGMDrive-specific 128-byte display-name
# trailer. See docs/prepared_vgm_metadata.md for the binary format.

set -u

SRC=${1:-/media/fat/VGM_MD/inbox}
DST=${2:-/media/fat/VGM_MD/vgm_cache}
METADATA_TRAILER_SIZE=128
MAX_PREPARED_VGM_SIZE=4194304

# Work byte-by-byte regardless of the host locale. UTF-8 decoding is handled
# explicitly by normalize_name_ascii below.
LC_ALL=C
export LC_ALL

if [ ! -d "$SRC" ] && [ ! -f "$SRC" ]; then
	echo "source not found: $SRC" >&2
	exit 1
fi

if ! command -v gzip >/dev/null 2>&1; then
	echo "gzip command not found" >&2
	exit 1
fi

if ! command -v unzip >/dev/null 2>&1; then
	echo "unzip command not found" >&2
	exit 1
fi

for required_tool in awk od dd wc cp mv; do
	if ! command -v "$required_tool" >/dev/null 2>&1; then
		echo "$required_tool command not found" >&2
		exit 1
	fi
done

if ! mkdir -p "$DST"; then
	echo "failed to create destination directory: $DST" >&2
	exit 1
fi

collapse_duplicate_top_dir() {
	rel=$1

	first_dir=${rel%%/*}
	after_first=${rel#*/}
	if [ "$after_first" != "$rel" ]; then
		second_dir=${after_first%%/*}
		after_second=${after_first#*/}
		if [ "$after_second" != "$after_first" ] && [ "$first_dir" = "$second_dir" ]; then
			rel=$first_dir/$after_second
		fi
	fi

	printf '%s\n' "$rel"
}

strip_vgm_ext() {
	name=$1

	case "$name" in
		*.[vV][gG][mM]) name=${name%.[vV][gG][mM]} ;;
		*.[vV][gG][zZ]) name=${name%.[vV][gG][zZ]} ;;
		*.[zZ][iI][pP]) name=${name%.[zZ][iI][pP]} ;;
	esac

	printf '%s\n' "$name"
}

basename_no_vgm_ext() {
	path=$1
	base=${path%/}
	base=${base##*/}
	strip_vgm_ext "$base"
}

is_inbox_dir_name() {
	case "$1" in
		[iI][nN][bB][oO][xX]) return 0 ;;
		*) return 1 ;;
	esac
}

strip_duplicate_collection_prefix() {
	collection=$1
	rel=$2

	case "$rel" in
		"$collection"/*) rel=${rel#"$collection"/} ;;
	esac

	printf '%s\n' "$rel"
}

vgm_dst_for_rel() {
	collection=$1
	rel=$(collapse_duplicate_top_dir "$2")
	rel=$(strip_duplicate_collection_prefix "$collection" "$rel")

	case "$rel" in
		*.[vV][gG][mM]) rel_no_ext=${rel%.[vV][gG][mM]} ;;
		*.[vV][gG][zZ]) rel_no_ext=${rel%.[vV][gG][zZ]} ;;
		*) rel_no_ext=$rel ;;
	esac

	printf '%s/%s/%s.vgm\n' "$DST" "$collection" "$rel_no_ext"
}

file_size_bytes() {
	fsb_size=$(wc -c < "$1") || return 1
	printf '%d\n' "$((fsb_size + 0))"
}

metadata_trailer_valid() {
	mtv_file=$1
	mtv_file_size=$(file_size_bytes "$mtv_file") || return 1
	if [ "$mtv_file_size" -lt "$METADATA_TRAILER_SIZE" ]; then
		return 1
	fi

	mtv_offset=$((mtv_file_size - METADATA_TRAILER_SIZE))
	# Read the fixed header through od so this works on both macOS and the
	# BusyBox-style MiSTer userspace without stat-specific options.
	set -- $(dd if="$mtv_file" bs=1 skip="$mtv_offset" count=20 2>/dev/null |
		od -An -v -tu1)
	if [ "$#" -ne 20 ]; then
		return 1
	fi

	# "MVGMTTL\0", version 1, flags limited to bits 0..1, bounded lengths,
	# trailer size 0x0080, and zero reserved bytes at 0x0e..0x0f.
	if [ "$1" -ne 77 ] || [ "$2" -ne 86 ] ||
	   [ "$3" -ne 71 ] || [ "$4" -ne 77 ] ||
	   [ "$5" -ne 84 ] || [ "$6" -ne 84 ] ||
	   [ "$7" -ne 76 ] || [ "$8" -ne 0 ] ||
	   [ "$9" -ne 1 ] || [ "${10}" -gt 3 ] ||
	   [ "${11}" -gt 32 ] || [ "${12}" -gt 48 ] ||
	   [ "${13}" -ne 128 ] || [ "${14}" -ne 0 ] ||
	   [ "${15}" -ne 0 ] || [ "${16}" -ne 0 ]; then
		return 1
	fi

	mtv_original_size=$((
		${17} +
		(${18} * 256) +
		(${19} * 65536) +
		(${20} * 16777216)
	))
	[ "$mtv_original_size" -eq "$mtv_offset" ]
}

copy_file_prefix() {
	cfp_input=$1
	cfp_output=$2
	cfp_count=$3
	cfp_blocks=$((cfp_count / 4096))
	cfp_remainder=$((cfp_count % 4096))

	dd if="$cfp_input" of="$cfp_output" bs=4096 \
		count="$cfp_blocks" 2>/dev/null || return 1
	if [ "$cfp_remainder" -ne 0 ]; then
		dd if="$cfp_input" bs=1 skip=$((cfp_blocks * 4096)) \
			count="$cfp_remainder" 2>/dev/null >> "$cfp_output" ||
			return 1
	fi
}

normalize_name_ascii() {
	nna_value=$1
	nna_limit=$2
	nna_output=$3

	# od makes the input independent of awk's locale/string handling. Valid
	# multi-byte UTF-8 sequences are consumed as one code point and become one
	# '?'. Invalid leading/continuation bytes also become safe '?' characters.
	printf '%s' "$nna_value" |
		od -An -v -tu1 |
		awk -v limit="$nna_limit" '
			function emit(byte_value) {
				if (output_count < limit) {
					printf "%c", byte_value
					output_count++
				}
			}
			BEGIN {
				output_count = 0
				continuations = 0
			}
			{
				for (i = 1; i <= NF; i++) {
					byte_value = $i + 0

					if (continuations > 0) {
						if (byte_value >= 128 && byte_value <= 191) {
							continuations--
							if (continuations == 0) emit(63)
							continue
						}
						emit(63)
						continuations = 0
					}

					if (byte_value >= 32 && byte_value <= 126) {
						emit(byte_value)
					} else if (byte_value >= 194 && byte_value <= 223) {
						continuations = 1
					} else if (byte_value >= 224 && byte_value <= 239) {
						continuations = 2
					} else if (byte_value >= 240 && byte_value <= 244) {
						continuations = 3
					} else {
						emit(63)
					}
				}
			}
			END {
				if (continuations > 0) emit(63)
			}
		' > "$nna_output"
}

pad_file_with_zeros() {
	pfz_file=$1
	pfz_count=$2
	if [ "$pfz_count" -gt 0 ]; then
		dd if=/dev/zero bs=1 count="$pfz_count" 2>/dev/null >> "$pfz_file"
	fi
}

append_display_metadata() {
	adm_file=$1
	adm_dst_file=$2
	adm_body_file=$adm_file.body.$$
	adm_trailer_file=$adm_file.trailer.$$
	adm_directory_file=$adm_file.directory.$$
	adm_basename_file=$adm_file.basename.$$

	if metadata_trailer_valid "$adm_file"; then
		adm_file_size=$(file_size_bytes "$adm_file") || return 1
		adm_body_size=$((adm_file_size - METADATA_TRAILER_SIZE))
		if ! copy_file_prefix "$adm_file" "$adm_body_file" "$adm_body_size"; then
			rm -f "$adm_body_file"
			return 1
		fi
		if ! mv "$adm_body_file" "$adm_file"; then
			rm -f "$adm_body_file"
			return 1
		fi
	fi

	adm_original_size=$(file_size_bytes "$adm_file") || return 1
	adm_prepared_size=$((adm_original_size + METADATA_TRAILER_SIZE))
	if [ "$adm_prepared_size" -gt "$MAX_PREPARED_VGM_SIZE" ]; then
		echo "prepared VGM exceeds ${MAX_PREPARED_VGM_SIZE} bytes: $adm_dst_file" >&2
		return 1
	fi

	adm_parent=${adm_dst_file%/*}
	if [ "$adm_parent" = "$adm_dst_file" ]; then
		adm_directory=
	else
		adm_directory=${adm_parent##*/}
	fi
	adm_basename=${adm_dst_file##*/}
	adm_basename=$(strip_vgm_ext "$adm_basename")

	if ! normalize_name_ascii "$adm_directory" 32 "$adm_directory_file"; then
		rm -f "$adm_directory_file" "$adm_basename_file" "$adm_trailer_file"
		return 1
	fi
	if ! normalize_name_ascii "$adm_basename" 48 "$adm_basename_file"; then
		rm -f "$adm_directory_file" "$adm_basename_file" "$adm_trailer_file"
		return 1
	fi

	adm_directory_length=$(file_size_bytes "$adm_directory_file") || return 1
	adm_basename_length=$(file_size_bytes "$adm_basename_file") || return 1
	adm_flags=0
	if [ "$adm_directory_length" -ne 0 ]; then
		adm_flags=$((adm_flags | 1))
	fi
	if [ "$adm_basename_length" -ne 0 ]; then
		adm_flags=$((adm_flags | 2))
	fi

	if ! pad_file_with_zeros "$adm_directory_file" $((32 - adm_directory_length)); then
		rm -f "$adm_directory_file" "$adm_basename_file" "$adm_trailer_file"
		return 1
	fi
	if ! pad_file_with_zeros "$adm_basename_file" $((48 - adm_basename_length)); then
		rm -f "$adm_directory_file" "$adm_basename_file" "$adm_trailer_file"
		return 1
	fi

	awk -v flags="$adm_flags" \
		-v directory_length="$adm_directory_length" \
		-v basename_length="$adm_basename_length" \
		-v original_size="$adm_original_size" '
		BEGIN {
			printf "MVGMTTL%c", 0
			printf "%c%c%c%c", 1, flags, directory_length, basename_length
			printf "%c%c%c%c", 128, 0, 0, 0
			printf "%c%c%c%c",
				original_size % 256,
				int(original_size / 256) % 256,
				int(original_size / 65536) % 256,
				int(original_size / 16777216) % 256
			for (i = 0; i < 12; i++) printf "%c", 0
		}
	' > "$adm_trailer_file" || {
		rm -f "$adm_directory_file" "$adm_basename_file" "$adm_trailer_file"
		return 1
	}

	cat "$adm_directory_file" "$adm_basename_file" >> "$adm_trailer_file" || {
		rm -f "$adm_directory_file" "$adm_basename_file" "$adm_trailer_file"
		return 1
	}
	pad_file_with_zeros "$adm_trailer_file" 16 || {
		rm -f "$adm_directory_file" "$adm_basename_file" "$adm_trailer_file"
		return 1
	}

	adm_trailer_size=$(file_size_bytes "$adm_trailer_file") || return 1
	if [ "$adm_trailer_size" -ne "$METADATA_TRAILER_SIZE" ]; then
		echo "internal metadata trailer size error: $adm_trailer_size" >&2
		rm -f "$adm_directory_file" "$adm_basename_file" "$adm_trailer_file"
		return 1
	fi

	if ! cat "$adm_trailer_file" >> "$adm_file"; then
		rm -f "$adm_directory_file" "$adm_basename_file" "$adm_trailer_file"
		return 1
	fi
	rm -f "$adm_directory_file" "$adm_basename_file" "$adm_trailer_file"
}

prepared_cache_is_current() {
	pcc_dst_file=$1
	pcc_source_file=$2
	[ -f "$pcc_dst_file" ] &&
		[ "$pcc_dst_file" -nt "$pcc_source_file" ] &&
		metadata_trailer_valid "$pcc_dst_file"
}

prepare_tmp() {
	dst_file=$1
	dst_dir=${dst_file%/*}
	tmp_file=$dst_file.tmp.$$

	if ! mkdir -p "$dst_dir"; then
		echo "failed to create destination directory: $dst_dir" >&2
		return 1
	fi

	rm -f "$tmp_file"
	printf '%s\n' "$tmp_file"
}

finish_tmp() {
	tmp_file=$1
	dst_file=$2

	if mv "$tmp_file" "$dst_file"; then
		echo "wrote: $dst_file"
		return 0
	fi

	echo "failed to move temp file into place: $dst_file" >&2
	rm -f "$tmp_file"
	return 1
}

finish_prepared_tmp() {
	fpt_tmp_file=$1
	fpt_dst_file=$2

	if ! append_display_metadata "$fpt_tmp_file" "$fpt_dst_file"; then
		echo "failed to add display metadata: $fpt_dst_file" >&2
		rm -f "$fpt_tmp_file" "$fpt_tmp_file".body.$$ \
			"$fpt_tmp_file".trailer.$$ "$fpt_tmp_file".directory.$$ \
			"$fpt_tmp_file".basename.$$
		return 1
	fi

	finish_tmp "$fpt_tmp_file" "$fpt_dst_file"
}

copy_vgm_file() {
	src_file=$1
	collection=$2
	rel=$3
	dst_file=$(vgm_dst_for_rel "$collection" "$rel")

	if prepared_cache_is_current "$dst_file" "$src_file"; then
		echo "skip: $dst_file"
		return 0
	fi

	tmp_file=$(prepare_tmp "$dst_file") || return 1
	if cp "$src_file" "$tmp_file"; then
		finish_prepared_tmp "$tmp_file" "$dst_file"
	else
		echo "failed to copy: $src_file" >&2
		rm -f "$tmp_file"
		return 1
	fi
}

expand_vgz_file() {
	src_file=$1
	collection=$2
	rel=$3
	dst_file=$(vgm_dst_for_rel "$collection" "$rel")

	if prepared_cache_is_current "$dst_file" "$src_file"; then
		echo "skip: $dst_file"
		return 0
	fi

	tmp_file=$(prepare_tmp "$dst_file") || return 1
	if gzip -dc "$src_file" > "$tmp_file"; then
		finish_prepared_tmp "$tmp_file" "$dst_file"
	else
		echo "failed to expand: $src_file" >&2
		rm -f "$tmp_file"
		return 1
	fi
}

copy_zip_vgm_entry() {
	zip_file=$1
	collection=$2
	entry=$3
	dst_file=$(vgm_dst_for_rel "$collection" "$entry")

	if prepared_cache_is_current "$dst_file" "$zip_file"; then
		echo "skip: $dst_file"
		return 0
	fi

	tmp_file=$(prepare_tmp "$dst_file") || return 1
	if unzip -p "$zip_file" "$entry" > "$tmp_file"; then
		finish_prepared_tmp "$tmp_file" "$dst_file"
	else
		echo "failed to extract zip entry: $zip_file :: $entry" >&2
		rm -f "$tmp_file"
		return 1
	fi
}

expand_zip_vgz_entry() {
	zip_file=$1
	collection=$2
	entry=$3
	dst_file=$(vgm_dst_for_rel "$collection" "$entry")

	if prepared_cache_is_current "$dst_file" "$zip_file"; then
		echo "skip: $dst_file"
		return 0
	fi

	tmp_file=$(prepare_tmp "$dst_file") || return 1
	if unzip -p "$zip_file" "$entry" | gzip -dc > "$tmp_file"; then
		finish_prepared_tmp "$tmp_file" "$dst_file"
	else
		echo "failed to expand zip vgz entry: $zip_file :: $entry" >&2
		rm -f "$tmp_file"
		return 1
	fi
}

import_zip_file() {
	zip_file=$1
	collection=$2
	entries=$(unzip -Z1 "$zip_file") || {
		echo "failed to list zip file: $zip_file" >&2
		return 1
	}

	zip_status=0
	while IFS= read -r entry; do
		case "$entry" in
			''|*/) continue ;;
			*.[vV][gG][mM])
				copy_zip_vgm_entry "$zip_file" "$collection" "$entry" || zip_status=1
				;;
			*.[vV][gG][zZ])
				expand_zip_vgz_entry "$zip_file" "$collection" "$entry" || zip_status=1
				;;
			*) ;;
		esac
	done <<EOF
$entries
EOF

	return "$zip_status"
}

export SRC
export DST

status=0
find_list=${TMPDIR:-/tmp}/vgm_md_import_find.$$.list
trap 'rm -f "$find_list"' EXIT HUP INT TERM

if [ -f "$SRC" ]; then
	printf '%s\n' "$SRC" > "$find_list" || {
		echo "failed to prepare source file list: $SRC" >&2
		exit 1
	}
else
	find "$SRC" -type f \( \
		-name '*.vgm' -o -name '*.VGM' -o \
		-name '*.vgz' -o -name '*.VGZ' -o \
		-name '*.zip' -o -name '*.ZIP' \
	\) > "$find_list" || {
		echo "failed to scan source directory: $SRC" >&2
		exit 1
	}
fi

while IFS= read -r src_file; do
	if [ -f "$SRC" ]; then
		collection=$(basename_no_vgm_ext "$SRC")
		rel=${src_file##*/}
	else
		src_collection=$(basename_no_vgm_ext "$SRC")
		rel=${src_file#"$SRC"/}
		if [ "$rel" = "$src_file" ]; then
			rel=${src_file##*/}
		fi

		if is_inbox_dir_name "$src_collection"; then
			case "$rel" in
				*/*)
					collection=${rel%%/*}
					rel=${rel#*/}
					;;
				*)
					collection=$(basename_no_vgm_ext "$rel")
					;;
			esac
		else
			collection=$src_collection
		fi
	fi

	case "$src_file" in
		*.[vV][gG][mM])
			copy_vgm_file "$src_file" "$collection" "$rel" || status=1
			;;
		*.[vV][gG][zZ])
			expand_vgz_file "$src_file" "$collection" "$rel" || status=1
			;;
		*.[zZ][iI][pP])
			import_zip_file "$src_file" "$collection" || status=1
			;;
	esac
done < "$find_list"

exit "$status"
