# Golden Player Shell v1.1 Stage B targeted regression

Run `bash tb/golden_player_shell_v1_1/stage_b/run_all.sh` from the repository
root. The runner uses the existing Stage B fixture generator, scanner test,
read-adapter test, and Olga reference without modifying them. New integration
tests exercise the v1.1 wrapper through accept/reject/reload/reset/abort/stale
flows, the physical upload and title path with the 934,025-byte prepared Olga
file, and the final stable-emu audio gate after its inherited reset hold.

Icarus, Verilator lint, and Verilator elaboration JSON use the actual Stage B
project source graph. Outputs go to a temporary directory. Quartus and Stage C
tests are never invoked.
