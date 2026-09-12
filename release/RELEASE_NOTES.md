# MegaVGMPlayer v2.2 Stage 1 — RBF naming migration

- Production Engine A/B paths now use `MegaVGMDrive_A.rbf` and
  `MegaVGMDrive_B.rbf` under `/media/fat/_Custom Cores/Cores/`.
- The hardware-validated Engine C C4 artifact is staged as
  `MegaVGMDrive_C.rbf` for a later PROFILE_C integration stage.
- Engine A/B payloads are byte-identical to v2.1; no FPGA resynthesis occurred.
- Legacy v2.1 RBFs are preserved and may coexist with the new names.
- The package includes matching exact-path Supervisor/controller builds and a
  transactional v2.1-to-v2.2 rollback path.

No Player, UI, audio, OSD, transport, classifier-decision, Main, daemon, or
importer behavior changes are included. Engine C is not production-routed yet.
