# Golden Player Shell v1.1 Stage C non-Quartus results

Validation date: 2026-08-04. Quartus was not run on Mac. These results do not
claim a MiSTer hardware PASS.

## Source and project integrity

- Existing Stage B/C RTL and reference blobs are unchanged; implementation
  copy/fork count is zero.
- The actual QIP graph contains 75 relative sources and 76 unique modules,
  with one v1.1 wrapper, one v1.1 shim, one public Stage C profile, and no v1.0
  shim or duplicate module.
- The QSF is normalized-equivalent to the hardware-PASS v1.1 Stage B template
  after its single profile QIP substitution. System QIP/Tcl files are exact.
- PCM DDR/cache/arbiter, Stage D, old player, production profile, HW-0
  sequencer/video/ROM, JT51, JTOUTRUN, SegaPCM, and testbench modules are
  absent. Seven pinned synthesizable vendor leaves retain their provenance.
- Golden Shell v1.0, the v1.1 ABI and existing projects, production, old
  profile, HW-0, existing Stage B/C, JT10/formal/pristine sources, protected
  35 untracked files, Sacred TB, and all stash entries are unchanged.

## Lifecycle, reader, reset, and faults

- The wrapper gate rises before parser start, once per accepted generation;
  it stays open through a loop and closes on end, upload/reload, and software
  Reset. Disabled L/R/sample-valid remain known zero.
- Wrapper integration passed four representative rejects followed by recovery,
  raw/prepared load, ENDED_IDLE reload, same/different reload, suppressed PCM,
  valid loop, and Reset during upload, scan, sound reset, first playback wait,
  and live loop/playback.
- Scanner/parser concurrent requests, PCM request/lane activity, command
  duplication/drop/reorder, stale delivery, owner mismatch, and X/Z were zero.
- The unchanged owner/read/fault tests passed two-cycle handoff, request/address
  hold, one outstanding response, response delay/backpressure, timeout,
  generation mismatch, stale quarantine, malformed PC/block/register/opcode,
  BUSY delay timeout, sound fault, and post-fault reload.

## Audio and Olga reference

- Three deterministic sound runs retained full FM hash
  `2a1aa6dc21860dfd`, SSG A/B/C hash `2d7fa36247dc0e75`, and explicit volume
  mute hash `28c31cf8df2ec325`; CEN was 8,000,000/20,000,000 and PCM/X/Z zero.
- Synthetic direct FM/SSG replay retained parser traces
  `3600d68a4c2a4d74` / `7ee5ee210617c916`. The retained-state audio windows
  remain `bda45f7a067cf72d`, `dc663bb0b7349cd5`, `184eec59e4466a7d`,
  `a4a707ca22e4bb61`, and `87a5398c48b391c1`.
- Actual v1.1 full-emu FM produced final `AUDIO_L/R` hash
  `2a1aa6dc21860dfd`; SSG and suppressed-PCM fixtures reached nonzero final
  audio then known-zero end. The signed Stage C -> wrapper -> v1.1 shim ->
  stable emu path matched at every checked sample.
- The prepared Olga physical upload was 934,025 bytes with SHA-256
  `7fd15fe7bf9537128bc2eb2db957a8ccf40cdac394675137a40ba2a9daa66246`.
  Scan totals were 171,869 commands and 81,272 writes with trace hash
  `7c3088bd1d4eea6f`.
- Olga forwarding remained FM/global 78,293, SSG 0, suppressed ADPCM-A 2,752,
  suppressed ADPCM-B 227, B-only/unknown 0, and data blocks 7. Loop target is
  `0xB6223`, end PC `0xE3F24`, and total timeline 8,372,668 samples.
- First ADPCM-B control at sample 4,625 was suppressed; final emu audio stayed
  zero through the first standard FM key-on at sample 120,851 (about
  2.740385 s), which was forwarded; first ADPCM-A control at sample 121,270
  was suppressed. PCM request/lane activity was zero.

## Tools

- Icarus owner/read/parser/sound/wrapper/full-emu compile and elaboration: rc 0.
- Verilator lint/elaboration and actual full-emu FM/SSG/suppressed/Olga runs:
  rc 0; `LATCH`, `MULTIDRIVEN`, and `UNOPTFLAT` zero.
- Relevant X/Z and duplicate/undefined module count: zero.
- Stable title integration and video timing: PASS.
- QSF/QIP/source/reference audits and `git diff --check`: PASS.

Canonical command:

```sh
bash tb/golden_player_shell_v1_1/stage_c/run_all.sh
```

Final marker: `GOLDEN_SHELL_V1_1_STAGE_C_NON_QUARTUS_RESULT PASS`.
