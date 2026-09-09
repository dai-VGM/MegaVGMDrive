# Phase 2 exact hardware acceptance — NOT YET RUN

1. Install from STOCK; preserve the printed backup. Confirm existing remote.sh,
   favorites block, and playlists.json have not changed.
2. Reboot with no test-profile setup or manual service start.
3. `megavgm_remote -service status` (use full runtime path) reports exactly one daemon;
   `netstat -lntp` shows 8183 and the independent 8182 listener.
4. `sha256sum /proc/<standalone-pid>/exe` equals
   `9cb59cb4032843a7e9b8368941540904da5d995df7d0b443b9e317f5a642cd7e`.
   Confirm `/proc/<pid>/exe` resolves to `/tmp/megavgm_remote`.
5. Supervisor status is STOCK, with stock Main. Autostart alone must not ENTER.
6. Open `http://<MiSTer-IP>:8183/megavgm`; GET /megavgm and /megavgm/ are 200.
   Embedded HTML refers to `assets/megavgm-36f68731.js`; JS, manifest/icons are 200.
7. Existing Favorites/Playlists remain. Play mixed A→B→A, then same-profile tracks;
   only profile boundaries reload an engine. Verify Next/Previous/Stop/Repeat/Shuffle.
8. During playback, restart only megavgm_remote: audio continues and status reconnects.
9. Playlist completion returns to STOCK automatically.
10. On iPhone PWA, bottom Browse/Playlists labels are visible; content alone scrolls.
11. Reboot again; 8183 starts automatically, 8182 still works, Main starts STOCK.
12. Verify normal MiSTer Remote controls at 8182 without opening its old MegaVGM UI.

If a check fails, capture runtime SHA, service log and Supervisor/controller status.
Do not replace or rebuild the Phase 1 rescue artifact. Return to STOCK and use rollback.
