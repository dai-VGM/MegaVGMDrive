# MegaVGMPlayer directory playlist controller

`megavgm_playlist` plays prepared VGM files from one directory exactly once.
It reuses the hardware-proven Phase 1C status parser and direct Main FIFO
transport. It never accesses FPGA SPI and never invokes a shell.

```sh
./megavgm_playlist --loops 2 \
  "/media/fat/MegaVGMDrive/01_Arcade/Game_(System)"
```

`--loops N` applies only to files with FPGA-reported native-loop metadata.
The default is `2`: after two accepted native VGM loop jumps, the controller
loads the next track without forcing FPGA `ENDED`. `--loops 0` disables this
policy and leaves native-loop tracks playing indefinitely.

While the controller is running, use the local control client:

```sh
./megavgm_ctl next
./megavgm_ctl prev
```

The client writes only `NEXT` or `PREV` to the controller-owned FIFO at
`/tmp/megavgm_playlist.cmd`; it never opens `/dev/MiSTer_cmd`. `NEXT` loads the
following track immediately. At the last track it completes the playlist
without wrapping. `PREV` loads the preceding track; at the first track it
deterministically restarts that first track.

Remote playlist playback uses a separate `PLAYLIST <snapshot>` command. The
snapshot is a closed, versioned, ordered list of canonical `.vgm` paths under
`/media/fat/MegaVGMDrive`, plus a zero-based starting index and display name.
The controller opens it without following symlinks, validates every file,
copies the complete ordering into memory, and removes the one-shot snapshot.
Persistent playlist edits therefore cannot change an active queue. If the
snapshot starts on the already-owned current track, the controller adopts the
new queue without reloading that track; otherwise it performs one serialized
replacement load. `NEXT`, `PREV`, native-loop advancement, and end-of-list
behavior then operate only inside the copied snapshot.

Commands are accepted only after the current controller-owned session reaches
PLAYING. Additional commands received while its replacement track is loading
are discarded, so Main transfers never overlap. A navigation command observed
in the same poll interval as ENDED, FATAL, or the native-loop limit claims the
single transition; the old session's later status is ignored.

Discovery is intentionally limited to direct, non-hidden regular files whose
names end in the exact case-sensitive suffix `.vgm`. Subdirectories, `.VGM`,
dotfiles, and helper files with another final suffix are ignored. Tracks are
sorted lexicographically by unsigned filename bytes, independent of locale.

For a non-loop track the controller waits for a new session, then PLAYING,
then ENDED for that same session. For a native-loop track it advances when the
same PLAYING session reaches the configured `loop_count`. A latched ENDED or
loop count can advance only once. FATAL or a nonzero error skips the current
track. A missing status/Main, load/start timeout, or malformed record aborts.
An unexpected session change exits with:

```text
PLAYLIST SUSPENDED: manual/external load detected
```

Normal playback has no timeout by default. The controller never uses silence
or elapsed playback time as an end detector. Loading the same VGM manually,
without this controller, retains the FPGA player's normal infinite-loop
behavior.

The controller also atomically publishes a future-UI-friendly snapshot at
`/tmp/megavgm_playlist.status`:

```text
state=PLAYING
index=4
count=10
path=/media/fat/Music/04 Track.vgm
session=27
loop_count=1
context=PLAYLIST
playlist=Favorites
```

`context=DIRECTORY` with an empty `playlist` retains the legacy Browse/direct
directory behavior. Snapshot playback publishes `context=PLAYLIST` and its
playlist name so Remote can show the controller-owned context.

`index` is one-based. This file summarizes controller ownership and does not
replace or duplicate the raw FPGA/Main status interface.

Build on MiSTer or with an ARM cross-compiler:

```sh
make                    # builds megavgm_playlist and megavgm_ctl
```

Run host simulations:

```sh
./run_host_tests.sh
```
