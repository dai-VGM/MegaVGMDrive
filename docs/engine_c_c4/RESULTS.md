# C4 verification results

All results below are **host/simulation results only**. C4 Windows Quartus,
resource/timing closure, RBF generation and physical audio/transition validation
remain unverified. The user's earlier C3 hardware results are the unchanged
baseline, not evidence of C4 hardware success.

## Executed gates

| Gate | Result |
| --- | --- |
| C0 strict format/reference tooling | 41 unit tests passed |
| C1 converter (including existing native libsidplayfp helper) | 22 tests passed, no skipped native tests |
| C4 native/raw suite | 81 simulator invocations passed, including one C3 reference run |
| Actual Golden upload/DDR/SID/common-owner transport | Integrated sequence passed |
| DDR health observer unit test | Passed: progress, raw/descriptor response bounds, BUSY, idle, reset/session clear |
| Actual full-shell scheduler starvation / descriptor corruption | Both passed, including FATAL interrupting FADE_ONLY |
| Full-shell capacity | Three scenarios passed: mixed sequence, max dense twice, oversize twice; each recovers to EOF-only load |
| Unchanged common FADE_ONLY owner suite | Passed: malformed/duplicate/policy/EOF/Stop/FATAL/replacement/loop takeover |
| Unchanged legacy owner regression | Passed: 107 loads, 54 ends, cold/warm100, EOF/manual/predicted-loop/Repeat/policy/FATAL/Stop |
| Unchanged Golden transport ABI suite | Passed: 29 admissions / 26 starts, stale ownership rejection, post-accept failure, reset/index-2 isolation |
| Unchanged reference status v2 suite | Passed: HPS lower-bit preservation, pulse spacing, session priority, loop saturation, FATAL payload (65,546 notifications) |
| QSF source resolution / emu elaboration | Passed Tcl static resolver and Verilator with HPS/PLL stubs, 67 unique HDL source files |
| Scope / source provenance audit | All pre-C4 tracked files unchanged; A/B owner and B transport/publisher byte-identical |

The 81 native/raw invocations include all four three-second tones (each twice),
eight mixed-model/timing resets compared against a clean SID reference, native
CE count/WRITE phase checks, equivalent rational clocks, exact WAIT/EOF checks,
same-value writes, strict malformed/unsupported/LOOP_VALID rejection, native
underflow and descriptor corruption, and the existing C2 capacity vectors.

Capacity vectors include 131071 / 131072 / 131073 bytes (unaligned lengths reject
as required), 4194303 / 4194304 / 4194305 bytes, aligned oversize, bad EOF at the
maximum, and explicit address 0x800000 rejection without byte-zero wrap.
The full physical DDR test loads a 4,194,304-byte dense file twice: each session
contains 131,068 WRITE events, and storage emits 262,138 descriptor word writes
(WRITE records plus EOF, two 64-bit words per record).

## Integrated transition checks

The test uses the real strict loader, DDR upload backend/arbiter/store, scheduler,
SID wrapper/RTL, common fade owner and status publisher. External DDR is modeled
with busy intervals and delayed burst responses; SID/audio are not stubbed.

- PAL/6581 natural EOF keeps session busy and SID publications alive after raw
  scheduler busy goes low; more than ten nonzero tail cycles are required.
- PAL/8580, NTSC/6581 and NTSC/8580 FADE_ONLY finish **before raw parser EOF**;
  the new scheduler halt stops events without resetting SID or stopping CE.
- The exact clock-paced ramp is 2,000,128 SYS clocks. An EOF join is 2,000,129.
- Index-2 preserves session, parser-start count, SID reset count and audio_ready.
- END is followed by >2,001,000 SYS clocks of zero output; duplicate FADE_ONLY
  and policy 00/01 cannot restore gain or emit more WRITE events.
- Replacement holds download/reset/session until zero; the new load increments
  session exactly once. Pure manual replacement has no phantom old END.
- EOF joining FADE_ONLY does not restart the ramp or duplicate END.
- Stop during fade immediately zeroes audio and returns IDLE/session 0 without
  a late completion; the next session starts cleanly.
- Invalid model after accepted load publishes the new session as FATAL.
- Missing physical raw DDR return becomes explicit F1, not an accepted byte.
- A raw request delayed in the arbiter plus a late physical response exercises
  the backend's synthesized byte path: return-provenance failure is sticky,
  even when the physical response itself is within its response budget.
- Permanently BUSY DDR during upload cannot strand Main forever on ioctl_wait:
  FATAL is published and remaining bytes are discarded after the existing
  one-second I/O stall budget. No parser start or ENDED is fabricated.
- Dense-record starvation first publishes 0x80; corrupt descriptor publishes
  0x81. The ongoing FADE_ONLY is cancelled, output is zero, session is preserved,
  and ENDED is absent. A later physical timeout may supersede the code with F1
  according to the unchanged common publisher's priority.

## C3 PAL/6581 bit-exact evidence

Both C3 and C4 are compiled against the same raw-publication harness. This
comparison is **before the common gain**, not a comparison of intentionally
different post-EOF final-output gating.

3 seconds, 132,300 mono signed 16-bit samples, 264,600 bytes:

```text
reference-pal.pcm
tone-pal-6581.pcm
SHA-256: 4d8428b1b01918f000bacd913b591ef499ec8e7f84ad76038c477e560c0e6c19
```

Additional generated raw PCM checksums:

| Case | SHA-256 |
| --- | --- |
| PAL/8580 | `8c18a98c1518fb8530e1ac71adee833e7922eb4c34e277f4e47f02b6a73f0b88` |
| NTSC/6581 | `fd4f641b9ab167a84aed40aee6df85713eba0d3b065d798732f61c731ebf296e` |
| NTSC/8580 | `7e7ee9078d8f5fedef88b496b4d602624e8c8c4fe099fd24d29f47ad821934b7` |

The existing C3 WAV files were not rewritten. No third-party SID music is added.

## Evidence location and limits

`/Users/daizo/Projects/MegaVGMPlayer_EngineC_PhaseC4_Artifacts/` contains
`results-raw.json`, `results-transport.json`, `results-capacity.json`,
`results-owner.json`, per-run logs, PCM and original synthetic `tail.mvgmsid`.
`source-audit.json` records reference hashes, macros, module resolution and
capacity; `resolved-sources.txt` and `emu-elaboration.log` record static checks.
Owner JSON also contains compiler invocations; do not count these as additional
simulation cases.

Inherited SID/backend width warnings remain; elaboration is not Quartus timing
closure. A/B sound-title RTL simulations were not rerun: their sources were not
modified; the shared owner/ABI regressions above are the checked common layer.
Host Profile C registration and automatic A/B/C playlist testing are explicitly
outside C4. See [hardware checklist](README.md#hardware-checklist--all-c4-items-still-unverified).
