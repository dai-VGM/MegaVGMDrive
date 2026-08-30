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

Build on MiSTer or with an ARM cross-compiler:

```sh
make
```

Run host simulations:

```sh
./run_host_tests.sh
```
