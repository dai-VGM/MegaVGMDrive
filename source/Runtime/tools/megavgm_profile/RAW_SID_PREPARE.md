# Engine C C6 raw SID prepare boundary

Raw `.sid` files are queue/library inputs, never FPGA payloads. The Phase2A
controller keeps the original SID path as the queue and published status
identity, while a separate `load_path` contains only the validated cache
artifact returned by `megavgm_sid_prepare`.

The controller publishes `PREPARING` before starting the child process. It
executes the preparer directly (no shell), polls it without blocking command
ownership, and accepts exactly one newline-terminated `.mvgmsid` path beneath
`/media/fat/MegaVGMPlayer/cache/sid`. The prepared bytes then pass through the
existing strict MVGMSID classifier and unchanged PROFILE_C switch/load path.

Stop, Next, Previous, Play, or Playlist replacement cancels the child before a
new generation is considered. A late process result therefore cannot issue a
profile request or index-1 load. Repeat/Shuffle updates remain queue policy and
do not cancel preparation.

Cold cache preparation has a 120-second watchdog independent of the unchanged
60-second profile/session timeout. Cancellation first invalidates the prepare
generation, sends SIGTERM, waits for a bounded 500 ms grace period, escalates to
SIGKILL when necessary, and reaps the child. After reap, the controller removes
only a regular, non-symlink cache-root entry named
`<64-lowercase-hex-cache-key>.mvgmsid.tmp.<child-pid>`. Published `.mvgmsid` /
`.json` pairs, `.lock` files, other process IDs, directories, and symlinks are
never cleanup targets. Cleanup failures are emitted as
`SID_TEMP_CLEANUP_FAILED` diagnostics.

Cold preflight uses `inspect_raw_sid_for_prepare`, which validates the raw file
location, PSID/RSID header bounds, single-SID declaration, and start song. It
does not classify raw bytes as playable PROFILE_C data. The converter remains
the authoritative parser/resolver for model/timing (including an exact
SHA/subtune sidecar), and a prepared artifact must still pass `classify_file`
before any RBF request.

Default runtime paths:

```text
/media/fat/MegaVGMPlayer/megavgm_sid_prepare
/media/fat/MegaVGMPlayer/cache/sid/
/media/fat/MegaVGMPlayer/sid/Songlengths.md5   (optional)
```

The cache is outside `/media/fat/MegaVGMDrive`, so Browse never exposes cache
objects. Existing `.vgm` and `.mvgmsid` behavior is unchanged.
