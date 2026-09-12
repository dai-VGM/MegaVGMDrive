# MegaVGMPlayer v2.2 Stage 1 — RBF naming migration

This branch prepares the final `MegaVGMDrive_A.rbf`, `MegaVGMDrive_B.rbf`, and
`MegaVGMDrive_C.rbf` distribution names. Engine A/B use the new exact production
paths; Engine C is staged only and is not yet connected to PROFILE_C routing.

See [release/README.md](release/README.md),
[release/README.ja.md](release/README.ja.md),
[validation](release/VALIDATION.md), and
[hardware acceptance](release/HARDWARE_CHECKLIST.md).

No Player, transport, classifier decision, OSD, RTL, or audio implementation is
changed. Legacy v2.1 RBFs are retained for coexistence and rollback.
