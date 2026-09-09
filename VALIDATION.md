# Phase 1 validation boundaries

## Host PASS

- Frozen backend: 60 original Go tests, unchanged, macOS and native Linux.
  Browse/path rejection, Favorites/Playlist CRUD and version-one persistence,
  folder and snapshot playlist dispatch, Stop/Next/Prev/Repeat/Shuffle/Exit,
  cold acceptance without captured-pipe EOF waiting, operation supersession,
  delayed publication, status/Transport Status/soundChips and error contracts.
- 21 method/path/handler mappings match the old Remote exactly.
- Frontend production TypeScript/Vite build.
- Original pure state/render/API tests and original DOM operation suite.
  Cold short-track before HTTP ACK; missed first PLAYING; stale ACK suppression;
  Stop/Next/Prev races; long/warm track; timeout cleanup; 100 transitions;
  authoritative Switching terminal/stale-generation handling.
- Dedicated production bundle browser test, actual HTTP fixture, not old Layout:
  320 and 393 by 852 standalone Chrome, safe-top 59 / safe-bottom 34.
  Shell bottom 852, header 103 (59+44), nav bottom 852, nav padding-bottom 34.
  Content is the only scroll owner; Browse/Playlists independent positions restore;
  repeated boundary scrolling leaves header/mini-player/nav stationary.
  All API requests are `/api/megavgm/*` on the fixture origin (not hardcoded 8183).
  No Remote endpoint request or WebSocket created. Four screenshots under `evidence/`.
- Linux-native service gate: fixed port, bind conflict, duplicate/concurrent starts,
  verified PID identity, stale/forged PID refusal, stop, restart, crash/manual restart,
  in-flight command drains before shutdown. Disconnect/restart issue no extra
  playback commands. Existing current session/status reread after restart.
- Exact distributed ARM executable, QEMU foreground: `/megavgm`, `/megavgm/`,
  embedded JS/CSS/logo/fonts, manifest/all icons HTTP 200; all Remote-only routes
  tested return 404. Existing fixture playlists/favorites, CRUD, controls, error
  JSON, Transport Status and soundChips tested over real HTTP.
- A→B→B→A **status fixtures** accept rebased session 57→1 and forward current
  profile/generation; STOCK fixture is reflected. These are not hardware switches.
- Byte equality of frozen Player components and five backend production files.
- Exact production helper recovered; saved compile sources match 9e2dd45;
  official GCC recipe plus OSABI metadata normalization reproduces exact SHA.

## Honest limitations / issues encountered

- No MiSTer execution, sound output, real engine switching or iPhone PWA test yet.
  Hardware acceptance checklist remains entirely pending in README.
- QEMU user-mode synthesizes `/proc/self/stat` (start-time 0) and self executable,
  but another process's `/proc/<pid>` exposes host QEMU identity. Therefore the
  PID identity service gate is run **natively**, not weakened to pass QEMU.
  Exact ARM HTTP/API gate uses foreground processes controlled by the test runner.
- One first native Linux run of original tests failed during TempDir removal:
  an existing background diagnostic trace writer was still writing after a test.
  The production/test files were not changed to conceal this. A subsequent Linux
  run passed; macOS suite passed. This is an inherited asynchronous fixture-cleanup
  race, not proof of a Player behavior regression. Do not describe it as hardware PASS.
- Initial extended service fixture delayed the helper 1 second and correctly hit
  the existing 750 ms control timeout. The fixture was corrected to 250 ms; no
  production timeout was extended.
- Existing Lima root/tmp capacity was exhausted. New build caches/temp files used
  available `/dev/shm`; no old user artifacts were deleted and no Docker/new VM
  or toolchain was installed.
- Shared playlist persistence still requires the documented single active
  MegaVGM daemon operator. Concurrent :8182/:8183 writes are not supported/tested.
- Phase 1 service has no auto-respawn/autostart, log rotation or Internet-facing
  authentication. Those are not silently added during transport extraction.

## Reproduction commands

```sh
python3 tests/provenance.py
go test ./internal/megavgm
cd frontend && npm ci && npm run build && cd ..
# Copy production build into embed root before compiling Go:
cp -R frontend/build/. cmd/megavgm_remote/web/build/

# Pure TS/render/API tests (esbuild comes from existing Vite dependency):
for test in frontend/src/components/megavgm*.test.ts frontend/src/components/*.render.test.tsx frontend/src/lib/megavgmApi.test.ts; do
  frontend/node_modules/.bin/esbuild "$test" --bundle --platform=node --format=cjs --outfile=evidence/unit.cjs
  node evidence/unit.cjs || exit 1
done
# Existing jsdom + fake-timers dependencies needed for the imported DOM harness:
frontend/node_modules/.bin/esbuild frontend/src/components/MegaVGMPlayer.operation.test.tsx --bundle --platform=node --format=cjs --outfile=evidence/operation.cjs
NODE_PATH=/private/tmp/megavgm-loading-fix.be6tIG/node_modules node tests/run-play-operation-dom.cjs evidence/operation.cjs
node tests/browser.cjs

# Native Linux, isolated filesystem and fake CLI helpers only:
go build -o /tmp/megavgm_remote-native ./cmd/megavgm_remote
python3 tests/service_gate.py /tmp/megavgm_remote-native
# Existing Linux QEMU/binfmt environment, exact ARM candidate:
python3 tests/service_gate.py /tmp/megavgm_remote.phase1 --foreground
```

Do not run the service test on MiSTer: port 8183 fixtures are deliberately isolated.
Original production code does not link the test runner or fixtures.
