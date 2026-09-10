# Engine C Phase C1: SID to MVGMSID converter

Phase C1 is desktop/reference tooling only. It executes one PSID or RSID
subtune through a pinned `libsidplayfp`, observes actual C64-to-SID bus WRITE
transactions, and encodes them with the unchanged Phase C0 MVGMSID v1 codec.
It does not add SID RTL, a Golden Shell profile, an RBF, or Player support.

## Dependency and license

The dependency is locked by `dependencies.lock.json`:

- libsidplayfp 3.1.1
- upstream tag commit `732fa8ec8131fc75aafc2eaea583ddcdeea2a3cc`
- official release archive SHA-256
  `12b79190593bf480b2d11481b5c2de62bac07f344437a66cd8d887329875c626`
- license: GPL-2.0-or-later

The generated native helper links libsidplayfp and must be distributed under
terms compatible with GPL-2.0-or-later. The Python codec/converter is source
tooling in this repository; generated `.mvgmsid` data does not embed
libsidplayfp code.

The build uses libsidplayfp's bundled SIDLite implementation. Audio samples
are discarded—the observer is before the emulation engine's `write()` method.
SIDLite still supplies OSC3/ENV3 readback when a tune reads SID state. A later
qualification pass may compare such read-sensitive tunes with reSIDfp, but
that does not alter the captured bus hook or MVGMSID v1.

## Exact capture mechanism

Unmodified libsidplayfp exposes neither an observer nor a complete write log.
The pinned patch adds one read-only callback at the start of:

```text
libsidplayfp::sidemu::writeReg(addr, data)
```

That is the common C64 SID-bus write path before voice-mute/filter transforms
and before the chosen SID emulator receives `write(addr, data)`. The callback
records:

```text
EventScheduler PHI1 absolute cycle, SID index, register address, data
```

No register polling or snapshot differencing is used. Consequently init
writes, writes that repeat the same value, and original write order survive.
The callback is synchronous on libsidplayfp's emulation thread.

The trace origin is taken immediately after `player.load()`, before emulation
starts the tune's generated driver/init routine. Writes performed while
executing that initialization are therefore present. `powerOnDelay` is set to
zero to remove libsidplayfp's randomized startup component and make conversion
deterministic.

MVGMSID v1 permits at most one WRITE at a given native cycle. If a corpus tune
produces multiple writes at one cycle, conversion fails rather than shifting a
write. The complete native trace is retained as
`OUTPUT.mvgmsid.failed-trace.tsv` for investigation.

## Build

The build script downloads only the locked official archive, verifies its
SHA-256 before extraction, applies the version-specific observer patch, builds
a static library, and links the local capture helper:

```sh
tools/engine_c_c1/build_native.sh
```

The output defaults to:

```text
tools/engine_c_c1/.build/bin/sid_capture
```

Override the disposable build directory with `MVGMSID_C1_BUILD_DIR`. The
archive includes its generated `configure` script and PSID driver binary, so
this path does not require Docker, CMake, Autoconf, or a 6502 assembler.

## Convert

When model and timing metadata are exact:

```sh
python3 tools/engine_c_c1/sid_to_mvgmsid.py \
  input.sid \
  --subtune 1 \
  --capture-seconds 180 \
  -o output.mvgmsid
```

When either source field is `unknown` or `any`, conversion stops. Supply an
explicit decision rather than letting the converter guess:

```sh
python3 tools/engine_c_c1/sid_to_mvgmsid.py \
  input.sid \
  --subtune 1 \
  --model 6581 \
  --timing pal \
  --capture-seconds 180 \
  -o output.mvgmsid
```

Accepted overrides are `--model 6581|8580` and `--timing pal|ntsc`. Their C0
header flags are set independently. PAL is exactly 985248 Hz and NTSC is
exactly 1022727 Hz in C1.

The capture limit is an integer number of seconds. Its native endpoint is
computed once with checked integer multiplication:

```text
final_cycle = capture_seconds * selected_sid_clock_hz
```

All event timestamps stay in native SID cycles. The converter emits `WAIT N`
from differences of absolute cycles; it never rounds each event to a 44.1 kHz
position. C0's rational scheduler remains the reference for transport
positions, so rounding does not accumulate per event.

Every successful output is decoded again by the Phase C0 strict validator.
The converter prints the C0 inspector summary and writes a machine-readable
sidecar at `output.mvgmsid.provenance.json`.

## C1 metadata policy

- PSID/RSID title, author, released, song count, start song, selected subtune,
  clock/model declaration, and speed metadata are recorded in the sidecar.
- `END_IS_CAPTURE_LIMIT` is always set.
- `DURATION_KNOWN` is never set merely from the CLI capture cap.
- `LOOP_VALID` is always clear; Phase C1 does not infer loops.
- No leading/trailing silence is trimmed.
- MVGMSID v1 is single SID, so multi-SID input is rejected.
- A requested subtune must exist; libsidplayfp fallback selection is rejected.

The sidecar records the source path/name/SHA-256, converter version and current
repository commit, pinned libsidplayfp version/commit, selected subtune,
resolved model/timing, explicit overrides, capture limit, event/write counts,
final cycle, and output SHA-256.

## Tests

Build the helper first, then run both C1 and unchanged C0 suites:

```sh
python3 -m unittest -v tools/engine_c_c1/test_sid_to_mvgmsid.py
PYTHONPATH=tools/engine_c_c0 \
  python3 -m unittest -v tools/engine_c_c0/test_mvgmsid.py
```

C1 creates an original synthetic PSID fixture at test time; no third-party SID
music is stored in the repository. Its init routine performs an intentional
same-value rewrite, allowing the integration test to prove the bus observer
retains transactions that a snapshot-diff implementation would lose.
