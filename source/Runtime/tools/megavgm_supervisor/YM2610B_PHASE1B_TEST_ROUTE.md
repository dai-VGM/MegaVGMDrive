# Fixed YM2610B Phase1B Player test route

## Scope and audit

This is an opt-in Supervisor-only resident-RBF selection, not a chip classifier
or automatic RBF switch. Do not use mixed-family playlists in this test.

Unchanged baselines:

- RBF source: `744d51ac6950b617004ad1ce9c83472a878a485c`, branch
  `golden-shell-v1.2-compat-phase1b`.
- QPF: `hw/golden_transport_phase1b/MegaVGMPlayer_GoldenTransport12Phase1B_YM2610B_MiSTer.qpf`.
- RBF: `MegaVGMPlayer_GoldenTransport12Phase1B_YM2610B_MiSTer.rbf`.
- Main: FIFO framing `a409745a00ca428999e909edb69646f1a5fc62d4`, strict SHA
  `a0e7b7d3557457a80ecd62a6bb4643585c33b78fbe515a7a7a5783b05b5addb5`.
- Host tools base: `294d63eebfd3b7d5625670fd3102f1c77435daf4`; Supervisor,
  Playlist and autoplay2 source is identical to `7e142fd` before this change.
- Current Remote: backend `9451ab4`, frontend `ff70f88`, runtime SHA
  `c1a3ba080472353ab6acf5d14db524a41bc9bd3d4e4ebfaf40ab85f99e985e60`.

Remote cold Playlist `coldPlaylistPlay` already invokes the Supervisor using
`enter --playlist-snapshot <immutable snapshot> <directory>`. Folder Play uses
`enter --start-file <file> <parent>`. Warm Playlist uses existing controller IPC.
None of these call sites or arguments changes. RBF selection was solely the
Supervisor `Paths.rbf` default. `LinuxRuntime::load_rbf`, prerequisite file check,
successor argv verification and diagnostics all consume that same path.

The Phase1B QIP selects `rtl/emu.sv` (CORENAME `MegaVGMDrive`) and the Phase1B
profile. Existing Supervisor accepts that CORENAME and the existing status-v2
parser. Remote validates mode/main/controller but does not require an
YM2151-specific `rbf` value. This is source compatibility evidence; complete
Player transport/audio PASS still requires the hardware checklist below.

## Route / ownership contract

```text
STOCK: test-profile ym2610b-phase1b
  -> private /tmp selector (no process/core change)
Remote existing Playlist Play
  -> existing enter --playlist-snapshot ...
  -> acquire original Supervisor flock
  -> resolve allowlisted RBF path (fail closed before stopping stock)
  -> original Main/bind/load_core/readiness/controller lifecycle
  -> original immutable snapshot and warm playlist IPC
  -> existing EXIT / natural completion restore stock
```

- No selector = original PlaylistLoopLab RBF, byte-for-byte original default path.
- Selector is `/tmp/megavgm_supervisor-test/profile`, within an owner-only 0700
  directory; file must be owner-owned, private, regular, non-symlink and exact
  allowlisted content. CLI mutation requires root. Publication is temp + fsync +
  close + atomic rename, under the existing instance flock.
- Setting/clearing requires no active/starting/draining owner and STOCK status
  (or absent first-boot status). Active-route changes are refused, never queued.
- Selection lasts across EXIT/ENTER until `test-profile default` or reboot.
  Reboot clears `/tmp` and returns to the normal route. No boot/service changes.
- Query reports the **next ENTER selection**, not proof of the loaded FPGA.
  Active evidence is Supervisor `rbf=YM2610B_PHASE1B` plus the verified Main
  `active_rbf_argv` and status-v2 publications.
- Missing selected RBF still fails the original preflight before stock is stopped.
- No RBF hash is invented: use the user's Windows-built, OSD-tested Phase1B RBF
  and verify its SHA across transfer. This patch neither produces nor changes it.

## Build

Use `build_test_route_arm.sh` inside the existing `mister-gcc10` Lima VM on a
fresh, explicitly copied source tree. It uses the existing official ARM GCC
10.2 hard-float toolchain, ARMv7/VFPv3 and `-static`. No Docker or Quartus.
Run host Supervisor/Playlist regressions first. The build also executes the ARM
Supervisor test binary under existing `qemu-arm-static`, executes a read-only
query in the exact shipped binary, and rejects PT_INTERP / DT_NEEDED.

## Safe hardware installation

First use existing Remote **Exit**, wait for `mode=STOCK`, `main=STOCK`,
`controller=STOPPED`. Do not replace an active Supervisor. Keep the currently
installed Main, controller, Remote and original PlaylistLoopLab RBF untouched.

Copy the new Supervisor as `megavgm_supervisor.ym2610b-test.new`, not over the
running binary. Copy the Windows RBF as its new filename, never over the MD RBF.
The delivery directory contains exact SCP commands and hashes in `INSTALL.md`.

On MiSTer, after comparing SHA256 to the delivery manifest:

```sh
cd /media/fat/MegaVGMPlayer
# Preserve existing backup if already present.
test -e megavgm_supervisor.pre-ym2610b-test || cp -p megavgm_supervisor megavgm_supervisor.pre-ym2610b-test
chmod 755 megavgm_supervisor.ym2610b-test.new
mv megavgm_supervisor.ym2610b-test.new megavgm_supervisor
./megavgm_supervisor test-profile ym2610b-phase1b
./megavgm_supervisor test-profile
```

Now use the unchanged Remote Playlist screen, choose a playlist containing only
supported YM2610/YM2610B VGM files, and Play its desired row. The default Favorites
CTA is not a family selector; do not use it if Favorites contains mixed families.
There is no automatic compatibility check in this phase.

For returning to the regular route: Remote Exit, wait for STOCK, then:

```sh
/media/fat/MegaVGMPlayer/megavgm_supervisor test-profile default
```

Next ordinary Remote Play uses the original PlaylistLoopLab RBF. To remove the
test Supervisor entirely, while STOCK copy the preserved backup to a `.restore`
file and atomically rename it over `megavgm_supervisor`; do not overwrite an
active executable. No Remote daemon restart or autostart change is necessary.

## Hardware evidence and PASS gate (not claimed by host tests)

Read `/tmp/megavgm_supervisor.status`, `/tmp/MegaVGMPlayer.status`,
`/tmp/megavgm_playlist.status`, `/tmp/megavgm_load_file.status` and
`/tmp/megavgm_load_file.log`. Preserve copies before EXIT/reboot.

1. Cold Playlist: selected index/count and immutable snapshot match the Playlist,
   not its parent folder; `rbf=YM2610B_PHASE1B` and active Main argv names the
   Phase1B RBF. No second bootstrap or duplicate first VGM transfer.
2. Session increments exactly once per accepted index-1 load; status advances
   LOADING -> PLAYING -> ENDED (or FATAL on genuine failure). Busy/done and
   loop-valid/count retain reference meanings; index-2 does not start a session.
3. Warm Next and 20+ repeated loads, including loop->loop, loop->EOF, EOF->loop.
   Each request gets exactly one Main transfer and one new session.
4. Natural EOF and Manual Next: original 100ms fade. Native loops: loop1 measured,
   loop2 last ~2s fades to boundary zero, no loop3, one ENDED then next.
5. Repeat One, Repeat Context, Stop (immediate), Stop->Next, rapid Next.
6. FM/SSG/ADPCM-A/ADPCM-B: no old-session garbage, no permanent mute, no missing
   next-track attack. No old audio reappearance after index-2 policy completion.
7. Final completion / explicit Exit restores stock Main; profile change while
   active refuses; default selection then cold MD Playlist remains functional.

Only after these hardware checks PASS proceed to any Phase2 classifier/RBF switch.

## Local verification performed

- macOS Supervisor host suite: PASS (Unix socket fixtures require sandbox access).
- macOS Playlist / control / playback-mode / CLI suite: PASS.
- Unchanged Remote `9451ab4`, `go test ./cmd/remote/megavgm`: PASS, including cold
  snapshot, cold/warm queue equivalence and request-lifecycle regressions.
- Direct call to that unchanged Remote parser with `rbf=YM2610B_PHASE1B` in
  STOCK/STARTING/MEGAVGM fixtures: PASS.
- ARMv7 hard-float static Supervisor suite under existing qemu-arm-static: PASS.
- Exact stripped delivery binary default-profile query: PASS.
- readelf: EABI5 hard-float / VFP-register ABI; no PT_INTERP or DT_NEEDED.
- Diff scope: Supervisor selection/metadata/tests/build/docs only; Linux runtime
  lifecycle implementation, controller/autoplay2, Main, Remote, RTL and QPF/QSF
  unchanged. No hardware installation or Player hardware PASS claimed here.
