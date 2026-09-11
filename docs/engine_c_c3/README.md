# Engine C Phase C3 — SID model / timing lab

Branch: `engine-c-phase-c3`.
Base: `c9fc9a1b35740c616f72af5116359ee41db944e7` (`engine-c-c2-capacity`).

The user reports C2 Capacity PAL/6581 hardware playback of Commando, Comic Bakery
and Monty on the Run. That project and all its tracked files remain unchanged.
C3 is a separate **simulation-validated** lab project, not a hardware-approved
RBF or production Profile C. No macOS Quartus or new RBF build was performed.

## Header contract

The frozen MVGMSID v1 format/API/converter is unchanged. C3 extends only the lab
parser's admitted execution subset. Whole-file strict validation still precedes
any SID playback.

| Header field | Offset / size | C3 accepted meaning |
| --- | --- | --- |
| `clock_num` | 20 / u32 LE | SID Hz numerator |
| `clock_den` | 24 / u32 LE | Nonzero denominator |
| `sid_model` | 28 / u8 | 1 = 6581, 2 = 8580 |
| `timing_standard` | 29 / u8 | 1 = PAL, 2 = NTSC |
| `sid_count` | 30 / u8 | Exactly 1 |

Validated clocks are **985248/1 Hz PAL** and **1022727/1 Hz NTSC**, matching the
frozen C1 native converter's `PAL_HZ`/`NTSC_HZ` constants in
`tools/engine_c_c1/native/sid_capture.cpp`. Exact equivalent rational encodings
are accepted (e.g. `1970496/2`); arbitrary other frequencies are not inferred or
rounded to a supported frequency.

Validation uses 64-bit equality:

```text
PAL:  clock_num == 985248 * clock_den
NTSC: clock_num == 1022727 * clock_den
```

Both operands must be nonzero. The maximum product of a u32 denominator with
these constants fits in 52 bits. No 32-bit product truncation is permitted.
Unknown model/timing, inconsistent clock/timing, zero numerator/denominator,
non-equivalent clock or multi-SID input rejects with existing error 5.
All previous flag/reserved/EOF/overflow/loop/capacity checks remain intact.
In particular, LOOP_VALID is still unsupported; this is not a new loop feature.

## Session/model ownership

```text
index-1 load/reset → raw DDR upload → whole-file preflight
                                     ↓ accepted FINISH edge
                          latch model/timing/clock num/den
                                     ↓ descriptor FIFO prepared
                          release unchanged SID reset wrapper
                                     ↓ scheduler launch (native cycle 0)
                          latch fractional CE step/period
                                     ↓
                     native-cycle WRITEs / qualified audio / EOF
```

The clock/model is unavailable at raw upload begin, so session configuration is
committed **after full validation, before playback launch**, not speculatively
from a partially received header. Rejected files never publish configuration.
`FINISH && !loaded` writes the accepted configuration once. It cannot change
again before the next index-1 session reset. A new file must go through the same
validation; index-2 or a stray `start` cannot update a running session.

`sid_model=1` becomes `session_model=0`; `sid_model=2` becomes `session_model=1`.
This feeds the **unchanged** `sid_session_wrapper.model`. That wrapper captures
its model while reset is asserted and then drives `sid_top.mode` for the session.
The loader commits configuration while the SID is still held in reset pending
descriptor preparation, so the correct model is stable before reset release.

Provenance of the mapping is the existing C64-derived `sid_voice.sv` and
`sid_tables.sv`: mode 0 chooses 6581 waveform/DAC/DC/curve paths; mode 1 chooses
8580 paths. `sid_filter.sv` also uses that same mode. **None of those files,
their arithmetic, lookup tables, pipeline resets, or publication logic changed.**
DUAL=0, filter enable/configuration, POT/ext-in/offset constants and signed
18-to-16 audio adaptation remain the C2 implementation.

## Fractional CE and WRITE phase

At scheduler launch:

```text
step   = accepted clock_num
period = SYS_HZ * accepted clock_den
phase  = 0
```

For every subsequent system-clock edge:

```text
sum = phase + step
ce_sid = (sum >= period)
phase = ce_sid ? sum - period : sum
```

`SYS_HZ=20000000` is unchanged. Phase and period are u64, sum is 65-bit; the
product is explicitly widened before multiplication. With a u32 denominator,
20 MHz * denominator is less than 2^57. Validated rates are below SYS_HZ, so at
most one CE is generated per system edge. No real-valued arithmetic, hardware
division, event rounding, clock pausing or 44.1-kHz WRITE quantization is added.

After `n` system edges from launch, exact CE count is:

```text
floor(n * clock_num / (20000000 * clock_den))
```

Clock inputs are copied at launch; later input changes cannot modify CE. The
request/response scheduler FSM, WRITE/EOF ordering and native-cycle counters are
otherwise unchanged. WRITE(0) remains the launch edge; WRITE(n) remains CE edge n,
with the old register consumed by that edge's oscillator and the new value used
on the following cycle. CE continues after EOF/fatal as in C2.

PAL minimum spacing remains 20 SYS cycles; NTSC minimum spacing is 19. Existing
sample publication is observed at CE + 17 SYS cycles by the consumer for both,
so no new publication delay or readiness heuristic is needed. Audio-ready remains
the unchanged reset/pipeline-qualified pulse contract, not `state==15` as a level.

## Scope / source list

Only three new RTL files are needed:

- `rtl/engine_c_c3/mvgmsid_loader.sv`: validated session configuration outputs.
- `rtl/engine_c_c3/engine_c_lab.sv`: configuration connections.
- `rtl/engine_c_c3/sid_native_scheduler.sv`: rational fractional CE and launch latch.

New `hw/engine_c_c3/` QPF/QSF/QIP/Tcl files select those three instead of their
C2 counterparts. They reuse the existing C2 Capacity profile adapter, upload
shim/backend, DDR record store/arbiter, SID wrapper and vendor RTL unchanged.
The dedicated source graph contains 63 unique HDL files, each selected module
exactly once. There is no subtractive QSF overlay or production source edit.

`tools/engine_c_c3/` contains the reference harness, mixed-load/full-shell tests,
clock-latch bench and source audit. C0/C1, production A/B, Supervisor, classifier,
Player, Main and production Profile C registration are untouched.

## Tests and audio outputs

See [RESULTS.md](RESULTS.md). The runner builds synthetic original streams using
the frozen C0 API, validates each and produces four three-second WAVs. It does
not bundle any third-party SID music.

```sh
python3 tools/engine_c_c3/run_tests.py
python3 tools/engine_c_c3/audit.py
```

The first command also reruns the frozen C2 Capacity reference (which in turn
runs the original C2 regression). `--reuse-reference` can reuse that completed
run at `/tmp/megavgm-c3-c2-reference`. Generated files, WAVs and machine-readable
reports default to:

```text
/Users/daizo/Projects/MegaVGMPlayer_EngineC_PhaseC3_Artifacts/
```

No generated waveform is a hardware audio claim. PAL/6581's WAV and every PCM
frame match the C2 reference exactly.

## Windows build / hardware follow-up

Synchronize the **entire C3 worktree**, including reused C2 source directories:

```text
/Users/daizo/Projects/MegaVGMPlayer_EngineC_PhaseC3/
```

QPF:

```text
hw/engine_c_c3/MegaVGMPlayer_EngineC_C3_Lab_MiSTer.qpf
```

From that directory on Windows:

```bat
quartus_sh --flow compile MegaVGMPlayer_EngineC_C3_Lab_MiSTer
```

Expected, not yet built:

```text
hw/engine_c_c3/output_files/MegaVGMPlayer_EngineC_C3_Lab_MiSTer.rbf
```

Keep the hardware-PASS C2 Capacity RBF intact. The existing C2 OSD lab entry uses
`.MVG` extension for MVGMSID bytes; for manual OSD load, copy/rename a generated
tone's `.mvgmsid` file to `.mvg`. The stream bytes must remain unchanged.

Remaining gates: Windows synthesis/fit/timing (including widened CE arithmetic),
four-combination hardware audio, continuous model/timing reload on MiSTer, and
regression of the user's PAL/6581 titles. Production Engine C integration and
license clearance remain outside C3; existing [SID provenance caveats](../engine_c_c2/PROVENANCE.md)
are unchanged. Mac elaboration uses HPS/PLL stubs and is not full Quartus proof.
