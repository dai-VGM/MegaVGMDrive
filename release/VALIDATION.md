# Phase 2 validation scope

## Frozen artifact gate

- Formal `megavgm_remote` is a byte-copy of the user-confirmed Phase 1 artifact:
  10,515,056 bytes; SHA-256
  `9cb59cb4032843a7e9b8368941540904da5d995df7d0b443b9e317f5a642cd7e`.
- Exact ARM ELF: ELF32 ARM EABI5, flags `0x5000400` hard-float, static,
  no PT_INTERP, no dynamic section / DT_NEEDED.
- Exact ARM QEMU HTTP/API gate: `/megavgm`, `/megavgm/`, linked assets,
  manifest and icons 200. Embedded JS `/assets/megavgm-36f68731.js`, SHA
  `55b6b07c1c4684cfe60a3d86128630ac88f61885957a0c9ada5c2e45c32cf649`.
- Favorites/Playlists CRUD, Browse, Play/Next/Prev/Stop/Repeat/Shuffle,
  transport/soundChips status, no MiSTer Remote APIs, and 8183 conflict rejection
  passed the existing `tests/service_gate.py` against the final ARM itself.
- A→B→B→A and playlist completion→STOCK are status fixtures, not FPGA tests.
- Native Linux service identity/restart/concurrent-start/crash/forged-PID tests
  passed using the existing native Phase 1 service executable. Its older frontend
  is NOT used as evidence for the final embedded UI. Go service source is unchanged.
  QEMU user-mode /proc identity differences prevent a trustworthy service-identity
  assertion there; no identity protections were weakened.

## Packaging gates

`tests/phase2_install_gate.py` exercises isolated FAT roots on existing Linux Lima:

- clean install, byte-for-byte v2.0 payload upgrade, Phase 1 upgrade;
- duplicate install is no-op, startup block exactly once, original blocks unchanged;
- rollback restores before bytes, introduced files recoverably retired;
- JSON edits after install retained; customized and known-v2 Remote untouched;
- old RBF/rescue/library files untouched;
- corrupt package, duplicate/unknown startup, symlink paths rejected;
- rollback refuses later user edits;
- interrupted before/after mixed transaction can roll back;
- startup block forwards boot/default, start, stop, restart without ENTER.

Package checksums and ZIP payload inventory are checked separately. No daemon,
helper, Supervisor, controller, Main, RBF, importer, or Frontend was rebuilt.
Only release scripts/docs/tests are changed in Phase 2.

## Hardware

The user reported Phase 1 A→B→A, same-profile, restart-with-audio, persistence,
STOCK restoration, 8182 coexistence and iPhone layout PASS. **Phase 2 reboot /
autostart / install acceptance remains NOT RUN.** Follow HARDWARE_CHECKLIST.md.
