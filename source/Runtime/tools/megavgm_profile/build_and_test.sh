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
msm=${MEGAVGM_HOST_MSM6295:-0}
case "$msm" in 0|1) ;; *) exit 2;; esac
flags="$flags -DMEGAVGM_HOST_MSM6295=$msm"
k053260=${MEGAVGM_HOST_K053260:-0}
case "$k053260" in 0|1) ;; *) exit 2;; esac
flags="$flags -DMEGAVGM_HOST_K053260=$k053260"
for feature in MEGAVGM_HOST_K053260_EMPTY_ROM MEGAVGM_HOST_MSM6295_PCM_ONLY MEGAVGM_HOST_A_YM2151_4026987; do
  eval "enabled=\${$feature:-0}"
  case "$enabled" in 0|1) ;; *) exit 2;; esac
  flags="$flags -D$feature=$enabled"
done
runner=
compiler=${CXX:-c++}
if [ "$mode" = arm ]; then
  prefix=/opt/gcc-arm-10.2-2020.11-x86_64-arm-none-linux-gnueabihf/bin/arm-none-linux-gnueabihf
  compiler=$prefix-g++
  flags="$flags -march=armv7-a -mfpu=vfpv3 -mfloat-abi=hard -static"
  runner=qemu-arm-static
elif [ "$mode" != host ]; then exit 2; fi
"$compiler" --version > "$out/compiler.txt"
run_test() {
  if [ "$mode" = arm ]; then
    # QEMU is a 64bit host process: ext4 returns 64bit directory cookies which
    # ARM32 glibc readdir cannot represent (EOVERFLOW). Use a PRIVATE tmpfs for
    # test fixtures, not a production code change or a skipped assertion.
    # Open the binary before hiding /tmp; no VM-global mount is changed.
    sudo unshare -m --propagation private sh -c \
      'exec 3<"$1"; mount -t tmpfs tmpfs /tmp; export MEGAVGM_CAPACITY_SKIP_REAL_DIR="$2"; exec qemu-arm-static /proc/self/fd/3' sh "$1" "${MEGAVGM_CAPACITY_SKIP_REAL_DIR:-}"
  else
    "$1"
  fi
}
profile='tools/megavgm_profile/profile.cpp tools/megavgm_profile/switch.cpp'
playlist='tools/megavgm_playlist/playlist.cpp tools/megavgm_playlist/playlist_control.cpp tools/megavgm_playlist/playback_mode.cpp tools/megavgm_playlist/sid_prepare.cpp tools/megavgm_autoplay2/autoplay2.cpp'
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
"$compiler" $flags tools/megavgm_profile/test_msm6295.cpp "$out/obj/profile.o" -o "$out/test_msm6295"
run_test "$out/test_msm6295" > "$out/msm6295-tests.txt"
"$compiler" $flags tools/megavgm_profile/test_a_ym2151_clock.cpp "$out/obj/profile.o" -o "$out/test_a_ym2151_clock"
run_test "$out/test_a_ym2151_clock" > "$out/a-ym-clock-tests.txt"
profile="$out/obj/profile.o $out/obj/switch.o"
playlist="$out/obj/playlist.o $out/obj/playlist_control.o $out/obj/playback_mode.o $out/obj/sid_prepare.o $out/obj/autoplay2.o"
supervisor="$out/obj/supervisor.o $out/obj/runtime_support.o $out/obj/test_profile.o $out/obj/sha256.o"
"$compiler" $flags tools/megavgm_profile/test_sound_chips.cpp $profile $playlist -o "$out/test_sound_chips"
run_test "$out/test_sound_chips" > "$out/sound-chip-tests.txt"
"$compiler" $flags tools/megavgm_profile/test_k053260.cpp $profile $playlist -o "$out/test_k053260"
run_test "$out/test_k053260" > "$out/k053260-tests.txt"
"$compiler" $flags tools/megavgm_profile/test_phase2a.cpp $profile $playlist -o "$out/test_phase2a"
run_test "$out/test_phase2a" > "$out/phase2a-tests.txt"
"$compiler" $flags tools/megavgm_supervisor/test_supervisor.cpp $supervisor -o "$out/test_supervisor"
run_test "$out/test_supervisor" > "$out/supervisor-tests.txt"
"$compiler" $flags tools/megavgm_supervisor/test_process_stabilization.cpp \
	"$out/obj/supervisor.o" -o "$out/test_process_stabilization"
run_test "$out/test_process_stabilization" > "$out/process-stabilization-tests.txt"
"$compiler" $flags tools/megavgm_playlist/test_playlist.cpp $profile $playlist -o "$out/test_playlist"
run_test "$out/test_playlist" > "$out/playlist-tests.txt"
"$compiler" $flags tools/megavgm_playlist/test_repeat_recovery.cpp $profile $playlist -o "$out/test_repeat_recovery"
run_test "$out/test_repeat_recovery" > "$out/repeat-recovery-tests.txt"
"$compiler" $flags tools/megavgm_profile/test_repeat_recovery_profile.cpp $profile $playlist -o "$out/test_repeat_recovery_profile"
run_test "$out/test_repeat_recovery_profile" > "$out/repeat-recovery-profile-tests.txt"
"$compiler" $flags tools/megavgm_profile/test_session_ownership.cpp $profile $playlist -o "$out/test_session_ownership"
run_test "$out/test_session_ownership" > "$out/session-ownership-tests.txt"
"$compiler" $flags tools/megavgm_profile/test_capacity_skip.cpp $profile $playlist -o "$out/test_capacity_skip"
run_test "$out/test_capacity_skip" > "$out/capacity-skip-tests.txt"
"$compiler" $flags tools/megavgm_playlist/test_sid_prepare.cpp tools/megavgm_playlist/sid_prepare.cpp -o "$out/test_sid_prepare"
run_test "$out/test_sid_prepare" > "$out/sid-prepare-tests.txt"
"$compiler" $flags tools/megavgm_playlist/main.cpp $profile $playlist -o "$out/megavgm_playlist"
"$compiler" $flags tools/megavgm_supervisor/main.cpp tools/megavgm_supervisor/linux_runtime.cpp \
  tools/megavgm_supervisor/phase2a.cpp $supervisor $profile $playlist -o "$out/megavgm_supervisor"
"$compiler" $flags tools/megavgm_profile/classify_main.cpp "$out/obj/profile.o" \
  "$out/obj/sha256.o" -o "$out/megavgm_classify"
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
grep -q 'test_profile=PHASE2A_AUTO' "$out/default-route.txt"
if $runner "$out/megavgm_playlist" > "$out/usage.txt" 2>&1; then exit 1; else test "$?" -eq 2; fi
echo 'Phase2A build + tests PASS (host/QEMU; hardware NOT TESTED)'
