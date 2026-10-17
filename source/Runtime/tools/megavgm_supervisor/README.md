# MegaVGMPlayer Supervisor S1

`megavgm_supervisor` owns one temporary MegaVGMPlayer lifecycle without
changing the FAT-resident stock `/media/fat/MiSTer` file.

S1 uses these fixed, reviewable inputs:

```text
stock Main:    /media/fat/MiSTer
modified Main: /media/fat/MegaVGMPlayer/MiSTer.megavgm
RBF:           /media/fat/MegaVGMPlayer/MegaVGMPlayer_PlaylistLoopLab_MiSTer.rbf
controller:    /media/fat/Scripts/megavgm_playlist
```

The modified Main must have SHA-256:

```text
ae6e050f87749962a354b0879bac45f33e58be64fb3892d4157a1754407f955e
```

Enter with one directory and the Phase 1E default of two native loops:

```sh
/media/fat/MegaVGMPlayer/megavgm_supervisor enter \
  "/media/fat/MegaVGMDrive/01_Arcade/Galaxy_Force_II_(Sega_Y)"
```

The CLI forks a new session and redirects the supervisor before the verified
stock Main is stopped. The resident child owns an advisory `flock`, a
root-only Unix socket, the modified Main process, and the playlist process.
It reports success only after the modified Main executable hash, active
MegaVGM core name, controller FIFO, and controller status are verified.

Exit and inspect status with:

```sh
/media/fat/MegaVGMPlayer/megavgm_supervisor exit
/media/fat/MegaVGMPlayer/megavgm_supervisor status
```

The read-only diagnostic command below hashes the configured modified Main
without entering MegaVGM mode or stopping stock Main. It prints the exact path,
file size, expected and actual SHA-256 values, hash success, and captured errno.

```sh
/media/fat/MegaVGMPlayer/megavgm_supervisor hash-main
```

`exit` is idempotent across automatic restoration. If a normal playlist
completion already owns restore, it reports `RESTORE_IN_PROGRESS`; after stock
mode is published it reports `ALREADY_STOPPED` instead of exposing a vanished
control-socket error.

Runtime files:

```text
/tmp/megavgm_supervisor.lock
/tmp/megavgm_supervisor.sock
/tmp/megavgm_supervisor.status
/tmp/megavgm_supervisor.log
/tmp/megavgm_playlist.stderr
/tmp/megavgm_playlist.trace
/tmp/megavgm_load_file.status
```

The supervisor status also preserves passive controller diagnostics across
rollback: child PID, exec result, exit code or signal, concise captured stderr,
first-request trace, the last Main `load_file` boundary, MegaVGM status
readiness at launch, controller FIFO/status observation, active modified-Main
SHA-256, and the verified RBF argv. The request trace records the initial FPGA
session, exact path, successful full FIFO write, session after the request, and
timeout elapsed time. The Main boundary record distinguishes command parsing,
file-open failure, transfer entry, and transfer success/failure without changing
the transfer itself.

The RBF is loaded through the existing Main-owned `/dev/MiSTer_cmd`
`load_core` endpoint. The supervisor never programs the FPGA directly.
The Phase 1F controller remains the sole owner of `load_file`, sessions,
loop policy, and NEXT/PREV.

Before launching the controller, S1 waits up to ten seconds for both the core
identity and a status record accepted by the same strict v1/v2 parser used by
the controller. A missing or temporarily incomplete record may become ready
within that bound; a persistently missing, malformed, or unsupported record
causes safe rollback. This is a readiness predicate, not a fixed delay.

MiSTer Main intentionally restarts itself after an RBF load. The process that
accepted `load_core` exits after forking a successor, and the successor runs
the same Main binary with the requested RBF as an argument. The supervisor
therefore reacquires Main ownership by executable SHA-256 and exact RBF argv;
it does not treat the initially launched PID as permanent. A missing successor
is accepted as a crash only after a bounded stabilization window.

The Phase 1F controller atomically publishes `state=COMPLETE` before returning
success. A controller exit with that final state is a normal lifecycle event:
S1 performs an orderly automatic restore and publishes stock mode. An exit
without `COMPLETE` remains a failure and uses the same recovery path.

If the modified Main or playlist process exits unexpectedly, S1 stops the
remaining process, removes controller runtime files, unmounts the bind,
verifies the uncovered stock file hash, and restores stock Main. A stock hash
mismatch is a hard failure: S1 will not execute an unverified path.
Before unmounting, rollback repeatedly stops every MiSTer process whose
executable SHA matches the modified Main or whose executable is the active bind
target. It requires zero qualifying processes to remain continuously for 1.5
seconds; a late double-fork successor resets that stability window and is also
stopped. Stock SHA verification is never attempted after a failed unmount.

S1 deliberately does not detect a manually loaded non-MegaVGM core. Use the
explicit `exit` command to restore stock Main after such a load. Core-change
interception belongs to a later phase.

The bind mount exists only in RAM/kernel state. The supervisor never opens
`/media/fat/MiSTer` for writing, and a power cycle removes the bind mount, so
normal stock boot remains the invariant.

Build and host-test:

```sh
make
make test
```
