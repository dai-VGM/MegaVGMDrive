#!/bin/sh
set -eu
. "$(dirname -- "$0")/common.sh"
verify_package
stock_gate
lock_install
printf '%s\n' "$paths" | while IFS= read -r rel; do
  safe_path "$fat/$rel"
  [ ! -e "$fat/$rel" ] || [ -f "$fat/$rel" ] || fail "Not a regular file: $rel"
done
startup="$fat/linux/user-startup.sh"
work=$(mktemp -d "$fat/MegaVGMPlayer/.v23-stage-XXXXXX")
# Staging/backup may be retained on failure for diagnosis, never delete user files.
if [ -f "$startup" ]; then cp -p "$startup" "$work/startup"; else printf '#!/bin/sh\n' > "$work/startup"; fi
if grep -q 'megavgm_remote\|BEGIN MegaVGMPlayer\|END MegaVGMPlayer' "$work/startup"; then
  [ "$(grep -c '^# BEGIN MegaVGMPlayer v2.1$' "$work/startup")" = 1 ] || fail 'Unrecognized/duplicate standalone startup; reconcile manually'
  sed -n '/^# BEGIN MegaVGMPlayer v2.1$/,/^# END MegaVGMPlayer v2.1$/p' "$work/startup" > "$work/block"
  cmp -s "$work/block" "$package/startup.block" || fail 'Modified startup block; preserve and inspect manually'
  sed '/^# BEGIN MegaVGMPlayer v2.1$/,/^# END MegaVGMPlayer v2.1$/d' "$work/startup" > "$work/outside"
  ! grep -q 'megavgm_remote\|BEGIN MegaVGMPlayer\|END MegaVGMPlayer' "$work/outside" || fail 'Additional standalone startup invocation'
else
  printf '\n' >> "$work/startup"
  cat "$package/startup.block" >> "$work/startup"
fi
changed=0
cmp -s "$work/startup" "$startup" || changed=1
while IFS= read -r rel; do
  cmp -s "$package/media/fat/$rel" "$fat/$rel" || changed=1
  case "$rel" in *.rbf) ;; *) [ -x "$fat/$rel" ] || changed=1;; esac
done <<EOF
$(targets)
EOF
if [ "$changed" = 0 ]; then
  verify_installed_targets
  if [ "$service_checks" = 1 ]; then
    stop_daemon
    "$fat/MegaVGMPlayer/megavgm_remote" -service start || fail 'Standalone Remote start failed'
    verify_running_remote
  fi
  echo 'Already installed and verified; no payload/startup changes and no new rollback checkpoint.'
  rm -rf "$work"
  exit 0
fi
backup=$(mktemp -d "$fat/MegaVGMPlayer/backups-v2.3-$(date +%Y%m%d-%H%M%S)-XXXXXX")
printf '%s\n' "$backup" > "$work/BACKUP"
: > "$backup/ABSENT"
: > "$backup/BEFORE.sha256"
: > "$backup/AFTER.sha256"
for_service=0
if [ "$service_checks" = 1 ] && "$daemon" -service status > "$work/service-status" 2>/dev/null; then
  service_pid=$(sed -n 's/^running pid=\([0-9]*\) .*/\1/p' "$work/service-status")
  service_sha=$(sed -n 's/.*sha256=\([0-9a-f]*\) .*/\1/p' "$work/service-status")
  cp "$proc_root/$service_pid/exe" "$backup/previous-daemon"
  [ "$(sha "$backup/previous-daemon")" = "$service_sha" ] || fail 'Running daemon identity changed'
  chmod 755 "$backup/previous-daemon"
  for_service=1
fi
printf '%s\n' "$for_service" > "$backup/WAS_RUNNING"
# Stage every target on the FAT filesystem and verify again before any replacement.
while IFS= read -r rel; do
  mkdir -p "$work/files/$(dirname "$rel")" "$backup/files/$(dirname "$rel")" "$fat/$(dirname "$rel")"
  if [ "$rel" = linux/user-startup.sh ]; then src="$work/startup"; else src="$package/media/fat/$rel"; fi
  cp "$src" "$work/files/$rel"
  [ "$(sha "$src")" = "$(sha "$work/files/$rel")" ] || fail "Stage mismatch: $rel"
  case "$rel" in *.rbf|*.sid|*.json) chmod 644 "$work/files/$rel";; *) chmod 755 "$work/files/$rel";; esac
  if [ -f "$fat/$rel" ]; then
    cp -p "$fat/$rel" "$backup/files/$rel"
    printf '%s  files/%s\n' "$(sha "$backup/files/$rel")" "$rel" >> "$backup/BEFORE.sha256"
  else printf '%s\n' "$rel" >> "$backup/ABSENT"; fi
  printf '%s  %s\n' "$(sha "$work/files/$rel")" "$rel" >> "$backup/AFTER.sha256"
done <<EOF
$paths
EOF
if [ -f "$backup/previous-daemon" ]; then
  printf '%s  previous-daemon\n' "$(sha "$backup/previous-daemon")" >> "$backup/BEFORE.sha256"
fi
touch "$backup/PREPARED"
printf 'Backup: %s\n' "$backup"
stop_daemon
stock_gate
# Recheck all originals after HTTP drain, before committing any file. A late
# operator edit or in-flight ENTER must not be silently overwritten.
while IFS= read -r rel; do
  if [ -f "$backup/files/$rel" ]; then
    cmp -s "$fat/$rel" "$backup/files/$rel" || fail "Changed during staging: $rel"
  else
    [ ! -e "$fat/$rel" ] || fail "Created during staging: $rel"
  fi
done <<EOF
$paths
EOF
# Each rename is atomic on the same FAT filesystem; journal supports interrupted installs.
: > "$backup/COMMITTED"
while IFS= read -r rel; do
  printf '%s\n' "$rel" >> "$backup/COMMITTED"
  mv -f "$work/files/$rel" "$fat/$rel"
done <<EOF
$paths
EOF
verify_installed_targets
if [ "$service_checks" = 1 ]; then
  "$fat/MegaVGMPlayer/megavgm_remote" -service start || fail 'Standalone Remote start failed'
  verify_running_remote
fi
printf '%s\n' "$backup" > "$work/last-backup"
mv -f "$work/last-backup" "$fat/MegaVGMPlayer/.v23-last-backup"
touch "$backup/COMPLETE"
rm -rf "$work"
echo 'Installed. Existing remote.sh and playlists.json untouched. Reboot and follow README hardware checks.'
