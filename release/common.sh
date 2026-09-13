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
    'MegaVGMPlayer/megavgm_sid_prepare' \
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
service_checks=1
if [ "$offline" = 1 ]; then service_checks=${MEGAVGM_INSTALL_SERVICE_TEST:-0}; fi
case "$service_checks" in 0|1) ;; *) fail 'Invalid service-test mode' ;; esac
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
  [ "$service_checks" = 1 ] || return 0
  if "$daemon" -service status >/dev/null 2>&1; then
    "$daemon" -service stop || fail 'Standalone drain/identity check failed; no force kill'
  elif [ -e "$runtime_root/megavgm_remote.pid" ] || [ -e "$runtime_root/megavgm_remote.identity" ]; then
    fail 'Standalone identity is unverifiable; inspect before replacement'
  fi
}
verify_installed_targets() {
  while IFS= read -r rel; do
    target="$fat/$rel"
    safe_path "$target"
    [ -f "$target" ] || fail "Installed target missing/not regular: $rel"
    expected=$(sha "$package/media/fat/$rel") || fail "Cannot hash packaged target: $rel"
    actual=$(sha "$target") || fail "Cannot hash installed target: $rel"
    [ "$actual" = "$expected" ] ||
      fail "Installed target SHA mismatch: $rel expected=$expected actual=$actual"
  done <<EOF
$(targets)
EOF
}
verify_running_remote() {
  [ "$service_checks" = 1 ] || return 0
  installed="$fat/MegaVGMPlayer/megavgm_remote"
  runtime="$runtime_root/megavgm_remote"
  expected=$(sha "$package/media/fat/MegaVGMPlayer/megavgm_remote") || fail 'Cannot hash packaged Remote'
  [ -f "$installed" ] || fail 'Installed Remote missing/not regular'
  [ "$(sha "$installed")" = "$expected" ] || fail 'Installed Remote SHA mismatch'
  [ -f "$runtime" ] || fail 'Runtime Remote missing/not regular'
  runtime_sha=$(sha "$runtime") || fail 'Cannot hash runtime Remote'
  [ "$runtime_sha" = "$expected" ] ||
    fail "Runtime Remote SHA mismatch: expected=$expected actual=$runtime_sha"
  state=$("$installed" -service status 2>&1) || {
    printf '%s\n' "$state" >&2
    fail 'Cannot verify running Remote service'
  }
  pid=$(printf '%s\n' "$state" | sed -n 's/^running pid=\([0-9][0-9]*\) sha256=[0-9a-f][0-9a-f]* port=8183$/\1/p')
  reported=$(printf '%s\n' "$state" | sed -n 's/^running pid=[0-9][0-9]* sha256=\([0-9a-f][0-9a-f]*\) port=8183$/\1/p')
  [ -n "$pid" ] && [ "$state" = "running pid=$pid sha256=$reported port=8183" ] ||
    fail "Invalid Remote service status: $state"
  [ "$reported" = "$expected" ] ||
    fail "Running Remote reported SHA mismatch: expected=$expected actual=$reported"
  process_exe=$(readlink "$proc_root/$pid/exe" 2>/dev/null) || fail 'Running Remote executable identity unavailable'
  [ "$process_exe" = "$runtime" ] ||
    fail "Running Remote executable path mismatch: expected=$runtime actual=$process_exe"
  process_sha=$(sha "$proc_root/$pid/exe") || fail 'Cannot hash running Remote executable'
  [ "$process_sha" = "$expected" ] ||
    fail "Running Remote executable SHA mismatch: expected=$expected actual=$process_sha"
  echo "Verified running Remote: pid=$pid path=$runtime sha256=$expected"
}
