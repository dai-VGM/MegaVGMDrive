#!/bin/sh
#
# Expand .vgz files into a plain .vgm cache directory for the MiSTer VGM core.
#
# Usage:
#   scripts/vgz_to_vgm_cache.sh [SRC_DIR] [DST_DIR]
#
# Defaults:
#   SRC_DIR=/media/fat/music/vgz
#   DST_DIR=/media/fat/music/vgm_cache
#
# Example:
#   scripts/vgz_to_vgm_cache.sh "/media/fat/music/vgz" "/media/fat/music/vgm_cache"
#
# The FPGA core loads the generated .vgm files. It does not natively load .vgz
# and does not do gzip decompression in hardware.

set -u

SRC=${1:-/media/fat/music/vgz}
DST=${2:-/media/fat/music/vgm_cache}

if [ ! -d "$SRC" ]; then
	echo "source directory not found: $SRC" >&2
	exit 1
fi

if ! command -v gzip >/dev/null 2>&1; then
	echo "gzip command not found" >&2
	exit 1
fi

if ! mkdir -p "$DST"; then
	echo "failed to create destination directory: $DST" >&2
	exit 1
fi

export SRC
export DST

find "$SRC" -type f \( -name '*.vgz' -o -name '*.VGZ' \) -exec sh -c '
	status=0

	for src_file do
		rel=${src_file#"$SRC"/}
		if [ "$rel" = "$src_file" ]; then
			rel=${src_file##*/}
		fi

		rel_no_ext=${rel%.[vV][gG][zZ]}
		dst_file=$DST/$rel_no_ext.vgm
		dst_dir=${dst_file%/*}
		tmp_file=$dst_file.tmp.$$

		if [ -f "$dst_file" ] && [ "$dst_file" -nt "$src_file" ]; then
			echo "skip: $dst_file"
			continue
		fi

		if ! mkdir -p "$dst_dir"; then
			echo "failed to create destination directory: $dst_dir" >&2
			status=1
			continue
		fi

		rm -f "$tmp_file"
		if gzip -dc "$src_file" > "$tmp_file"; then
			if mv "$tmp_file" "$dst_file"; then
				echo "wrote: $dst_file"
			else
				echo "failed to move temp file into place: $dst_file" >&2
				rm -f "$tmp_file"
				status=1
			fi
		else
			echo "failed to expand: $src_file" >&2
			rm -f "$tmp_file"
			status=1
		fi
	done

	exit "$status"
' sh {} +
