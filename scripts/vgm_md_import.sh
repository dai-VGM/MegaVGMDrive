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

set -u

SRC=${1:-/media/fat/VGM_MD/inbox}
DST=${2:-/media/fat/VGM_MD/vgm_cache}

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

copy_vgm_file() {
	src_file=$1
	collection=$2
	rel=$3
	dst_file=$(vgm_dst_for_rel "$collection" "$rel")

	if [ -f "$dst_file" ] && [ "$dst_file" -nt "$src_file" ]; then
		echo "skip: $dst_file"
		return 0
	fi

	tmp_file=$(prepare_tmp "$dst_file") || return 1
	if cp "$src_file" "$tmp_file"; then
		finish_tmp "$tmp_file" "$dst_file"
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

	if [ -f "$dst_file" ] && [ "$dst_file" -nt "$src_file" ]; then
		echo "skip: $dst_file"
		return 0
	fi

	tmp_file=$(prepare_tmp "$dst_file") || return 1
	if gzip -dc "$src_file" > "$tmp_file"; then
		finish_tmp "$tmp_file" "$dst_file"
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

	if [ -f "$dst_file" ] && [ "$dst_file" -nt "$zip_file" ]; then
		echo "skip: $dst_file"
		return 0
	fi

	tmp_file=$(prepare_tmp "$dst_file") || return 1
	if unzip -p "$zip_file" "$entry" > "$tmp_file"; then
		finish_tmp "$tmp_file" "$dst_file"
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

	if [ -f "$dst_file" ] && [ "$dst_file" -nt "$zip_file" ]; then
		echo "skip: $dst_file"
		return 0
	fi

	tmp_file=$(prepare_tmp "$dst_file") || return 1
	if unzip -p "$zip_file" "$entry" | gzip -dc > "$tmp_file"; then
		finish_tmp "$tmp_file" "$dst_file"
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
