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
04cafec381e7ecd49b1a4333be1fd7de0a9acf29a42e9c8342db299fb7c3bb1f
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

Runtime files:

```text
/tmp/megavgm_supervisor.lock
/tmp/megavgm_supervisor.sock
/tmp/megavgm_supervisor.status
/tmp/megavgm_supervisor.log
```

The RBF is loaded through the existing Main-owned `/dev/MiSTer_cmd`
`load_core` endpoint. The supervisor never programs the FPGA directly.
The Phase 1F controller remains the sole owner of `load_file`, sessions,
loop policy, and NEXT/PREV.

If the modified Main or playlist process exits unexpectedly, S1 stops the
remaining process, removes controller runtime files, unmounts the bind,
verifies the uncovered stock file hash, and restores stock Main. A stock hash
mismatch is a hard failure: S1 will not execute an unverified path.

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
