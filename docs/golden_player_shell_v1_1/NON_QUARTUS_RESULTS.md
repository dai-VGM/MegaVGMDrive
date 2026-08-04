# Golden Player Shell v1.1 non-Quartus results

Validation date: 2026-08-04. These are simulation, elaboration, lint, source
graph, and repository-integrity results. They are not a Quartus build or a
MiSTer hardware PASS.

## Audio contract results

- Stage A remained inert through raw/prepared upload, title, Reset, reload,
  abort/reload, a 934,025-byte upload, and 120 seconds-equivalent idle.
  Reader requests, scanner/parser starts, sound writes, enable rises,
  sample-valid, and final audio were all zero.
- Audio Lab emitted exactly 44,100 valid samples, 1,999 sign changes, identical
  L/R, and peak magnitude 2,048. The sequence passed twice around software
  Reset, with exactly one enable rise per sequence and zero outside the tone.
- The actual Audio Lab stable-`emu` runtime reached final `AUDIO_L/R` for
  20,000,000 non-zero `clk_sys` cycles at peak magnitude 2,048, then returned
  to mute. Completion was at 76,777,237 cycles after external Reset release.
- The inherited stable shell holds internal Reset for 16,777,216 cycles.
  Therefore the profile's exact two-second silence starts after that hold; at
  20 MHz, first audible output is expected about 2.839 seconds after external
  Reset release and lasts about one second.
- Profile, shim, stable emu final gate, and final `AUDIO_L/R` were compiled and
  executed as one design. Verilator elaboration JSON retained
  `profile_audio_enable`, `audio_gate_open`, and `AUDIO_L` in the Audio Lab
  graph, confirming the candidate route was not replaced by the v1.0 constant
  gate.

## Tool and source-graph results

- Icarus compile/elaboration: PASS for Stage A and Audio Lab profiles, both
  complete stable-emu graphs, both shim tests, and upload/title regressions.
- Verilator lint/elaboration: rc 0 for both graphs; undefined modules,
  duplicates, `LATCH`, `MULTIDRIVEN`, and `UNOPTFLAT` all zero.
- Relevant X/Z: zero. Signed audio width is 16 bits; peak, polarity, L/R
  equality, sample-valid cadence, enable assert/deassert, and Reset retrigger
  all passed.
- Each QIP graph has nine direct sources and nine unique modules, exactly one
  v1.1 `mister_vgm_md_top`, exactly one selected v1.1 profile, and no v1.0
  shim, scanner, parser, sound chip, ADPCM, PCM reader, testbench, duplicate,
  forbidden, or absolute source.
- Both QSF files are byte-equivalent to the hardware-PASS v1.0 Stage A QSF
  after replacing its one profile QIP assignment. System QIP/Tcl support is
  byte-identical to that project.
- Stable title helper integration passed for ordinary and near-limit prepared
  payloads.

## Repository integrity results

`AGENTS.md`, stable `rtl/emu.sv`, Golden Player Shell v1.0, existing Stage
A/B/C, production sources/projects, the old YM2610 profile, HW-0,
JT10/formal/pristine sources, the protected 35 untracked diagnostics, Sacred
TB, and every stash entry remained unchanged. Candidate paths contain no
Quartus database/output, waveform, audio, log, or generated cache artifact.
`git diff --check` passed.

Canonical command:

```sh
bash tb/golden_player_shell_v1_1/run_all.sh
```

Final marker: `GOLDEN_SHELL_V1_1_NON_QUARTUS_RESULT PASS`.
