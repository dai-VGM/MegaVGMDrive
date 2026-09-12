# Packed v2 host implementation results

Branch: `engine-c-packed-v2`.
Base: `5d0c9b73f70dd3912e112b172d36329d3e3d9cfe` (C4 CORENAME validation lineage).
Date: 2026-09-12. No Quartus, RTL, runtime or hardware testing performed.

## Outcome

All 11 requested local captures validated with frozen C0 and passed full v1/v2
canonical equality: **580,271 WRITEs**, all 11 EOF cycles, all flags,
clock/model/timing/subtune/duration/source digest and canonical loop metadata.
All output files were read back and compared. A second pack was byte-identical.
The actual corpus has no loop flags; loop equivalence is tested synthetically,
including targets on WAITs and three repeated iterations against C0 schedule().

The normative layout was documented in [the format specification](MVGMSID_PACKED_V2.md)
before implementing the codec. The permanent C0 v1 API and C1 converter are unchanged.
The v2 loop target is deliberately a WRITE ordinal, not a repurposed v1 event
number; semantic loop coordinates and behavior are preserved.

## Local corpus

Original v1 artifacts: `/Users/daizo/Downloads/`.
Packed output and machine-readable results:
`/Users/daizo/Projects/MegaVGMPlayer_EngineC_PackedV2_Artifacts/`.

[Committed numerical evidence](MVGMSID_PACKED_V2_CORPUS.json) contains each input/output
SHA-256, absolute EOF cycle, all metadata and detailed statistics. No SID file,
register trace, v1/v2 music artifact or copyrighted audio is committed.

| Input | v1 bytes | v2 bytes | v2/v1 | WRITE count | Body bytes/WRITE | Max delta | ULEB lengths (including EOF) | 4MiB estimated seconds |
|---|---:|---:|---:|---:|---:|---:|---|---:|
| Commando_60s.mvg | 973920 | 103383 | 10.62% | 30430 | 3.3932 | 19500 | {"1":21475,"2":5949,"3":3007} | 2437.2 |
| Commando_270s.mvg | 4823488 | 506007 | 10.49% | 150729 | 3.3562 | 58635 | {"1":110565,"2":26640,"3":13525} | 2238.5 |
| Comic_Bakery_60s.mvg | 1136640 | 116528 | 10.25% | 35515 | 3.2775 | 19634 | {"1":28666,"2":3847,"3":3003} | 2161.9 |
| Monty_on_the_Run_60s.mvg | 946528 | 102493 | 10.83% | 29574 | 3.4613 | 19656 | {"1":18941,"2":7627,"3":3007} | 2458.4 |
| Sanxion_60s.mvg | 1365536 | 143239 | 10.49% | 42668 | 3.3541 | 19708 | {"1":30571,"2":9091,"3":3007} | 1758.4 |
| Power_60s.mvg | 1965568 | 196842 | 10.01% | 61419 | 3.2028 | 19105 | {"1":51972,"2":6441,"3":3007} | 1279.3 |
| Realm_of_Impossibility_60s.mvg | 216384 | 22662 | 10.47% | 6757 | 3.3349 | 392988 | {"1":5441,"2":373,"3":944} | 11167.6 |
| Relaxation_V3_NTSC_plus_8580_60s.mvg | 1871488 | 188664 | 10.08% | 58479 | 3.2240 | 17618 | {"1":47793,"2":8277,"3":2410} | 1334.8 |
| Volfied_10s.mvg | 1507328 | 188282 | 12.49% | 47099 | 3.9949 | 56338 | {"1":246,"2":46853,"3":1} | 222.9 |
| No_Mercy_10s.mvg | 944288 | 110524 | 11.70% | 29504 | 3.7417 | 19005 | {"1":7890,"2":21348,"3":267} | 379.9 |
| No_Mercy_30s.mvg | 2819264 | 329741 | 11.70% | 88097 | 3.7415 | 19005 | {"1":23584,"2":63708,"3":806} | 381.7 |

Ratio means v2 file bytes / v1 file bytes (smaller is better).
Average here is packed body including EOF divided by WRITE count, excluding
the 128-byte header. JSON additionally reports WRITE-record-only average.
Maximum delta and ULEB histogram include the EOF record.

Commando 270s is **506,007 bytes (494.15 KiB)**, below 4,194,304 bytes.
Volfied 10s is **188,282 bytes** with exactly **47,099 WRITEs**.
Measured density suggests ~222.9 seconds (~3m43s) of Volfied-like data in 4MiB;
No Mercy 30s suggests ~381.7 seconds (~6m22s).
These are storage-density extrapolations, not measured longer captures or
playback guarantees. Density can change later in a tune.

Formula (all sizes include the necessary header allowance):
`estimated_seconds = (4194304 - 128) * captured_seconds / packed_body_bytes`.
Only the report uses floating-point display; codec cycles and timing are exact
unsigned integers. Real files show ULEB lengths 1–3; no benefit for a private
varint has been demonstrated. Standard ULEB128 is recommended.

## Commands

From this worktree:

```sh
python3 tools/engine_c_packed_v2/packed.py pack input.mvg -o output.mvgmsid2
python3 tools/engine_c_packed_v2/packed.py validate output.mvgmsid2
python3 tools/engine_c_packed_v2/packed.py inspect output.mvgmsid2
python3 tools/engine_c_packed_v2/packed.py dump output.mvgmsid2
python3 tools/engine_c_packed_v2/packed.py compare input.mvg output.mvgmsid2
python3 tools/engine_c_packed_v2/corpus.py --output-dir /absolute/new/output-directory input1.mvg input2.mvg
```

`dump` emits metadata followed by JSON-line absolute-cycle WRITEs and EOF.
`pack` refuses to overwrite an existing file. The corpus tool requires a new
output directory and refuses duplicate output names. The .mvgmsid2 suffix is
a host reference convention, not a registered Player/OSD extension.

## Tests

- Packed v2: 21 tests, including 200 deterministic generated v1 streams,
  loop replay against the independent C0 scheduler, 2,000 seeded mutations,
  explicit u64/ULEB limits, invalid headers/records and CLI/disk round trips.
- Frozen C0: 41 tests.
- Frozen C1: 22 tests including all six native integration tests using the
  already-built helper below. No helper rebuild was needed.
- Total: **84 tests passed, zero skipped** in the final runs.
- Separate requested real corpus gate: all 11 captures fully equivalent.

```sh
python3 -m unittest discover -s tools/engine_c_packed_v2 -v
python3 -m unittest discover -s tools/engine_c_c0 -v
MVGMSID_C1_NATIVE_HELPER=/Users/daizo/Projects/MegaVGMPlayer_EngineC_PhaseC1/tools/engine_c_c1/.build/bin/sid_capture python3 -m unittest discover -s tools/engine_c_c1 -v
```

## Freeze / next-step risks

Only new host codec/tests/report tooling and these documents are added.
Existing tracked source files, C0/C1, SID RTL, scheduler, audio, C4 transport,
RBF/QPF/QSF, Supervisor, classifier/Profile C and Player/PWA are unchanged.
No public release, FPGA build, deployment or automatic conversion was performed.

**Do not load these packed files into C4.** Current hardware still parses v1.
Packing makes Commando fit the storage budget but does not add v2 decode support.

A future RTL implementation needs a separately validated ULEB decoder, FIFO
throughput/underflow analysis, checked u64 deadline accumulation and loop
ordinal/byte-offset resolution. See the specification's decoder proposal.
Do not stall CE to compensate for decoding latency or alter fade ownership.
For initially loop-free bring-up, reject LOOP_VALID explicitly instead of
silently ignoring metadata.

The reference implementation buffers the input/trace in host memory; it is not
a bounded-memory importer or hardware DMA parser. Large untrusted-input resource
budgets and in-field format adoption remain separate stages. There is no new
integrity checksum inside the v2 container: source_sha256 retains its v1 meaning
(source SID digest); sidecar input/output SHA-256 records provide artifact identity.
