# YM2610 profile regression

Generated VGM fixtures are written only to a temporary directory. The fixture
generator covers standard FM, JT49 A/B/C, ADPCM-A, ADPCM-B, simultaneous A+B,
raw/prepared title forms, a B-compatible positive, B-only key-on/setup rejects,
dual/unknown/opcode/range rejects, loop and load lifecycle. No generated VGM or copyrighted Olga
payload is committed.

`inspect_ym2610_vgm.py` is the independent semantic reference. Its trace hash
packs, in order, little-endian command PC, little-endian sample timestamp,
opcode, port, address and data into FNV-1a-64.

Run locally:

```sh
tb/ym2610_player/run_scanner.sh
tb/ym2610_player/run_parser.sh
tb/ym2610_player/run_audio.sh
tb/ym2610_player/run_title.sh
tb/ym2610_player/run_olga_windows.sh
python3 tb/ym2610_player/audit_profile.py
```

The audio runner models a variable 12–15-cycle byte response. Its cache is made
smaller than hardware (32 rather than 64 entries) to stress replacement while
leaving room for the eight-slot repeated-B reservation and simultaneous A
owners. The committed QIP uses the 64-entry default.

`run_scanner.sh` compares RTL descriptor lookup against the independent Python
mapping at every descriptor boundary, explicit gaps and 256 deterministic
legal random addresses in each A/B space. `run_olga_windows.sh` never commits
derived payloads: it creates bounded local B, FM, A, simultaneous A+B and loop
windows in its temporary directory, checks parser traces against Python, then
runs each JT10 audio window three times.

The loop window is a bounded transition fixture: it retains all seven Olga ROM
blocks byte exact, the final 3,000 samples of register/wait events and the first
9,000 samples at the real loop target. Its end command loops backward to that
post-loop slice, after which 9,000 additional public audio samples are checked.
