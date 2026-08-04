# Golden Player Shell v1.1 Stage C targeted tests

Run from the repository root:

```sh
bash tb/golden_player_shell_v1_1/stage_c/run_all.sh
```

The runner creates all generated fixtures, logs, Icarus executables, and
Verilator objects in a temporary directory and removes it on exit. It requires
Icarus, Verilator, Python 3, and the exact prepared Olga file at
`/Users/daizo/Music/03 Olga Breeze.vgm`. Set `OLGA_VGM` only when the same
SHA-256 file is stored elsewhere.

The suite first audits the immutable/reuse/project boundary, then runs the
unchanged owner/read/parser/fault and sound hash tests, the new versioned
wrapper lifecycle test, Icarus full-emu elaboration, Verilator full-graph lint,
and actual stable-emu FM, SSG, suppressed-PCM, and prepared-Olga integrations.
It finishes with title/video and repository-integrity audits.

`hps_io_stage_c_upload_stub.sv` is simulation-only and exists only in
`stage_c_full_emu_sources.f`; it is prohibited from the QIP. The synthesizable
graph is `stage_c_emu_sources.f`, which mirrors the project QIP plus elaboration
stubs for external MiSTer/PLL surfaces.
