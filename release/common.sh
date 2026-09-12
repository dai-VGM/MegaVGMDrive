#!/bin/sh
# Sourced by the release scripts. No Remote, playlist data, or playback commands.
set -eu
package=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
fat=${MEGAVGM_FAT_ROOT:-/media/fat}
offline=${MEGAVGM_INSTALL_OFFLINE:-0}
fail() { echo "ERROR: $*" >&2; exit 1; }
case "$fat" in /*) ;; *) fail 'FAT root must be absolute';; esac
[ "$fat" != / ] || fail 'Refusing filesystem root'
if [ "$offline" = 1 ]; then
  [ "$fat" != /media/fat ] || fail 'Offline mode requires an isolated root'
else
  [ "$fat" = /media/fat ] || fail 'Live mode requires /media/fat'
  [ "$(id -u)" = 0 ] || fail 'Run as root on MiSTer'
fi
targets() {
  printf '%s\n' \
    '_Custom Cores/Cores/MegaVGMDrive_A.rbf' \
    '_Custom Cores/Cores/MegaVGMDrive_B.rbf' \
    '_Custom Cores/Cores/MegaVGMDrive_C.rbf' \
    'MegaVGMPlayer/MiSTer.megavgm' 'MegaVGMPlayer/megavgm_supervisor' \
    'MegaVGMPlayer/megavgm_playlist-phase2a' 'MegaVGMPlayer/megavgm_remote' \
    'Scripts/megavgm_ctl' 'Scripts/vgm_md_import.sh'
}
paths="$(targets)
linux/user-startup.sh"
verify_package() { (cd "$package" && sha256sum -c SHA256SUMS) || fail 'Package SHA mismatch'; }
sha() { sha256sum "$1" | cut -d ' ' -f 1; }
stock_main_sha256=7ca3cd2f224b9264d0889f593a0d77aafa5adda61910baba92c5ae401e26fcce
proc_root=/proc
runtime_root=/tmp
# The override exists only for isolated Linux fixtures. Live installation
# always uses real /proc, /tmp, and the compiled-in known stock Main SHA.
if [ "$offline" = 1 ] && [ "${MEGAVGM_PREFLIGHT_TEST:-0}" = 1 ]; then
  proc_root=${MEGAVGM_PROC_ROOT:?missing test proc root}
  runtime_root=${MEGAVGM_RUNTIME_ROOT:?missing test runtime root}
  stock_main_sha256=${MEGAVGM_TEST_STOCK_SHA256:?missing test stock SHA}
fi
# Refuse symlink targets/parents, including in offline tests.
safe_path() {
  check=$1
  while [ "$check" != / ]; do
    [ ! -L "$check" ] || fail "Symlink not supported: $check"
    check=$(dirname "$check")
  done
}
verify_stock_without_status() {
  [ -d "$proc_root" ] || fail "Process filesystem unavailable: $proc_root"
  mister_count=0
  mister_pid=
  for process in "$proc_root"/[0-9]*; do
    [ -d "$process" ] || continue
    comm=$(sed -n '1p' "$process/comm" 2>/dev/null) || continue
    exe=$(readlink "$process/exe" 2>/dev/null || true)
    case "$comm" in
      megavgm_play*|megavgm_super*)
        fail "MegaVGM controller/Supervisor process is active: $(basename "$process")"
        ;;
    esac
    case "$exe" in
      "$fat/MegaVGMPlayer/megavgm_playlist-phase2a"|"$fat/Scripts/megavgm_playlist")
        fail "MegaVGM controller process is active: $(basename "$process")"
        ;;
      "$fat/MegaVGMPlayer/megavgm_supervisor")
        fail "MegaVGM Supervisor process is active without status: $(basename "$process")"
        ;;
      "$fat/MegaVGMPlayer/MiSTer.megavgm")
        fail "Modified Main process is active: $(basename "$process")"
        ;;
    esac
    [ "$comm" = MiSTer ] || continue
    [ -n "$exe" ] || fail "MiSTer executable identity unavailable: $(basename "$process")"
    mister_count=$((mister_count + 1))
    mister_pid=$(basename "$process")
    [ "$exe" = "$fat/MiSTer" ] || fail "Active Main executable path is not stock: $exe"
    actual=$(sha "$process/exe") || fail "Cannot hash active Main: $mister_pid"
    [ "$actual" = "$stock_main_sha256" ] ||
      fail "Active Main SHA mismatch: expected=$stock_main_sha256 actual=$actual"
  done
  [ "$mister_count" -eq 1 ] ||
    fail "Expected exactly one SHA-verified stock MiSTer process; found $mister_count"

  for active in \
    "$runtime_root/megavgm_supervisor.sock" \
    "$runtime_root/megavgm_playlist.cmd" \
    "$runtime_root/megavgm_playlist.status" \
    "$runtime_root/megavgm_playlist.stderr" \
    "$runtime_root/megavgm_playlist.trace" \
    "$runtime_root/MegaVGMPlayer.status" \
    "$runtime_root/megavgm_load_file.status"; do
    [ ! -e "$active" ] || fail "Active/ambiguous MegaVGM runtime state exists: $active"
  done
  for channel in "$runtime_root"/megavgm-phase2a.*; do
    [ ! -e "$channel" ] || fail "Active/ambiguous Phase2A channel exists: $channel"
  done
  echo "Verified STOCK without persisted Supervisor status: pid=$mister_pid sha256=$stock_main_sha256"
}
stock_gate() {
  [ "$offline" != 1 ] || [ "${MEGAVGM_PREFLIGHT_TEST:-0}" = 1 ] || return 0
  if [ -x "$fat/MegaVGMPlayer/megavgm_supervisor" ]; then
    if state=$("$fat/MegaVGMPlayer/megavgm_supervisor" status 2>&1); then
      printf '%s\n' "$state" | grep -q '^mode=STOCK$' || fail 'Exit Player to STOCK first'
      printf '%s\n' "$state" | grep -q '^main=STOCK$' || fail 'Main is not STOCK'
      return
    fi
    case "$state" in
      STATUS_UNAVAILABLE:*) verify_stock_without_status ;;
      *) printf '%s\n' "$state" >&2; fail 'Cannot read Supervisor' ;;
    esac
  elif [ -e "$runtime_root/megavgm_supervisor.status" ]; then
    fail 'Existing Supervisor status without executable; inspect manually'
  else
    verify_stock_without_status
  fi
}
lock_install() {
  safe_path "$fat/MegaVGMPlayer/.v22-install-lock"
  mkdir -p "$fat/MegaVGMPlayer"
  lock="$fat/MegaVGMPlayer/.v22-install-lock"
  mkdir "$lock" || fail 'Installer lock exists; do not run concurrently. Inspect any interrupted transaction first.'
  trap 'rmdir "$lock"' EXIT
}
daemon="$package/media/fat/MegaVGMPlayer/megavgm_remote"
stop_daemon() {
  [ "$offline" = 1 ] && return
  if "$daemon" -service status >/dev/null 2>&1; then
    "$daemon" -service stop || fail 'Standalone drain/identity check failed; no force kill'
  elif [ -e /tmp/megavgm_remote.pid ] || [ -e /tmp/megavgm_remote.identity ]; then
    fail 'Standalone identity is unverifiable; inspect before replacement'
  fi
}
