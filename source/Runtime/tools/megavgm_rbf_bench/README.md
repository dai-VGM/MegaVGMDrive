# MegaVGMPlayer RBF source benchmark

This directory contains diagnostic-only tooling. It does not implement a lazy
cache and does not alter the Player, controller, Supervisor, Main, FPGA, or
production path contract.

`rbf_read_bench.py` verifies the frozen A/B/C bytes, copies them to tmpfs, and
measures cold-ish FAT (`POSIX_FADV_DONTNEED`), warm FAT/page-cache, and `/tmp`
reads. It never writes `drop_caches`.

`rbf_bench_interposer.c` is loaded only into the dynamically linked modified
Main during the benchmark. It observes the existing RBF `open`, completed
`read`, configuration-return boundary (the `sync()` call immediately after
`socfpga_load` returns), and post-sync boundary with `CLOCK_MONOTONIC`. It does
not replace data or return values. The internal `socfpga_load` entry is not a
dynamic symbol, so configuration start is represented by the completed-read
timestamp immediately preceding `do_bridge(0); socfpga_load(...)`.

The benchmark branch adds a fail-closed diagnostic environment pass-through in
`LinuxRuntime::launch_main`. It accepts only the exact `/tmp` interposer/log
paths and `fat`/`tmp` source labels. With those variables absent, the sanitized
production Main environment remains the existing six entries. The diagnostic
Supervisor is run from `/tmp`; the installed production Supervisor is not
replaced.

`rbf_bind.py` can temporarily bind exact SHA-verified `/tmp` copies over the
three exact production filenames. The underlying FAT files are never replaced
or deleted. Always run `unmount` in cleanup and verify all three production
SHA-256 values afterward.

`switch_bench.py` drives the existing controller FIFO with fixed warm tracks,
observes Supervisor generation/READY, controller rebind/PLAYING, and the Remote
status API, and records ten A↔C and B↔C switches in each direction. It excludes
setup switches from its samples.

The second diagnostic stage also records the accepted generation in the
controller, Supervisor request/fade/switch/drain/start/verify/FIFO boundaries,
and Main command/open boundaries under the same `switch_id`. Internal Main calls
from command parsing through `fpga_load_rbf()` are not dynamic symbols; T10 and
T11 are therefore bounded by the observed FIFO read (T9) and RBF `open()` entry
(T12), rather than inferred as distinct timestamps. `latency_log.h` is inert
unless the same exact diagnostic environment and `/tmp` log path are present.

Hardware safety rules:

1. Start and finish in verified STOCK mode.
2. Keep the known-good runtime binaries and RBFs unchanged.
3. Use `/tmp/megavgm-rbf-bench` only for diagnostic files.
4. Do not interrupt while bind mounts are active. If interrupted, run
   `rbf_bind.py unmount` before any production playback.
5. Re-hash production RBFs and restart normal production paths after cleanup.
