# MegaVGMPlayer directory playlist controller

`megavgm_playlist` plays prepared VGM files from one directory exactly once.
It reuses the hardware-proven Phase 1C status parser and direct Main FIFO
transport. It never accesses FPGA SPI and never invokes a shell.

```sh
./megavgm_playlist "/media/fat/MegaVGMDrive/01_Arcade/Game_(System)"
```

Discovery is intentionally limited to direct, non-hidden regular files whose
names end in the exact case-sensitive suffix `.vgm`. Subdirectories, `.VGM`,
dotfiles, and helper files with another final suffix are ignored. Tracks are
sorted lexicographically by unsigned filename bytes, independent of locale.

For every track the controller waits for a new session, then PLAYING, then
ENDED for that same session. A latched ENDED can advance only once. FATAL or a
nonzero error skips the current track. A missing status/Main, load/start
timeout, or malformed record aborts. An unexpected session change exits with:

```text
PLAYLIST SUSPENDED: manual/external load detected
```

Normal playback has no timeout by default. Consequently a native-loop VGM
remains PLAYING indefinitely; Phase 1D does not implement a loop limit or use
silence/time as an end detector.

Build on MiSTer or with an ARM cross-compiler:

```sh
make
```

Run host simulations:

```sh
./run_host_tests.sh
```
