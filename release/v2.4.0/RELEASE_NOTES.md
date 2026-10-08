# MegaVGMPlayer v2.4.0 — Architecture Refresh

Release Candidate; prepared locally, not published or deployed.

This release refreshes internal playback architecture while aiming to preserve the existing supported sound chips and user features. It adds no new sound chip and does not combine Engines A and D. Unverified full compatibility is not claimed.

- Engines A/B/D use shared Strict Reader, Common VGM Parser and continuous logical Scheduler infrastructure with engine-specific adapters and sample clients. The retained Transport boundary continues to own loop/fade policy.
- Engine C is unchanged, including its exact stable RBF and independent SID native-cycle playback/preparation path.
- Engine A uses the accepted A1 balanced resource selection and A2 FIFO RAM-inference repair. Resources are 23,503 ALM / 3,705 LAB / 85 M10K; constrained worst setup +0.088ns.
- Engine B retains its proven JT10/ADPCM/cache path and uses prepared-store synchronous metadata RAM / shared preparation comparators. Seed3 gives 31,787 ALM / 3,995 LAB / 84 M10K; constrained worst setup +0.467ns. Two independent Full Compilations reproduced resources, Timing and RBF bytes.
- Engine D uses 22,074 ALM / 3,700 LAB / 79 M10K; constrained worst setup +0.495ns.
- A/B/D pass the five reported Timing checks in all four corners, with zero reported TNS. Inherited external-I/O/constraint limitations remain disclosed; Flow Successful alone is not a Timing guarantee.
- Frozen Mac source, immutable root-QPF Build Artifacts and Windows Quartus 17.0.0 Build 595 reports provide traceable builds. Future sound-chip work starts with shared infrastructure plus an explicit Adapter/Core/Storage extension.

Canonical A–D filenames, Main, Controller, Supervisor, Remote/PWA and helper payloads remain compatible by retained identity and the scoped user tests. There are no Player UI, queue or navigation feature changes. Activity and Main-directed transparent bottom Loading remain required production interfaces.

Hardware acceptance is limited to DAI's reported checks for each exact RBF. Long-duration, all-track compatibility and the complete Stop/Next/Reload/loop/cross-engine admission matrix have not been newly certified. C retains legacy producing-build provenance limits. See HARDWARE_ACCEPTANCE.md, TIMING.md and KNOWN_LIMITATIONS.md.

日本語: 新音源追加ではなく内部基盤の刷新です。A/B/DをvNext基盤へ移行し、Cと既存Runtime/PWAは維持します。未検証の全曲互換性・長時間安定性は保証しません。
