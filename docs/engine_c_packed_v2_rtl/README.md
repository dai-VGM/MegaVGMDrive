# Engine C Packed v2 direct decoder — validation candidate

Branch: `engine-c-packed-v2-rtl`.
SID/transport base: `5d0c9b73f70dd3912e112b172d36329d3e3d9cfe`.
Host/reference base: `bb467fca2c9ea982345645c419d9da7d21a5d095`.

This is simulation-validated, **not Quartus-compiled or hardware-validated**.
No production routing, RBF, Supervisor, classifier or PWA was changed.
The normative [Packed v2 format](../MVGMSID_PACKED_V2.md) and C0/C1 are unchanged.

## Architecture and ownership

```text
uploaded original file in raw DDR (8MiB maximum)
    -> 16-byte format-identity check / version dispatch
       v1 -> frozen C3 loader -> frozen C2 descriptor DDR store
       v2 -> raw DDR burst reader -> 512-byte FIFO
             -> complete strict preflight (no audio, no descriptor writes)
             -> rewind original packed bytes (not expanded data)
             -> ULEB128/tag/data decoder -> 128 x 78-bit canonical FIFO
    -> selected {EOF, absolute cycle[63:0], reg[4:0], data[7:0]}
    -> frozen C4 scheduler / fractional CE
    -> frozen SID wrapper and publication
    -> frozen C4 transition/fade/session owner
```

The initial identity check validates magic, version/minor and header/record
encoding. The selected path validates its complete header and entire body before
playback. Unknown formats reject. v2 does not write any DDR descriptor or v1
expansion; simulation asserts zero DDR writes by the v2 engine after upload.
The second pass revalidates records as it streams them to the FIFO.

v1 loader, descriptor store, scheduler, SID algorithm, CE, reset/publication and
transport sources remain byte-identical. A separate lab `engine_c_lab.sv` wires
the dispatcher/mux in front of those modules. Its scheduler instantiation and
everything below it are byte-identical to C4. v1 incurs an extra initial
16-byte identity read before the original loader starts; absolute native-cycle
launch, audio and transport behavior are unchanged. Early malformed identity
errors can now be rejected by the dispatcher before the legacy loader starts.

Session model/timing/clock commit only after complete validation and stay fixed
until session reset. `loaded` additionally requires 64 canonical records prefetched,
or the whole stream including EOF if shorter. This is FIFO preparation, not a
time delay, SID warm-up counter, or changed audio qualification rule.
The existing SID pipeline qualification and fade owner remain the sole audio
readiness/transition authorities. On halt, parsing/consumption stops; the existing
scheduler continues its CE, with no old-session WRITE resurrection.

`mem_addr` is the frozen scheduler's 17-bit sequential request ordinal. v2 checks
the matching modulo ordinal, while its file record count and cycles remain u64.
It does NOT use this ordinal to seek into expanded DDR. The 150,729-WRITE Commando
and 1,398,058-WRITE capacity tests exercise ordinal wrap without truncation.

## Accepted subset / rejection

The C4 subset is unchanged: single SID, 6581/8580, exact PAL 985248 Hz or NTSC
1022727 Hz, including equivalent rational encodings. Both versions explicitly
reject LOOP_VALID in the pre-C7.2 baseline; no loop is inferred or ignored. C7.2
adds the strict manual-loop replay contract documented in
`docs/ENGINE_C_C7_2_MANUAL_LOOPS.md`. This remains a subset restriction for v1,
not a change to the v1/v2 format specification. Duration/capture/override flags
keep their existing validation contract; reserved and unknown values reject.

ULEB128 allows at most ten bytes and shortest representation only. Byte ten must
be 01. All absolute-cycle addition uses a 65-bit carry check. First WRITE at zero
is legal; subsequent zero deltas reject. EOF is a deadline-bearing record; its
final delta is preserved, including EOF at the last WRITE's cycle. No duplicate
or same-value write is removed.

Packed-specific errors:

| Code | Meaning |
|---|---|
| 91 | nonsequential canonical FIFO request |
| 92 | packed DDR timeout / byte FIFO failure |
| 93 | physical EOF inside a record or missing EOF |
| 94 | invalid/noncanonical/overflowing ULEB128 |
| 95 | absolute cycle addition overflow |

Header, register and EOF errors reuse the corresponding C4-style 01/03..0c
codes. Existing scheduler starvation remains 80, not silent clock pausing.
Physical I/O health checks remain the original C4 checks.

## FIFO sizing and timing envelope

- Byte FIFO: 64 x 64-bit words = 512 bytes, up to 16-beat / 128-byte bursts.
- Canonical FIFO: 128 x 78 bits = 9,984 bits; initial occupancy target 64 records.
- Data FIFO payload total: 14,080 bits (1,760 bytes), plus header/state registers.
- Parse cost with bytes available: 4 SYS clocks for a one-byte-delta WRITE;
  at most 13 SYS clocks for a ten-byte-delta WRITE (LEB + tag + data + emit).
- Shortest native interval at 20MHz is 19 SYS clocks (NTSC), 20 for PAL.
  Even the longest varint compute path fits between minimum native edges when
  supplied. In valid dense traces, one-cycle deltas use only three bytes/WRITE;
  longer varints imply correspondingly longer native wait intervals.
- 64-record initial occupancy gives at least roughly 1,216 SYS clocks of dense
  event coverage, apart from the scheduler head, and the byte FIFO adds reserve.
- Under the tested 512-clock initial DDR latency, beat/arbiter overhead remains
  below a conservative 600 clocks per 128-byte burst. This is faster than the
  dense demand of 128 bytes per about 811 clocks at 3 bytes / 19 SYS clocks.

Simulation tests one WRITE per native cycle (4,096 WRITEs), PAL and NTSC, including
512-clock DDR latency and periodic BUSY; all deadlines and CE counts match.
The full real-corpus decoder also uses delayed responses and beat stalls.
These are **bounded test conditions**, not a measured worst-case MiSTer DDR
latency guarantee. Unbounded starvation must and does become FATAL. No FIFO size
can make arbitrary DDR stalls safe. Real latency/fit margins remain hardware gates.

No Quartus resource utilization or fMAX is available. The bit counts above are
structural storage counts, not a claim about inferred M10K/MLAB/ALM usage.

## Simulation evidence

[Machine-readable evidence](EVIDENCE.json) includes each result and the resolved
source hashes. Local logs, PCM and generated fixtures are in:

`/Users/daizo/Projects/MegaVGMPlayer_EngineC_PackedV2_RTL_Artifacts/`

| Suite | Cases | Result |
|---|---:|---|
| RTL decoder / real corpus / malformed / latency | 57 | all passed in simulation |
| v1/v2 SID audio, repeated sessions, starvation, v1 oversize | 11 | all passed in simulation |
| legacy vectors + v2 empty/zero-cycle scheduler cases | 76 | all passed in simulation |
| exact physical size boundaries | 6 | all passed in simulation |
| dense native scheduler / integrated long-file prefix | 6 | all passed in simulation |
| full C4 transport: v2-only, mixed, v1-only | 3 | all passed in simulation |
| Frozen host Packed v2 / C0 / C1 tests | 84 | all passed, none skipped |

**159 RTL executable cases**, plus 84 host tests. Tcl resolves 70 source files
without duplicate assignments/entities. Verilator elaborates `emu` with HPS/PLL
stubs. Vendor legacy width warnings remain; no new packed-module warnings were
reported. Neither test constitutes a Quartus Full Compilation.

All 11 requested real captures: **580,271 WRITEs**, every absolute cycle, address,
data, order and EOF agree between RTL FIFO output, host v2 decode and C0 v1 trace.
The TB reads host-generated canonical records and reports the first divergent
record/cycle/address/data, not just a digest.

| Real input | WRITEs | EOF native cycle | Packed bytes |
|---|---:|---:|---:|
| Commando 60s | 30430 | 59114880 | 103383 |
| Commando 270s | 150729 | 266016960 | 506007 |
| Comic Bakery 60s | 35515 | 59114880 | 116528 |
| Monty on the Run 60s | 29574 | 59114880 | 102493 |
| Sanxion 60s | 42668 | 59114880 | 143239 |
| The Power 60s | 61419 | 59114880 | 196842 |
| Realm of Impossibility 60s | 6757 | 61363620 | 22662 |
| Relaxation V3 NTSC/8580 60s | 58479 | 61363620 | 188664 |
| Volfied 10s | 47099 | 9852480 | 188282 |
| No Mercy 10s | 29504 | 9852480 | 110524 |
| No Mercy 30s | 88097 | 29557440 | 329741 |

Full corpus tests run the actual streaming decoder/FIFO/DDR arbiter, not the
audio engine for the entire captured duration. Synthetic and dense tests run
the real scheduler/SID; Commando 270s additionally passes integrated load and
the first 20,000 native cycles in PLAYING. Full 270s audio remains a hardware gate.
No copyrighted stream, canonical music trace, or music audio is committed.

Three-second pre-gain 44.1kHz signed-16 mono PCM: v1 == v2 == existing C4
CORENAME-validation PCM, 264,600 bytes each:

| Condition | SHA-256 |
|---|---|
| PAL/6581 | 4d8428b1b01918f000bacd913b591ef499ec8e7f84ad76038c477e560c0e6c19 |
| PAL/8580 | 8c18a98c1518fb8530e1ac71adee833e7922eb4c34e277f4e47f02b6a73f0b88 |
| NTSC/6581 | fd4f641b9ab167a84aed40aee6df85713eba0d3b065d798732f61c731ebf296e |
| NTSC/8580 | 7e7ee9078d8f5fedef88b496b4d602624e8c8c4fe099fd24d29f47ad821934b7 |

Each playback also checks native publication pulses, CE counts, oscillator bus
phase and repeat-session samples against a separately reset clean SID reference.
v1 -> v2 -> v1 repeated load is exercised without changing scheduler logic.

Additionally, **every full-width 18-bit native SID publication** is stored as
sign-extended little-endian int32 (`tone-*-v1.native32` / `*-v2.native32`) and
compared byte-for-byte before any 44.1kHz sampling or 18-to-16-bit conversion.
All four pairs are exactly equal: PAL has 2,955,743 samples / 11,822,972 bytes per
file; NTSC has 3,068,180 samples / 12,272,720 bytes. The count omits the not-yet-
published final CE at immediate parser EOF, identically in both formats.

Physical-size boundaries: packed 131071/131072/131073, 4194303/4194304/4194305,
and 8388607/8388608 bytes decode exactly. 8388609 bytes reject before audio.
The exact 8 MiB case reads through raw DDR word `0x060fffff` without entering
the adjacent `0x06100000` region. Golden Commando 270s v1 is 4,823,488 bytes
and still rejects on the frozen v1 record-capacity path; its 506,007-byte v2 is
accepted. Packed v2 retains direct streaming replay rather than descriptor
expansion.

C4 shell tests retain the original assertions for Natural EOF, FADE_ONLY,
duplicate FADE_ONLY, EOF race, replacement without phantom ENDED, Stop/clean
reload, exactly-once session/ENDED, index-2 isolation and >100ms held silence.
Measured fade is the unchanged 2,000,128 SYS clocks, or 2,000,129 with the existing
one-clock parser-EOF join. Stop, malformed loads and physical DDR faults retain
their existing mute/FATAL behavior. v2 starvation reaches scheduler error 80.

## Reproduction

```sh
python3 tools/engine_c_packed_v2_rtl/run_tests.py --out /absolute/new/artifacts --only all
python3 tools/engine_c_packed_v2_rtl/audit.py --out /absolute/new/artifacts
```

The runner defaults to the documented local C3 fixture and Downloads corpus
directories; it does not fetch or redistribute SID music. Individual `--only`
suites are available, and `--reuse-build` is for already compiled test binaries.
Use a new output directory or the known task-specific directory, not PASS outputs.

## Windows project and hardware gate

QPF relative to this worktree:

`hw/engine_c_packed_v2/MegaVGMPlayer_EngineC_PackedV2_Validation_MiSTer.qpf`

It is a complete dedicated QSF, with no assignment-removal overlay. Its platform,
pins, clocks and macros match C4 validation. Only the output directory and source
QIP selection differ; the QIP substitutes the decoder-layer engine adapter and
adds three new modules. CORENAME remains **MegaVGMDrive**.

On Windows, from `hw/engine_c_packed_v2`:

```powershell
quartus_sh --flow compile MegaVGMPlayer_EngineC_PackedV2_Validation_MiSTer
```

Expected newly built RBF (not generated on this Mac):

`hw/engine_c_packed_v2/output_files_packed_v2/MegaVGMPlayer_EngineC_PackedV2_Validation_MiSTer.rbf`

Keep the hardware-PASS C4 RBF (SHA
`117adcd8d9360388826f60f4207c5b547daee58f5f0ba2e456f10e7bf41abed8`)
and production A/B untouched as reference/rollback copies. Initially stage the
candidate under its new name. The existing C4 lab harness requires its exact
expected RBF argv; do not change production Supervisor or bypass its checks.
If using the harness's existing C4 lab pathname, first back up that RBF and
verify both old/new SHA before an explicit lab-only replacement. No deploy was
performed here; the new RBF SHA will only exist after Windows compilation.

Hardware files: use the exact packed outputs from
`MegaVGMPlayer_EngineC_PackedV2_Artifacts`, copying them under `.mvg` suffixes for
the existing OSD filter. This changes filenames only, not bytes. Verify hashes
against the host [corpus manifest](../MVGMSID_PACKED_V2_CORPUS.json).

1. Verify CORENAME MegaVGMDrive, exact modified Main identity, new candidate RBF
   argv and live status before sending transport commands through the C4 harness.
2. Commando 270s Packed v2: full ~4:30 playback; no starvation/pop/FATAL.
3. Volfied 10s Packed v2: digi/voice audibly agrees with v1.
4. PAL/6581, PAL/8580, NTSC/6581, NTSC/8580 synthetic v1/v2 pairs agree.
5. Short v1 Commando: backward-compatible load/playback. Repeat v1 -> v2 -> v1.
6. Natural EOF: same session, ~100ms fade, ENDED once, zero output thereafter.
7. FADE_ONLY and duplicate: same session, no fade restart or duplicate ENDED;
   subsequent policy transfers cannot re-arm output.
8. Replacement: old fade -> zero -> new session; no phantom ENDED or stale audio.
9. Stop during playback/fade: immediate mute; clean subsequent reload.
10. Capture status/error and timing/resource reports. Do not promote to PROFILE_C
    until these hardware checks pass.

This source configures the production Packed-v2 project with
`C2_MAX_FILE_BYTES=8388608`; the physical upload address remains 23 bits and
address `0x800000` remains an overflow. Remaining gates: Windows
synthesis/fit/timing, real DDR latency headroom, real
audio/listening and hardware transport regression. There is no PROFILE_C routing
addition, public RBF rename, PWA change or format migration in this candidate.
