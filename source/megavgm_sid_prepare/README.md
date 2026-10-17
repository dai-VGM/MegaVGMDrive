# Engine C C6 raw SID preparer

`megavgm_sid_prepare` executes one PSID/RSID subtune with pinned
libsidplayfp 3.1.1 and writes canonical Packed MVGMSID v2 directly. It never
creates v1 in production, polls SID registers, reconstructs snapshots, or
quantizes writes to 44.1 kHz. The observer runs immediately before
`sidemu::writeReg(addr,data)` and records EventScheduler PHI1 cycles.

## Decisions and strict boundaries

- Single SID only. BASIC-ROM compatibility is rejected. No C64 ROM is bundled.
- Exact header model/timing are used. `unknown`/`any` are rejected unless an
  exact source-SHA/subtune sidecar or explicit diagnostic CLI override resolves
  them.
- Duration priority is an available HVSC `Songlengths.md5` lookup using
  libsidplayfp's full-content MD5 plus selected subtune, then an exact sidecar,
  then a 300-second capture limit. No basename matching or loop guessing.
- A trusted duration ends at `ceil(milliseconds * SID_Hz / 1000)` with no hidden
  margin. The existing FPGA Natural EOF fade follows that endpoint. Fallback
  output sets `END_IS_CAPTURE_LIMIT`; trusted output sets `DURATION_KNOWN`.
  If a duration-less high-write-rate tune reaches the 8 MiB Engine C
  capacity first, the fallback closes a canonical EOF at that observed native
  cycle and records the shorter capture. A trusted duration that cannot fit is
  rejected instead of silently truncated.
- Output is strictly validated, fsynced, and atomically renamed. Cache identity
  includes source SHA-256, subtune, resolved model/timing/clock, duration
  decision, converter implementation, pinned library, Packed-v2 version, and
  the explicit `capacity_bytes=8388608` conversion policy.

## Optional C7.2 manual loop metadata

Automatic loop detection is not used. A raw SID may opt into a loop with an
exact SHA/subtune-bound `<source>.sid.loop.json` sidecar:

```json
{
  "schema": "MegaVGMPlayer-SID-loop-v1",
  "source_sha256": "<64 lowercase hex>",
  "subtune": 1,
  "loop_start_ms": 42000,
  "loop_end_ms": 103500
}
```

The field set is closed and all numbers are unsigned integers. Stale SHA,
wrong subtune, malformed JSON, `end <= start`, and an end beyond the selected
capture horizon reject the prepare. Requested milliseconds are converted once
to native SID cycles, then independently snapped to the nearest WRITE cycle
(ties choose the earlier cycle). The end may also snap to the captured EOF.
The artifact is re-encoded as one canonical `intro + loop` traversal, with all
WRITEs at the resolved end excluded and EOF moved to that end. No event is
split and no SID timing is converted to 44.1 kHz.

The exact sidecar bytes and schema/policy participate in the cache key.
Provenance records both requested millisecond points and resolved native-cycle
coordinates. With no sidecar, cache identity and the non-loop C6 result remain
unchanged.

The optional exact sidecar is `<source>.sid.megavgm`:

```text
MEGAVGMSID_OVERRIDE_V1
source_sha256=<64 lowercase hex>
subtune=1
model=8580
timing=ntsc
duration_ms=180000
```

Only `source_sha256` and `subtune` are mandatory. Unknown keys, duplicates,
invalid values, and mismatched identity are rejected.

## Runtime CLI

```sh
megavgm_sid_prepare \
  --input /media/fat/MegaVGMDrive/SID/Commando.sid \
  --cache-root /media/fat/MegaVGMPlayer/cache/sid \
  --songlength-db /media/fat/MegaVGMPlayer/sid/Songlengths.md5
```

The single stdout line is the validated cache artifact path. Diagnostics use
stderr. The production controller owns cancellation and never exposes this CLI
to the ordinary Player UI.

Every successful output has a machine-readable provenance sidecar. Cache mode
uses `<cache-key>.json`; diagnostic `--output FILE` mode uses `FILE.json`.

## License and ROM provenance

libsidplayfp 3.1.1 is GPL-2.0-or-later. The linked preparer is distributed as a
GPL-2.0-or-later program, together with the exact upstream source archive,
observer patch, preparer source, build recipe, dependency lock, and GPL text.
The standalone process boundary does not change the license of unrelated
MegaVGMPlayer processes. No Commodore ROM or third-party SID tune is included.

libsidplayfp's built-in minimal KERNAL path is used. `COMPATIBILITY_BASIC` is
rejected. Some RSID tunes may depend on behavior from user-owned ROMs beyond
what metadata can prove; such failures remain explicit, and user-ROM support is
future work.
