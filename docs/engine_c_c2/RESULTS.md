# C2 verification results

Scope: macOS Verilator/Python/Tcl only. No Quartus build or hardware PASS.

| Gate | Result |
| --- | --- |
| C0 unchanged regression | 41 tests successful |
| C1 unchanged regression | 22 tests successful, including six native tests using the existing C1 helper (no rebuild) |
| C2 executable RTL stream cases | 45 successful: 4 valid cases and 41 rejects |
| Scheduler/reset contracts | successful, assertions enabled |
| Golden Shell DDR upload/repeated load | successful, assertions enabled |
| Total C2 runner cases | 47 successful |
| Fixed SID sources | 7 exact upstream git blobs/SHA-256 matches |
| QSF/QIP static source resolution | 61 unique HDL sources, intended SID/top/profile once each |
| emu syntax/elaboration | successful with HPS/PLL elaboration stubs; warnings retained in log |
| Existing production/C0/C1 source changes | none |
| Windows Quartus, FPGA timing/resources | not run |
| Real MiSTer SID audio | not tested |

## Original synthetic tone

- PAL 985248 native cycles/second, 6581, single SID.
- Voice 1, approximately 440 Hz saw, ADSR, routed lowpass filter.
- 21 events: 10 WRITE, 10 WAIT, 1 EOF.
- Final cycle: **2,955,744**, exactly three PAL seconds.
- Each session: **2,955,744 CE**, **2,955,743 internal publications**.
- Two runs: exact WRITE ordinal/native-cycle/data, oscillator phase, and every
  internal audio publication compared. Second run also matches a clean reference.
- WAV: mono signed 16-bit / 44100 Hz / 132300 frames (3 seconds).
- Sample min/max: -4115 / 2538. A one-second steady-state window has 440 rising
  mean crossings. This checks generated tone activity, not subjective audio quality.
- Stream SHA-256:
  `c8f183bba3711c8c55d74e648be0e93436bb567af49ed965675d8ee93975de2a`
- WAV SHA-256:
  `ae3e3527820aaea60bf45915c9bf6a7e18c38ad6dd582b36d29ae5c7e58e2b04`

## Additional RTL checks

- Minimal EOF at cycle 0, adjacent native-cycle same-value WRITE, consecutive
  WAITs, and WRITE/EOF at one timestamp.
- Unknown version/opcode/flags, unsupported model/timing, reserved bytes,
  single-SID requirement, header sizes, duration/loop consistency, malformed
  EOF, register range, zero WAIT, same-cycle writes, truncation/trailing data,
  event count/size multiplication range, WAIT sum overflow, descriptor capacity.
- Missing prefetched descriptor after launch: fatal; **10 CE pulses still
  occur in the subsequent 200 SYS clocks**. No catch-up writes.
- Dirty three-voice/filter session: 9805 nonzero publications. One SYS-clock
  reset with CE low; every output and valid flag equals a clean reference for
  100000 SYS clocks, including **4925 new publications**, all zero.
- Actual Golden upload adapter and unchanged DDR backend against a one-beat
  DDR model: two short-tone uploads each yield **10006 external publications**,
  188 audio changes, EOF, and final zero. Parser start increments once per load;
  an intervening index-2 transfer never restarts the profile.

The simulated DDR is not the physical MiSTer memory subsystem. These tests do
not establish transport fades, public Profile C support, NTSC/8580/digi
correctness, analog quality, or source redistribution permission.
