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
    '_Custom Cores/Cores/MegaVGMPlayer_Transport13FadeOnly_A_MiSTer.rbf' \
    '_Custom Cores/Cores/MegaVGMPlayer_Transport13FadeOnly_B_MiSTer.rbf' \
    'MegaVGMPlayer/MiSTer.megavgm' 'MegaVGMPlayer/megavgm_supervisor' \
    'MegaVGMPlayer/megavgm_playlist-phase2a' 'MegaVGMPlayer/megavgm_remote' \
    'Scripts/megavgm_ctl' 'Scripts/vgm_md_import.sh'
}
paths="$(targets)
linux/user-startup.sh"
verify_package() { (cd "$package" && sha256sum -c SHA256SUMS) || fail 'Package SHA mismatch'; }
sha() { sha256sum "$1" | cut -d ' ' -f 1; }
# Refuse symlink targets/parents, including in offline tests.
safe_path() {
  check=$1
  while [ "$check" != / ]; do
    [ ! -L "$check" ] || fail "Symlink not supported: $check"
    check=$(dirname "$check")
  done
}
stock_gate() {
  [ "$offline" = 1 ] && return
  if [ -x "$fat/MegaVGMPlayer/megavgm_supervisor" ]; then
    state=$("$fat/MegaVGMPlayer/megavgm_supervisor" status) || fail 'Cannot read Supervisor'
    printf '%s\n' "$state" | grep -q '^mode=STOCK$' || fail 'Exit Player to STOCK first'
    printf '%s\n' "$state" | grep -q '^main=STOCK$' || fail 'Main is not STOCK'
  elif [ -e /tmp/megavgm_supervisor.status ]; then
    fail 'Existing Supervisor status without executable; inspect manually'
  fi
}
lock_install() {
  safe_path "$fat/MegaVGMPlayer/.v21-install-lock"
  mkdir -p "$fat/MegaVGMPlayer"
  lock="$fat/MegaVGMPlayer/.v21-install-lock"
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
