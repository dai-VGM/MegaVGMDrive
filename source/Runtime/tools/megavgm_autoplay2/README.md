# MegaVGMPlayer autoplay2 proof controller

`megavgm_autoplay2` performs one automatic transition between two non-looping
VGM files. It consumes the Phase 1B atomic snapshot written by Main and sends
the existing Phase 1A command directly to Main's FIFO. It never accesses FPGA
SPI and does not invoke a shell.

```text
/tmp/MegaVGMPlayer.status
  -> current session reaches PLAYING, then ENDED
  -> /dev/MiSTer_cmd: load_file 1 <Track B path>
  -> new session reaches PLAYING
```

Build on MiSTer or with an ARM cross-compiler:

```sh
make
```

Run with two prepared, non-looping files:

```sh
./megavgm_autoplay2 \
  "/media/fat/MegaVGMDrive/01 Track A.vgm" \
  "/media/fat/MegaVGMDrive/02 Track B.vgm"
```

The controller exits successfully immediately after Track B reaches PLAYING.
An unexpected session change before Track A ends aborts with
`MANUAL_OR_EXTERNAL_SESSION_CHANGE`. Native-loop tracks remain PLAYING and will
eventually reach the Track A end timeout; the timeout is not treated as an end.

Run the host simulations with:

```sh
./run_host_tests.sh
```
