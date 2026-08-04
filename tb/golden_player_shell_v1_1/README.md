# Golden Player Shell v1.1 targeted regression

Run `bash tb/golden_player_shell_v1_1/run_all.sh`. The runner audits the two
actual QIP graphs, reuses the stable upload/title regression, verifies Stage A
constant silence, measures the Audio Lab 44.1 kHz/1 kHz/±2048 contract,
elaborates both stable emu graphs with Icarus and Verilator, executes the lab
tone through final emu `AUDIO_L/R`, and emits Verilator elaboration JSON under
`/tmp`.
It never invokes Quartus and does not run Stage C/JT10 regressions.
