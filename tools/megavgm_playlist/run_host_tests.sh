#!/bin/sh
set -eu

tool_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
autoplay2_dir=$tool_dir/../megavgm_autoplay2
test_bin=${TMPDIR:-/tmp}/megavgm_playlist_test.$$
controller_bin=${TMPDIR:-/tmp}/megavgm_playlist_host.$$
control_test_bin=${TMPDIR:-/tmp}/megavgm_playlist_control_test.$$
ctl_bin=${TMPDIR:-/tmp}/megavgm_ctl_host.$$
mode_test_bin=${TMPDIR:-/tmp}/megavgm_playback_mode_test.$$
trap 'rm -f "$test_bin" "$controller_bin" "$control_test_bin" "$ctl_bin" "$mode_test_bin"' EXIT HUP INT TERM

"${CXX:-c++}" -O2 -std=c++14 -Wall -Wextra -Wpedantic \
	"$tool_dir/test_playlist.cpp" "$tool_dir/playlist.cpp" \
	"$tool_dir/playlist_control.cpp" \
	"$tool_dir/playback_mode.cpp" \
	"$autoplay2_dir/autoplay2.cpp" -o "$test_bin"
"$test_bin"

"${CXX:-c++}" -O2 -std=c++14 -Wall -Wextra -Wpedantic \
	"$tool_dir/test_playlist_control.cpp" "$tool_dir/playlist_control.cpp" \
	"$tool_dir/playback_mode.cpp" \
	-o "$control_test_bin"
"$control_test_bin"

"${CXX:-c++}" -O2 -std=c++14 -Wall -Wextra -Wpedantic \
	"$tool_dir/test_playback_mode.cpp" "$tool_dir/playback_mode.cpp" \
	-o "$mode_test_bin"
"$mode_test_bin"

"${CXX:-c++}" -O2 -std=c++14 -Wall -Wextra -Wpedantic \
	"$tool_dir/main.cpp" "$tool_dir/playlist.cpp" \
	"$tool_dir/playlist_control.cpp" \
	"$tool_dir/playback_mode.cpp" \
	"$autoplay2_dir/autoplay2.cpp" -o "$controller_bin"
"$controller_bin" >/dev/null 2>&1 && exit 1 || test "$?" -eq 2
"$controller_bin" --loops nope /tmp >/dev/null 2>&1 && exit 1 || test "$?" -eq 2
"$controller_bin" --loops 65536 /tmp >/dev/null 2>&1 && exit 1 || test "$?" -eq 2
"$controller_bin" --loops 42949672960 /tmp >/dev/null 2>&1 && exit 1 || test "$?" -eq 2
"$controller_bin" --start-file /tmp/a.vgm --playlist-snapshot \
	/tmp/megavgm_playlist.snapshot-test /tmp >/dev/null 2>&1 && exit 1 || test "$?" -eq 2
"${CXX:-c++}" -O2 -std=c++14 -Wall -Wextra -Wpedantic \
"$tool_dir/ctl.cpp" "$tool_dir/playlist_control.cpp" \
	"$tool_dir/playback_mode.cpp" -o "$ctl_bin"
"$ctl_bin" >/dev/null 2>&1 && exit 1 || test "$?" -eq 2
"$ctl_bin" unknown >/dev/null 2>&1 && exit 1 || test "$?" -eq 2
echo "megavgm_playlist CLI build/usage: PASS"
