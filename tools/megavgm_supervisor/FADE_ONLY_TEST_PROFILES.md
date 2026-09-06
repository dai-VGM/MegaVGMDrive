# Transport v1.3 FADE_ONLY Supervisor test profiles

Base: `4ac6809d3d062298ad39f13ba7cf805b1b8d0d6c` fixed YM2610B test route.
This extension changes only the profile allowlist/path mapping and CLI help.
The existing atomic selector, ENTER flock, prerequisite verification, Main
bind/start/successor verification, controller and restore lifecycle are unchanged.

| CLI selection | Status label | Resident RBF |
|---|---|---|
| default | YM2151_SEGAPCM | /media/fat/MegaVGMPlayer/MegaVGMPlayer_PlaylistLoopLab_MiSTer.rbf |
| ym2610b-phase1b | YM2610B_PHASE1B | /media/fat/MegaVGMPlayer/MegaVGMPlayer_GoldenTransport12Phase1B_YM2610B_MiSTer.rbf |
| fade-only-a | FADE_ONLY_A | /media/fat/_Utility/MegaVGMPlayer_Transport13FadeOnly_A_MiSTer.rbf |
| fade-only-b | FADE_ONLY_B | /media/fat/_Utility/MegaVGMPlayer_Transport13FadeOnly_B_MiSTer.rbf |

The exact modified Main remains `/media/fat/MegaVGMPlayer/MiSTer.megavgm`, SHA256:
`a0e7b7d3557457a80ecd62a6bb4643585c33b78fbe515a7a7a5783b05b5addb5`.
Wrong SHA or missing selected RBF refuses entry before stock Main is stopped.
Selecting a profile does not load an RBF or replace Main. The NEXT Supervisor
ENTER (including normal Remote cold Playlist Play) uses the selection. Direct
OSD launch from _Utility under stock Main does NOT activate modified Main.

Selection is STOCK-only. Held ENTER/restore lock, non-STOCK status, invalid
selector records, symlinks or unsafe directory ownership/mode are rejected by
the existing mechanism. The selector in `/tmp/megavgm_supervisor-test/profile`
survives Exit/Enter but not reboot; `test-profile default` removes it. There is
no automatic classifier, mid-session profile switch or RBF relocation.

## Build and evidence

Use the unchanged `build_test_route_arm.sh` in the existing `mister-gcc10` Lima
VM, after transferring the exact commit's Supervisor/autoplay2 source archive
into a fresh VM directory. No mirrored /Users path is assumed to be current.
Compiler: official ARM A-profile GCC 10.2-2020.11, ARMv7-A/VFPv3/hard-float,
`-O2 -std=c++14 -Wall -Wextra -Wpedantic -Werror -static`.
The script runs the ARM test suite under qemu, strips the delivered Supervisor,
checks ELF32 EABI5/hard-float and absence of PT_INTERP/DT_NEEDED, then hashes it.
No Main/controller/Remote/RBF artifact is rebuilt by this task.

Host tests include both new paths and exact Main hash, snapshot preservation,
equal lifecycle calls, duplicate selection, refusal for all active/restore/failure
states and held lock, invalid/traversal records, atomic-write failure retention,
default restoration, plus all existing Supervisor safety/restore/SHA regressions.
Local socket tests require permission to create Unix sockets; sandbox denial is
an environment restriction, not a reason to weaken those tests.

The delivery directory contains BUILD.md with the final source commit, archive
and binary hashes and exact build evidence. These host/ELF tests do not claim
hardware playback or index-2 transfer PASS.

## Install (Supervisor only)

1. Remote Exit if a Supervisor session is active. Confirm STOCK/main STOCK/
   controller STOPPED and that no old Supervisor owns the session. If no
   Supervisor has ever entered, missing status is allowed by existing semantics;
   verify stock Main SHA and no running controller. Do not remove a lock/status
   file to bypass an active owner.
2. Copy the new binary to a separate `.fade-only.new` path, not over a running
   executable. Compare its SHA to the delivery SHA256SUMS and verify Main SHA.
3. While still STOCK, create a previously unused backup filename for the old
   Supervisor; do not overwrite existing rescue backups. chmod the staged file
   and rename it to `/media/fat/MegaVGMPlayer/megavgm_supervisor`.
4. Do not replace Remote, Main, controller or either RBF. RBFs are already in
   _Utility at the exact paths above.

## A/B selection and actual ENTER

```sh
/media/fat/MegaVGMPlayer/megavgm_supervisor test-profile fade-only-a
/media/fat/MegaVGMPlayer/megavgm_supervisor test-profile
```

Then use the existing Remote Playlist Play on a supported A-family track.
Alternatively use the existing `megavgm_supervisor enter <actual-folder>` CLI;
this launches the existing folder controller, not an idle standalone mode.
Do not launch the RBF directly from _Utility as a substitute for ENTER.

After Exit and STOCK, B uses exactly the same sequence with `fade-only-b` and
a YM2610/YM2610B-only playlist. No automatic sound-family selection is provided.

After ENTER:

```sh
cat /tmp/megavgm_supervisor.status
cat /tmp/MegaVGMPlayer.status
cat /tmp/megavgm_playlist.status
for megavgm_main_pid in $(pidof MiSTer); do
  readlink /proc/$megavgm_main_pid/exe
  sha256sum /proc/$megavgm_main_pid/exe
  tr '\000' ' ' < /proc/$megavgm_main_pid/cmdline
  echo
done
```

Require MEGAVGM / MODIFIED / RUNNING, the requested profile and RBF argv,
exactly one current Main with the modified SHA above, and FPGA PLAYING.
The executable symlink may still display `/media/fat/MiSTer` because the existing
Supervisor uses a bind mount: runtime SHA, not pathname alone, proves the binary.
Inspect `/tmp/megavgm_load_file.log` and `.status` after the first scripted VGM
load. These files are created by modified Main when requests are processed, not
merely by test-profile selection. OSD playback alone is not log proof.

## FADE_ONLY send / isolated ENDED observation

Use a long PLAYING track. The unmodified controller automatically advances on
ENDED; otherwise it can immediately issue the next index-1 and obscure this
standalone fade-only test. For isolation only, identify its exact PID from
Supervisor status, verify `/proc/<pid>/cmdline`, then temporarily SIGSTOP that
controller (not Main or Supervisor). Do not stop/kill its lifecycle. Remember
the PID and SIGCONT it after observing ENDED, BEFORE Remote Exit. Do not use
Remote playback commands while it is paused. This is an optional manual test
procedure, not a controller or Supervisor code change.

```sh
printf '\115\126\002\002' > /tmp/megavgm_fade_only.control
od -An -tx1 /tmp/megavgm_fade_only.control
printf 'load_file 2 /tmp/megavgm_fade_only.control\n' > /dev/MiSTer_cmd
tail -40 /tmp/megavgm_load_file.log
cat /tmp/megavgm_load_file.status
cat /tmp/MegaVGMPlayer.status
```

Payload must be `4d 56 02 02`. Require Main's received/accepted/transfer events
for this index-2 path and TRANSFER_SUCCESS, then the same FPGA session ENDED
after the existing ~100ms fade. FIFO write success alone proves neither transfer
nor ENDED. With controller parked, no new index-1 should occur and output must
stay zero. Duplicate FADE_ONLY and policy 0/1 must not re-output old audio.
Resume the controller with SIGCONT on the verified saved PID; normal auto-next
may then occur. Test ordinary next/load and stock restore separately.

## Default restoration

Resume any deliberately paused controller first. Remote Exit (or the existing
Supervisor `exit`) -> verify STOCK, then:

```sh
/media/fat/MegaVGMPlayer/megavgm_supervisor test-profile default
/media/fat/MegaVGMPlayer/megavgm_supervisor test-profile
```

Expect YM2151_SEGAPCM and the original PlaylistLoopLab path. The next normal
Remote Play uses the unchanged default route. After Exit the current Main SHA
should again be the user's stock SHA
`7ca3cd2f224b9264d0889f593a0d77aafa5adda61910baba92c5ae401e26fcce`.
Phase 2A switching stays blocked on actual FADE_ONLY A/B hardware validation.
