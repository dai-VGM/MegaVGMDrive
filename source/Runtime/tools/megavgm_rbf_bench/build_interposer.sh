#!/bin/sh
set -eu

source_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
output=${1:?absolute output path required}
case "$output" in /*) ;; *) echo "absolute output path required" >&2; exit 2;; esac
compiler=${ARM_CC:-/opt/gcc-arm-10.2-2020.11-x86_64-arm-none-linux-gnueabihf/bin/arm-none-linux-gnueabihf-gcc}
prefix=${compiler%gcc}
"$compiler" -std=c11 -O2 -Wall -Wextra -Wpedantic -Werror \
  -march=armv7-a -mfpu=vfpv3 -mfloat-abi=hard -fPIC -shared \
  "$source_dir/rbf_bench_interposer.c" -ldl -o "$output"
"${prefix}strip" --strip-all "$output"
file "$output"
"${prefix}readelf" -h -A -l -d "$output"
sha256sum "$output"
