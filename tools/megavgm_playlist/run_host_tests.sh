#!/bin/sh
set -eu

tool_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
autoplay2_dir=$tool_dir/../megavgm_autoplay2
test_bin=${TMPDIR:-/tmp}/megavgm_playlist_test.$$
controller_bin=${TMPDIR:-/tmp}/megavgm_playlist_host.$$
trap 'rm -f "$test_bin" "$controller_bin"' EXIT HUP INT TERM

"${CXX:-c++}" -O2 -std=c++14 -Wall -Wextra -Wpedantic \
	"$tool_dir/test_playlist.cpp" "$tool_dir/playlist.cpp" \
	"$autoplay2_dir/autoplay2.cpp" -o "$test_bin"
"$test_bin"

"${CXX:-c++}" -O2 -std=c++14 -Wall -Wextra -Wpedantic \
	"$tool_dir/main.cpp" "$tool_dir/playlist.cpp" \
	"$autoplay2_dir/autoplay2.cpp" -o "$controller_bin"
"$controller_bin" >/dev/null 2>&1 && exit 1 || test "$?" -eq 2
echo "megavgm_playlist CLI build/usage: PASS"
