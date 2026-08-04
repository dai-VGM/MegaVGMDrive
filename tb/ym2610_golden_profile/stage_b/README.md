# Golden Shell Stage B tests

Run `bash tb/ym2610_golden_profile/stage_b/run_all.sh` on macOS. The runner
never invokes Quartus and writes generated fixtures/build output only below a
temporary directory.

The local acceptance file must remain outside the repository at
`/Users/daizo/Music/03 Olga Breeze.vgm`; its SHA-256 is checked before use.
Neither that VGM nor any payload, dump, waveform, or generated fixture is
committed.

The suite covers the single-client adapter contract, raw/prepared lifecycle,
reset/reload/abort/stale behavior, all negative classifications, the complete
Olga RTL scan, descriptor boundaries and 256 deterministic payload mappings in
each ROM space, a real 934,025-byte upload through the immutable DDR backend,
full `emu` elaboration, Verilator structural checks, and Stage A provenance.
