#!/bin/sh
set -eu
. "$(dirname -- "$0")/common.sh"
verify_package
stock_gate
lock_install
backup=${1:-$(cat "$fat/MegaVGMPlayer/.v23-last-backup")}
case "$backup" in "$fat"/MegaVGMPlayer/backups-v2.3-*) ;; *) fail 'Invalid backup path';; esac
safe_path "$backup"
[ -f "$backup/PREPARED" ] || fail 'Backup not prepared'
[ ! -f "$backup/ROLLED_BACK" ] || fail 'Already rolled back'
(cd "$backup" && { [ ! -s BEFORE.sha256 ] || sha256sum -c BEFORE.sha256; }) || fail 'Backup corrupted'
# Preflight all targets before stopping service or changing any file. Only restore
# files still equal to this transaction's before/after bytes; preserve later edits.
while IFS= read -r rel; do
  safe_path "$fat/$rel"
  if [ -f "$fat/$rel" ]; then
    actual=$(sha "$fat/$rel")
    expected=$(awk -v p="$rel" 'substr($0,67)==p {print substr($0,1,64)}' "$backup/AFTER.sha256")
    if [ "$actual" != "$expected" ]; then
      [ -f "$backup/files/$rel" ] && [ "$actual" = "$(sha "$backup/files/$rel")" ] || fail "Changed since install: $rel"
    fi
  elif ! grep -Fxq "$rel" "$backup/ABSENT"; then fail "Missing since install: $rel"; fi
done <<EOF
$paths
EOF
stop_daemon
while IFS= read -r rel; do
  if [ -f "$backup/files/$rel" ]; then
    stage=$(mktemp "$fat/$(dirname "$rel")/.v23-restore-XXXXXX")
    cp -p "$backup/files/$rel" "$stage"
    mv -f "$stage" "$fat/$rel"
  elif grep -Fxq "$rel" "$backup/ABSENT" && [ -f "$fat/$rel" ]; then
    # Recoverable removal of files introduced by this install.
    mkdir -p "$backup/retired/$(dirname "$rel")"
    mv "$fat/$rel" "$backup/retired/$rel"
  fi
done <<EOF
$paths
EOF
if [ "$service_checks" = 1 ] && [ "$(cat "$backup/WAS_RUNNING")" = 1 ]; then
  "$backup/previous-daemon" -service start
fi
touch "$backup/ROLLED_BACK"
echo 'Rolled back. Introduced files retained under backup/retired. Remote and playlist JSON untouched.'
