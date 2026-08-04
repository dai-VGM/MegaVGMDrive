# Golden Player Shell v1.1 Stage B non-Quartus results

Validation date: 2026-08-04. These are Mac-side simulation, elaboration, lint,
source-graph, and repository-integrity results. Quartus was not run, and Stage
B hardware validation remains pending.

## Reuse and source graph

- Existing Stage B compatibility decoder, scanner, read adapter, profile,
  fixtures, and Olga reference remained byte-for-byte unchanged.
- The new v1.1 profile wrapper directly instantiates the existing public Stage
  B profile; copied or forked scanner/read/DDR logic: zero.
- The actual QIP graph has 13 sources and 13 unique modules: one scanner, one
  read adapter, one existing Stage B profile, one v1.1 profile wrapper, one
  v1.1 public shim, and no v1.0 shim.
- Parser, wait engine, sound core, JT10/JT49/JT12/JT51, ADPCM playback,
  playback PCM client, Stage C, HW-0, testbench, absolute, duplicate, and
  undefined sources are absent.
- The Stage B QSF equals the v1.1 Stage A template after replacing exactly its
  profile QIP assignment. System QIP/Tcl files are byte-identical.

## Scanner and lifecycle

- All unchanged fixture-generator cases passed: standard, B-compatible,
  B-only key/frequency/operator writes, dual, unknown register, unsupported
  opcode, malformed/compressed/unknown data block, A/B range, payload EOF,
  descriptor overflow, missing end, invalid loop target, raw, and prepared.
- Actual v1.1 wrapper integration passed raw/prepared accept, rejected-to-valid
  reload, aborted-upload reload, stale response quarantine, stale-generation
  isolation, software Reset during upload, software Reset during scan, and
  accepted idle for 120 seconds-equivalent time.
- Wrapper lifecycle final accounting was 2,425 accepts and 2,425 responses.
  Request/address hold, single outstanding, no upload read, no duplicate scan
  start, and post-scan request/outstanding zero all passed.
- The read-adapter timeout, captured-address/transaction, stale response, and
  permanent request-deassert contracts passed unchanged.

## Olga result

- Source SHA-256:
  `7fd15fe7bf9537128bc2eb2db957a8ccf40cdac394675137a40ba2a9daa66246`
- Physical upload: 934,025 bytes; original body: 933,897 bytes.
- Physical upload completion and final partial write fence: PASS.
- Classification: B_COMPATIBLE.
- Commands 171,869; writes 81,272; port 0/1 38,246/43,026; samples
  8,372,668; B-only/unknown/unsupported/SSG all zero.
- ADPCM-A key on/off 793/850; ADPCM-B START/RESET 23/27.
- Loop target `0xB6223`; end PC `0xE3F24`.
- Trace hash `7c3088bd1d4ee6f`; first-256 hash `155cbbc09e7b636b`.
- Descriptor A/B counts 4/3. All seven entries, 14 boundaries, 256
  deterministic addresses in each ROM space, and four gap/range misses passed.
- Scanner-only requests/responses: 378,149/378,149. Physical prepared-file
  integration reads: 378,277/378,277, including 128 metadata bytes.
- Title metadata and post-scan read quiescence passed. The Olga file, payload,
  fixtures, and dumps are not part of the candidate tree.

## Playback and audio invariants

- `profile_audio_enable` rise count: zero through all lifecycle and Olga tests.
- Signed profile L/R and sample-valid: known zero.
- Parser start, playback active/start surface, sound writes, and both PCM
  playback requests: zero. Sound devices and playback clients in graph: zero.
- Verilator executed the actual v1.1 Stage B profile -> v1.1 shim -> unchanged
  stable emu gate -> final `AUDIO_L/R` graph for 17,000,000 cycles, beyond the
  inherited reset hold: gate rises zero and final audio/sample-valid zero.
- Elaborated JSON retained the v1.1 profile, existing Stage B profile/scanner,
  `profile_audio_enable`, `audio_gate_open`, and final `AUDIO_L` hierarchy.

## Tools and integrity

- Icarus profile/integration and full-emu compile/elaboration: rc 0.
- Verilator lint/elaboration/runtime: rc 0; `LATCH`, `MULTIDRIVEN`, and
  `UNOPTFLAT` zero.
- Relevant X/Z, duplicate/undefined modules, combinational-loop indication,
  request/response drop, stale delivery, underflow, and owner mismatch: zero.
- Stable ordinary/near-limit title helper integration: PASS.
- Golden Shell v1.0, v1.1 core/Stage A/Audio Lab, existing Stage A/B/C,
  production, old profile, HW-0, JT10/formal/pristine, protected 35 untracked,
  Sacred TB, and every stash entry remained unchanged.
- Candidate build artifacts/cache/logs: zero. `git diff --check`: PASS.

Canonical command:

```sh
bash tb/golden_player_shell_v1_1/stage_b/run_all.sh
```

Final marker: `GOLDEN_SHELL_V1_1_STAGE_B_NON_QUARTUS_RESULT PASS`.
