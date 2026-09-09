# Phase 1 candidate — 2026-09-09

Hardware state: **UNTESTED on MiSTer/iPhone**. No deployment or autostart change.

## Delivered files

| Artifact | Absolute path | Bytes | SHA-256 |
|---|---|---:|---|
| New daemon | `/Users/daizo/Projects/MegaVGMPlayer_Standalone_Phase1/artifacts/megavgm_remote.phase1` | 10056304 | `2826b15574e080b74ec656241f2a989d769787d61faf9f49b734a73fbda1c61e` |
| Existing helper, preserved copy | `/Users/daizo/Projects/MegaVGMPlayer_Standalone_Phase1/artifacts/megavgm_ctl.production` | 961808 | `378905c80c22f0b072e248d6fdb67238f2727a38287f4407b2596c8c2a9ae45b` |

Implementation commit: `46f17f85d74d5cd74431413d56b851b37e61c104`.
Exact final build archive: `eb7fad88a1fff39cdaeaebb157f56eb70040a627`
(second commit changes only test cleanup/provenance documentation).
Branch: `v2.1-independence-phase1`.

Go embedded module inspection: Go 1.21.9; linux/arm/GOARM=7, CGO=1;
sole third-party Go module `github.com/gorilla/mux v1.8.0`.
ELF32 ARM, EABI5 hard-float flags `0x5000400`; VFP register ABI;
static; no PT_INTERP; no dynamic section/DT_NEEDED; stripped.
BuildID: `960f1004c0c846c352c5debe6caba6786b9b5cb4`.

## Exact final ARM HTTP gate

Executed the above SHA in existing `mister-gcc10` Lima QEMU/binfmt, foreground
with isolated fake status/filesystem/CLI helpers. No MiSTer access.

- `/megavgm` and `/megavgm/`: HTTP 200, identical HTML
- Embedded JS: `/assets/megavgm-fd0d8574.js`, HTTP 200
- JS SHA: `0319f8dee63e78d369e98afd4018f8c9560a248b8c916a7ca409c0995d96cef5`
- CSS/fonts/header logo and HTML-linked icons: HTTP 200
- `/megavgm-manifest.json`: HTTP 200
- `/megavgm-vgm-play-v2-180.png` (Apple), `-192.png` (favicon/manifest),
  `-512.png` (manifest): HTTP 200
- Existing Favorites/Playlist JSON, CRUD, control/error responses,
  Transport Status and soundChips: PASS
- Remote-only `/api/ws`, `/api/sysinfo`, peers and music endpoints: HTTP 404
- HTTP disconnect, restart status reconnect, in-flight command drain: PASS
- Final fixture evidence directory in VM: `/tmp/megavgm-phase1-gate-zv07n4go`

Service PID identity, duplicate/concurrent start, bind conflict, forged PID
protection and crash/manual restart were additionally tested on native Linux from
the same source. Final native fixture: `/dev/shm/megavgm-phase1-tmp/megavgm-phase1-gate-at8vil1_`.
QEMU identity limitations are documented in VALIDATION.md; no service check was
weakened for emulation.

## Frontend evidence

- [320 Browse](evidence/standalone-320-browse.png)
- [320 Playlists](evidence/standalone-320-playlists.png)
- [393 Browse](evidence/standalone-393-browse.png)
- [393 Playlists](evidence/standalone-393-playlists.png)
- [Browser measurements / request paths](evidence/browser.json)

These are Chrome standalone production-bundle fixtures, not iPhone photographs.
Safe-top 59 and safe-bottom 34 are explicit emulation values. Real iOS validation
is still required.

Deployment target is **only** `/media/fat/MegaVGMPlayer/megavgm_remote.phase1`.
Use README staging/SHA checks. Existing helper only needs hash verification, not
replacement. Keep existing Remote, Supervisor/controller/Main/RBF/importer intact.

No installer, boot registration, Phase 2 change or original Remote restoration.
