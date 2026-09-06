#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
test_bin=${TMPDIR:-/tmp}/megavgm_supervisor_test.$$
trap 'rm -f "$test_bin"' EXIT HUP INT TERM

"${CXX:-c++}" -O2 -std=c++14 -Wall -Wextra -Wpedantic -Werror \
	"$script_dir/test_supervisor.cpp" \
	"$script_dir/supervisor.cpp" \
	"$script_dir/runtime_support.cpp" \
	"$script_dir/sha256.cpp" \
	"$script_dir/test_profile.cpp" \
	-o "$test_bin"
"$test_bin"
