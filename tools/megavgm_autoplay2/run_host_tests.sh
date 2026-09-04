#!/bin/sh
set -eu

tool_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
test_bin=${TMPDIR:-/tmp}/megavgm_autoplay2_test.$$
controller_bin=${TMPDIR:-/tmp}/megavgm_autoplay2_host.$$
trap 'rm -f "$test_bin" "$controller_bin"' EXIT HUP INT TERM

"${CXX:-c++}" -O2 -std=c++14 -Wall -Wextra -Wpedantic \
	"$tool_dir/test_autoplay2.cpp" "$tool_dir/autoplay2.cpp" \
	-pthread -o "$test_bin"
"$test_bin"

"${CXX:-c++}" -O2 -std=c++14 -Wall -Wextra -Wpedantic \
	"$tool_dir/main.cpp" "$tool_dir/autoplay2.cpp" \
	-o "$controller_bin"
"$controller_bin" >/dev/null 2>&1 && exit 1 || test "$?" -eq 2
echo "megavgm_autoplay2 CLI build/usage: PASS"
