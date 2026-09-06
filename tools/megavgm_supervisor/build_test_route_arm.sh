#!/bin/sh
# Run inside the existing mister-gcc10 Lima VM, from an explicitly copied source tree.
# No downloads, Docker, source mutation, or MiSTer installation.
set -eu
tool_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
out=${1:?provide a new absolute output directory}
case "$out" in /*) ;; *) echo 'output must be absolute' >&2; exit 2;; esac
mkdir "$out"
arm_prefix=/opt/gcc-arm-10.2-2020.11-x86_64-arm-none-linux-gnueabihf/bin/arm-none-linux-gnueabihf
cd "$tool_dir"
"$arm_prefix-g++" --version > "$out/compiler.txt"
"$arm_prefix-g++" -O2 -std=c++14 -Wall -Wextra -Wpedantic -Werror \
  -march=armv7-a -mfpu=vfpv3 -mfloat-abi=hard -static \
  main.cpp linux_runtime.cpp test_profile.cpp supervisor.cpp runtime_support.cpp \
  sha256.cpp ../megavgm_autoplay2/autoplay2.cpp -o "$out/megavgm_supervisor"
"$arm_prefix-g++" -O2 -std=c++14 -Wall -Wextra -Wpedantic -Werror \
  -march=armv7-a -mfpu=vfpv3 -mfloat-abi=hard -static \
  test_supervisor.cpp test_profile.cpp supervisor.cpp runtime_support.cpp sha256.cpp \
  -o "$out/test_supervisor"
qemu-arm-static "$out/test_supervisor"
"$arm_prefix-strip" --strip-all "$out/megavgm_supervisor"
# Executes the exact delivered binary; query only, no ENTER/stock manipulation.
qemu-arm-static "$out/megavgm_supervisor" test-profile > "$out/default-profile.txt"
grep -qx 'test_profile=YM2151_SEGAPCM' "$out/default-profile.txt"
grep -qx 'rbf=/media/fat/MegaVGMPlayer/MegaVGMPlayer_PlaylistLoopLab_MiSTer.rbf' "$out/default-profile.txt"
file "$out/megavgm_supervisor" | tee "$out/file.txt"
"$arm_prefix-readelf" -h -A -l -d "$out/megavgm_supervisor" > "$out/elf.txt"
grep -q 'Version5 EABI, hard-float ABI' "$out/elf.txt"
grep -q 'VFP registers' "$out/elf.txt"
if grep -Eq 'INTERP|NEEDED' "$out/elf.txt"; then
  echo 'FAIL: dynamic runtime dependency' >&2; exit 1
fi
sha256sum "$out/megavgm_supervisor" > "$out/SHA256SUMS"
echo 'Supervisor static ARM exact-binary regression: PASS'
