# Engine C Phase C2 — PAL/6581 SID lab

Branch: `engine-c-phase-c2`, based on
`e7b479d029578a7196779e6aba11a3271e0f9bc2`.

This is a **simulation-validated standalone lab**, not a production Engine C
release. No Quartus compilation, RBF build, hardware audio validation, or host
profile integration has been performed. C0/C1 and all existing production files
remain unchanged. Redistribution/license clearance is outstanding; see
[PROVENANCE.md](PROVENANCE.md).

## Architecture

```text
index-1 .MVG (MVGMSID v1 bytes)
  → Golden Shell physical DDR upload
  → strict whole-file preflight
  → timestamped WRITE/EOF RAM
  → native-cycle fractional-CE scheduler
  → single C64_MiSTer SID (6581)
  → reset-qualified publication → signed 18-to-16 → Golden Shell audio
```

The loader consumes the frozen C0 128-byte header and 16-byte records, little
endian. WAIT adds to an unsigned 64-bit native-cycle cursor; WRITE records its
absolute timestamp and original address/data; EOF records the validated final
cycle. No rounding, dropping equal-value writes, loop guessing, or opcode
reinterpretation occurs. All file bytes are validated before SID playback.

### Admitted C2 subset and errors

- v1.0, header size 128, event size 16; single SID only.
- PAL indication 1, clock numerator 985248, denominator 1, model 1 (6581).
- DURATION_KNOWN, END_IS_CAPTURE_LIMIT and explicit model/clock override flags
  retain C0 meanings. Duration flag/value consistency is checked.
- LOOP_VALID and nonzero loop fields are rejected. 8580/NTSC are valid v1
  concepts but are explicitly unsupported in this first lab execution path.
- Maximum 8,192 events / 131,200 input bytes and 4,095 WRITE descriptors plus
  EOF. These are advertised lab resource bounds, not changes to the format.
- Reserved bits/bytes, unknown opcodes/version/flags, invalid register,
  same-cycle writes, zero WAIT, unsigned sum overflow, count/size mismatch,
  truncated/trailing file data and malformed/early/missing EOF all reject.
- Source SHA bytes are metadata, not a payload-integrity checksum in v1.

Error codes: 1 file range; 2 preflight read timeout; 3 identity/version/sizes;
4 flags/reserved; 5 model/timing/clock/single/subtune; 6 event/file sizes;
7 duration/loop metadata; 8 event reserved; 9 WAIT; 10 WRITE;
11 descriptor capacity; 12 EOF/final cycle; 13 opcode; 0x80 scheduler fatal.
Loading watchdog is a fatal diagnostic bound, not a playback delay.

### Exact CE and WRITE phase

`SYS_HZ = 20,000,000` from the existing PLL's actual output configuration.
After launch at cycle 0, initialize `phase=0`. Every SYS clock:

```text
sum = phase + 985248
ce_sid = (sum >= 20000000)
phase = ce_sid ? sum - 20000000 : sum
```

After `k` SYS edges, CE count is exactly `floor(k*985248/20000000)`.
Native edge `n` occurs at `ceil(n*20000000/985248)`; intervals are 20/21 SYS
clocks. There is no accumulated per-event rounding and no fixed 1 MHz clock.
The CE pulse is a combinational decode of registered phase, stable for one SYS
cycle and sampled on its rising edge. At 20 MHz there is room for SID's complete
16-edge publication pipeline before the next CE.

WRITE timestamp 0 is sampled at the launch edge (before the first CE).
WRITE timestamp n>0 is sampled on exactly CE n. SID register and oscillator
processes use nonblocking assignments: oscillator n consumes the previous
register; the newly written value is available for oscillator n+1. The test
checks the register sequence and oscillator accumulation across these edges.
Adjacent native-cycle writes remain adjacent; they are not 44.1 kHz quantized.

The synchronous descriptor RAM is prefetched between CEs. A missing head at
a native edge, overdue descriptor, or cycle overflow is fatal; no late write
is issued. After launch CE continues even after fatal/EOF, until explicit
session reset. A starvation fault never pauses SID clock to catch up.

### SID wrapper constants and publication

`reg_addr[4:0]`, `reg_data[7:0]`, `reg_write`, `ce_sid`, synchronous `reset`,
`model` enter `sid_session_wrapper`. Model is latched during reset and cannot
change in-session; C2 connects 6581. DUAL=0, cfg=0, cutoff offsets=0 select the
default stock curve. C64's `C64.sv` maps offsets to zero when adjustment is off.
POT inputs are 0xff (unconnected/open); ext_in=0 matches C64's 6581 path, whose
external MSB is `sid_ver AND sid_digifix`. No loader writes are enabled for the
tables. filter_en=1 is retained, although the pinned top does not use that port.

Audio is explicitly `$signed` 18-bit, mirrored L/R, adapted by `[17:2]` to the
shell's signed 16-bit range. No audio algorithm or coefficient is retuned.
See [RESET_AUDIT.md](RESET_AUDIT.md) for the full state inventory and exact
publication timing.

### Lab transport scope

Golden Shell v1.1's physical upload/read/audio boundary is reused in versioned
copies. Index-1 resets the lab profile during download; backend completion
causes exactly one preflight/start. Index-2 is ignored without rearming it.
Done and fatal are observable at the shell. EOF immediately mutes and terminates
the lab parser in the same run; there is no auto repeat.

**Common production fade/session/status v1.3, FADE_ONLY, replacement fade and
Supervisor integration are not implemented in C2.** Do not use this RBF through
production Player. They must be adapted in a later transport phase, not assumed
from the shell port names. The synthetic tone includes a one-second ADSR release
before EOF; this is test content, not an added transport fade engine.

## Reproduce on macOS (no Quartus)

From repository root:

```sh
python3 tools/engine_c_c2/run_tests.py
python3 tools/engine_c_c2/audit.py
python3 -m unittest discover -s tools/engine_c_c0
python3 -m unittest discover -s tools/engine_c_c1
```

The last suite uses a pre-existing C1 helper if `MVGMSID_C1_NATIVE_HELPER` points
to one; otherwise its six native tests are explicitly skipped. No C1 rebuild
is required. C2 uses Verilator 5.050, a C++ compiler, Tcl and Python stdlib.

Default output: `/tmp/megavgm-engine-c-c2/`. `--out` selects another directory.
It contains original generated `tone-pal-6581.mvgmsid`, byte-identical `.mvg`
for the lab OSD's three-letter extension filter, a 44.1 kHz mono WAV, test JSON,
and separate compile logs. This is generated original 440 Hz voice-1 saw with
ADSR/filter, 2 seconds gated plus 1 second release; no copyrighted SID tune.
WAV generation samples the held RTL output; it is an inspection aid, not a
model of MiSTer's final analog/HDMI reconstruction chain.

`audit.py` checks all imported SID hashes, optional upstream git blobs,
production/C0/C1 immutability, recursive QIP resolution, duplicate sources,
and one definition of every SID/top/profile module. It elaborates actual emu,
shim, upload, parser, scheduler and SID with HPS/PLL **simulation stubs only**.
Hardware QIPs contain actual platform/PLL sources, not those stubs.

## Windows Quartus lab project

Sync the complete `engine-c-phase-c2` worktree, not only a QSF.

```bat
cd <checkout>\hw\engine_c_c2
quartus_sh --flow compile MegaVGMPlayer_EngineC_C2_Lab_MiSTer -c MegaVGMPlayer_EngineC_C2_Lab_MiSTer
```

QPF: `hw/engine_c_c2/MegaVGMPlayer_EngineC_C2_Lab_MiSTer.qpf`

Expected output (not generated):
`hw/engine_c_c2/output_files/MegaVGMPlayer_EngineC_C2_Lab_MiSTer.rbf`.

The QSF is self-contained, with explicit platform imports and no source
remove/subtract overlay. It resolves 61 unique HDL files. Production SID-free
tops and provenance-only upstream SID modules are not re-added indirectly.

After successful Windows synthesis/fitting/timing, manually start this lab RBF
without Supervisor/Remote. OSD: **Load prepared SID**, select the generated
`.mvg` file. Check a tone, EOF, repeated loads and reset. Preserve all production
RBFs/artifacts. Hardware PASS is for the user to establish; none is claimed here.

## Remaining qualification

- Windows Full Compilation/resource/timing closure, actual MiSTer audio.
- Full transport adaptation, status/session v1.3 and shared fade owner.
- External/publication license clearance for the imported dependency set.
- Larger streaming storage architecture (C2 bounded preflight RAM is deliberate).
- 8580, NTSC, digi/filter corpus and formal/X-state testing; no dual SID or loop
  playback is added by this phase.
