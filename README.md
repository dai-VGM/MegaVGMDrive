# MegaVGMPlayer v2.1 — Independence Day

Phase 2 packaging: [release/README.md](release/README.md),
[validation](release/VALIDATION.md), and
[hardware acceptance](release/HARDWARE_CHECKLIST.md).
Branch: `v2.1-independence-phase2`. Phase 1 is now user-confirmed hardware PASS;
Phase 2 reboot/autostart acceptance is pending. The daemon is promoted byte-for-byte,
not rebuilt. The remainder below is the historical Phase 1 development record.

## Phase 1 record (at initial implementation)

Standalone HTTP daemon, **host-validated candidate; MiSTer/iPhone not yet validated**.
Branch: `v2.1-independence-phase1`. No autostart, installer migration or restoration
of original MiSTer Remote is performed in this phase.

## Architecture

```text
Browser / PWA (:8183/megavgm)
  dedicated header + unchanged v2.0 Player
  same-origin /api/megavgm/*
    megavgm_remote
      existing MegaVGM Adapter / JSON persistence / status parser
        megavgm_supervisor (Start / Exit / cold snapshot)
        megavgm_ctl (Play / Next / Prev / Stop / Repeat / Shuffle)
          existing Phase2A controller, Main and sound engines

MiSTer Remote (:8182) remains a separate, unchanged service.
```

The five production MegaVGM Go files and all Player components are byte-identical
to the frozen v2.0 inputs. Only a new router, manual service lifecycle, monitor
shutdown hook and dedicated frontend shell are added. See [PROVENANCE.md](PROVENANCE.md).

The 21 path/method/handler mappings and MegaVGM frontend API method bodies are
unchanged. Existing status/error JSON, snapshot handoff, operation generations,
diagnostic convergence, Transport Status and soundChips remain owned by that code.
No new playback owner, controller protocol or switch-generation counter exists.

Removed: Remote common Layout, drawer/Connect dialog/PlayingButton, WebSocket,
sysinfo/peers/music/logo/settings endpoints, uinput, tracker/tasks, games, SSH sync,
ArcadeDatabase and curses service UI. No fake WS server. Unused Remote frontend
runtime dependencies are removed from package.json/lock, not just hidden in the UI.

The standalone header intentionally contains the existing centered logo only:
the Remote drawer and Remote core popup button do not become transport buttons.
The unchanged Player owns Browse/Playlists, mini-player, controls and bottom tabs.
The v2.0 iOS standalone `100lvh` rule, safe-top once in header and safe-bottom once
in navigation are retained. Chromium emulation is not evidence of iOS hardware PASS.

## Persistence and dependencies

- Library: `/media/fat/MegaVGMDrive/`
- Favorites/Playlists: `/media/fat/Scripts/.config/megavgm/playlists.json`
- Controller status/FIFO: `/tmp/megavgm_playlist.status`, `/tmp/megavgm_playlist.cmd`
- Supervisor: `/media/fat/MegaVGMPlayer/megavgm_supervisor`
- Supervisor status: `/tmp/megavgm_supervisor.status`
- Existing helper: `/media/fat/Scripts/megavgm_ctl` (exact SHA below)

No schema change/migration. **Only one MegaVGM HTTP operation owner at a time.**
During Phase 1 use only :8183 for Player, Favorites or Playlist mutations. Close
the :8182 MegaVGM UI/PWA tabs. Ordinary non-MegaVGM Remote use on :8182 is fine.
There is deliberately no cross-daemon persistence lock/protocol change in this phase.

## Manual service

```sh
/media/fat/MegaVGMPlayer/megavgm_remote.phase1 -service start
/media/fat/MegaVGMPlayer/megavgm_remote.phase1 -service status
/media/fat/MegaVGMPlayer/megavgm_remote.phase1 -service restart
/media/fat/MegaVGMPlayer/megavgm_remote.phase1 -service stop
# Foreground alternative (not together with start):
/media/fat/MegaVGMPlayer/megavgm_remote.phase1 -service exec
```

Runtime: `/tmp/megavgm_remote`, `.pid`, `.identity`, `.lock`, `.start.lock`, `.log`.
`start` stages its own executable into /tmp, waits for a successful :8183 bind,
then returns. A lifetime flock and launcher flock prevent concurrent starts.
PID/start-time/executable SHA are checked before signalling. Bind errors are
explicit; no fallback port. Log output from `start` children goes to `.log`;
foreground `exec` logs to stderr. Existing handoff trace remains
`/tmp/megavgm_remote_playlist_handoff.log`.

`stop` drains HTTP and only stops this daemon. It sends **no Stop or Supervisor
Exit**. An accepted request is allowed to finish. If draining exceeds the CLI
deadline, the command reports an error rather than force-killing the process.
`restart` rereads the current status files; it does not reconstruct/reset the queue.
After a crash no automatic respawn occurs in Phase 1; manual start/restart can
replace stale PID records only after acquiring the free service lock.

No authentication is introduced: keep this LAN-only, do not forward port 8183 to
the Internet. The browser uses same origin; no permissive CORS middleware is added.
`-test-root` and `-runtime-dir` are explicit isolated Linux test options, not hardware
deployment settings. Do not use them on MiSTer.

## Build and host tests

```sh
cd frontend
npm ci
npm run build
cd ..
cp -R frontend/build/. cmd/megavgm_remote/web/build/
go test ./internal/megavgm
python3 tests/provenance.py   # requires the frozen local reference worktrees
# In existing remote3-arm-gate Lima, not on macOS:
sh tests/build-arm.sh
```

Frontend lock preserves the existing library versions. Build requires Go 1.21.9
and the existing ARM hard-float GCC in the Lima build environment. Do not install
Docker or run Quartus. Tests and execution distinctions are in [VALIDATION.md](VALIDATION.md).

## Safe hardware deployment (manual, no autostart)

1. Exit current playback through the existing Player if necessary; confirm STOCK
   in `/tmp/megavgm_supervisor.status`. Close all :8182 MegaVGM tabs.
2. Record existing :8182 PID/SHA and back up `playlists.json` while there are no
   writers. Do not replace `remote.sh` or change `user-startup.sh`.
3. Upload only the new daemon under a staging name (substitute the IP):

```sh
scp /Users/daizo/Projects/MegaVGMPlayer_Standalone_Phase1/artifacts/megavgm_remote.phase1 \
  root@<MiSTer-IP>:/media/fat/MegaVGMPlayer/megavgm_remote.phase1.new
```

4. On MiSTer, compare SHA with the delivered manifest, and independently verify
   the already-installed helper before starting:

```sh
sha256sum /media/fat/MegaVGMPlayer/megavgm_remote.phase1.new
sha256sum /media/fat/Scripts/megavgm_ctl
# helper must be 378905c80c22f0b072e248d6fdb67238f2727a38287f4407b2596c8c2a9ae45b
# First install only: if a previous Phase1 exists, stop and back it up first.
test ! -e /media/fat/MegaVGMPlayer/megavgm_remote.phase1 || exit 1
chmod 755 /media/fat/MegaVGMPlayer/megavgm_remote.phase1.new
mv /media/fat/MegaVGMPlayer/megavgm_remote.phase1.new /media/fat/MegaVGMPlayer/megavgm_remote.phase1
/media/fat/MegaVGMPlayer/megavgm_remote.phase1 -service start
/media/fat/MegaVGMPlayer/megavgm_remote.phase1 -service status
sha256sum /proc/$(cat /tmp/megavgm_remote.pid)/exe
netstat -lntp | grep -E ':(8182|8183)[[:space:]]'
curl -i http://127.0.0.1:8183/megavgm
curl -i http://127.0.0.1:8183/api/megavgm/status
```

A helper hash mismatch is a stop condition; do not silently replace it. The copied
`artifacts/megavgm_ctl.production` is a dependency/provenance record, not an install
instruction. No Supervisor/controller/Main/RBF/importer artifact is rebuilt.

5. Open `http://<MiSTer-IP>:8183/megavgm`. A new port is a new browser origin; an
   existing home-screen shortcut to :8182 does not automatically move. For iPhone
   standalone testing add the :8183 page to the home screen separately.

## Rollback / stop

```sh
/media/fat/MegaVGMPlayer/megavgm_remote.phase1 -service stop
```

Close the :8183 UI, verify :8183 is no longer listening, then use the unchanged
:8182 Player again. Stop does not terminate playback; use the explicit Player
Stop/Exit when desired. Do not restore an old playlists.json over new user changes.
No boot scripts or production binaries need rollback, because none were changed.
Reboot removes the manual daemon until the next manual start (Phase 1 by design).

## Hardware acceptance — all pending

- :8182 and :8183 each have one listener; :8182 executable/SHA unchanged.
- Existing Favorites/Playlists visible; CRUD persists across daemon restart.
- Cold Favorites/Playlist first Play: exact snapshot, short-track Loading clears.
- Warm Play/Next/Previous, rapid selection, Repeat One/Context, Shuffle, Stop.
- A→B→A: automatic engine changes; A→A/B→B: no unnecessary reload.
- Playlist completion/explicit Exit restore STOCK through existing Supervisor.
- Stop/restart **daemon** during playback: audio continues, current state reconnects.
- iPhone PWA 320/393: logo/icons, safe areas, Browse/Playlist scroll restore,
  only content scrolls, no Remote connect/drawer/core popup.
- No interaction with the :8182 MegaVGM UI during this test.

Do not proceed to autostart/installer migration/original Remote restoration until
Phase 1 hardware acceptance is complete.
