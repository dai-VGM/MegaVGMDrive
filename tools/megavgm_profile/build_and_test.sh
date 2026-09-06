#!/bin/sh
# Existing official ARM GCC/Lima path; host mode for non-mutating regressions.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
out=${1:?new absolute output directory}
mode=${2:-host}
case "$out" in /*) ;; *) exit 2;; esac
mkdir "$out"
cd "$root"
flags='-O2 -std=c++14 -Wall -Wextra -Wpedantic -Werror -DMEGAVGM_PHASE2A'
runner=
compiler=${CXX:-c++}
if [ "$mode" = arm ]; then
  prefix=/opt/gcc-arm-10.2-2020.11-x86_64-arm-none-linux-gnueabihf/bin/arm-none-linux-gnueabihf
  compiler=$prefix-g++
  flags="$flags -march=armv7-a -mfpu=vfpv3 -mfloat-abi=hard -static"
  runner=qemu-arm-static
elif [ "$mode" != host ]; then exit 2; fi
"$compiler" --version > "$out/compiler.txt"
profile='tools/megavgm_profile/profile.cpp tools/megavgm_profile/switch.cpp'
playlist='tools/megavgm_playlist/playlist.cpp tools/megavgm_playlist/playlist_control.cpp tools/megavgm_playlist/playback_mode.cpp tools/megavgm_autoplay2/autoplay2.cpp'
supervisor='tools/megavgm_supervisor/supervisor.cpp tools/megavgm_supervisor/runtime_support.cpp tools/megavgm_supervisor/test_profile.cpp tools/megavgm_supervisor/sha256.cpp'
# All expansions below are fixed source/flag lists, never user paths/commands.
mkdir "$out/obj"
pids=
jobs=0
for source in $profile $playlist $supervisor; do
  object=$(basename "$source" .cpp)
  "$compiler" $flags -c "$source" -o "$out/obj/$object.o" &
  pids="$pids $!"
  jobs=$((jobs+1))
  if [ "$jobs" -eq 2 ]; then
    for pid in $pids; do wait "$pid"; done
    pids=
    jobs=0
  fi
done
for pid in $pids; do wait "$pid"; done
profile="$out/obj/profile.o $out/obj/switch.o"
playlist="$out/obj/playlist.o $out/obj/playlist_control.o $out/obj/playback_mode.o $out/obj/autoplay2.o"
supervisor="$out/obj/supervisor.o $out/obj/runtime_support.o $out/obj/test_profile.o $out/obj/sha256.o"
"$compiler" $flags tools/megavgm_profile/test_phase2a.cpp $profile $playlist -o "$out/test_phase2a"
$runner "$out/test_phase2a" > "$out/phase2a-tests.txt"
"$compiler" $flags tools/megavgm_supervisor/test_supervisor.cpp $supervisor -o "$out/test_supervisor"
$runner "$out/test_supervisor" > "$out/supervisor-tests.txt"
"$compiler" $flags tools/megavgm_playlist/test_playlist.cpp $profile $playlist -o "$out/test_playlist"
$runner "$out/test_playlist" > "$out/playlist-tests.txt"
"$compiler" $flags tools/megavgm_playlist/main.cpp $profile $playlist -o "$out/megavgm_playlist"
"$compiler" $flags tools/megavgm_supervisor/main.cpp tools/megavgm_supervisor/linux_runtime.cpp \
  tools/megavgm_supervisor/phase2a.cpp $supervisor $profile $playlist -o "$out/megavgm_supervisor"
"$compiler" $flags tools/megavgm_profile/classify_main.cpp "$out/obj/profile.o" -o "$out/megavgm_classify"
if [ "$mode" = arm ]; then
  for binary in megavgm_playlist megavgm_supervisor megavgm_classify; do
    "$prefix-strip" --strip-all "$out/$binary"
    file "$out/$binary" > "$out/$binary.file.txt"
    "$prefix-readelf" -h -A -l -d "$out/$binary" > "$out/$binary.elf.txt"
    grep -q 'Version5 EABI, hard-float ABI' "$out/$binary.elf.txt"
    grep -q 'VFP registers' "$out/$binary.elf.txt"
    if grep -Eq 'INTERP|NEEDED' "$out/$binary.elf.txt"; then exit 1; fi
  done
fi
$runner "$out/megavgm_supervisor" test-profile > "$out/default-route.txt"
grep -q 'test_profile=YM2151_SEGAPCM' "$out/default-route.txt"
if $runner "$out/megavgm_playlist" > "$out/usage.txt" 2>&1; then exit 1; else test "$?" -eq 2; fi
echo 'Phase2A build + tests PASS (host/QEMU; hardware NOT TESTED)'
