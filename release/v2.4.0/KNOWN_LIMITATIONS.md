# Known limitations / unrun gates

- No new long-duration or exhaustive all-track compatibility certification. Historical simulation checkpoints/deep windows retain their named scope; B's 95 assets comprise 40 full and 55 scoped, not 95 full traversals.
- Complete hardware Stop/Next/Reload/loop/cross-engine/full production admission and package install/upgrade/rollback on MiSTer are not newly performed by this integration. Exact user receipts are in HARDWARE_ACCEPTANCE.md.
- A worst setup margin is only +0.088ns. A/D have one recorded Full Compilation; independent bit-identical reconstruction is NOT_RUN. B has two independent matching runs.
- Timing PASS refers to constrained checks. Inherited unconstrained external-I/O and unmatched SDC filter warnings remain; D records 3 unconstrained inputs / 50 outputs. No SDC weakening or exceptions were added here.
- C RBF/source/native-cycle path is unchanged. Its original producing Windows build is not recovered, and a different old Windows C RBF is not substituted. Legacy project layout is preserved in the exact source-closure snapshot; it is not a new root-QPF Build Artifact.
- A one-span YM2612 DAC client remains limited to the audited admitted corpus. New multi-span asset support needs a separate compatibility phase. Unsupported/reserved VGM commands and dual aliases remain explicit rejects.
- A actual hardware DDR latency/cache envelope remains unmeasured. No new cache is added. B additional resource-cache optimization and A+D integration are future separate projects.
- Immutable older Build Artifacts/evidence may say hardware NOT_RUN; current adoption receipts supersede only the exact selected RBF's reported scope, without rewriting the original evidence.
- Runtime/PWA/Main binaries retain their internal v2.3-era identity strings where present; v2.4.0 is the distribution version, not a claim of rebuilt host software.
