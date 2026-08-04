# Stage C non-Quartus regression

Run `bash tb/ym2610_golden_profile/stage_c/run_all.sh` on the Mac. It creates
all VGM, trace, simulator, and log artifacts below a temporary directory and
does not run Quartus. Olga is read from
`/Users/daizo/Music/03 Olga Breeze.vgm` (override with `OLGA_VGM`) and must
match the pinned SHA-256. No VGM or audio payload is committed.

Coverage includes immutable provenance, QSF/QIP/source graph, raw/prepared
loads, Stage B scan, full independent Olga parser trace, owner fencing,
backpressure, defensive faults, standard FM, SSG A/B/C, PCM suppression,
all reject classes, no-loop end, loop continuity, reset/reload phases,
direct/parser replay, deterministic audio hashes, full `emu` Icarus
elaboration, Verilator lint, title/video integration, and HW-0/pin audits.
The Olga replay keeps sound-core state from the song start through the loop
and checks five FM/final-LR windows in three Verilator runs; synthetic direct
replay and the full parser trace are also run under Icarus.

The old candidate hashes `7c6b79c702fe3c29` and `4af421aa03326d95`
belonged to different fixture/measurement contracts and are not asserted.
