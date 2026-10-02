# MegaVGMPlayer v2.3 four-engine final release candidate

Current packaging/version authority: [final promotion](release/FINAL_PROMOTION.md).
The twelve accepted payloads are unchanged. Tag and GitHub Release creation are
not authorized yet; existing public v2.2 remains immutable.

## Historical v2.2 Engine C C6 candidate notes

The following notes describe the earlier lab milestone, not the current final
candidate or its accepted payload authority.

This branch integrates the hardware-tested Packed MVGMSID v2 Engine C into the
existing automatic production routing and adds on-demand raw SID preparation.
Place a single-SID `.sid` file in `/media/fat/MegaVGMDrive/`; Browse presents
the original track while the HPS prepares and caches a strict Packed MVGMSID v2
artifact before the unchanged PROFILE_C load.

See [release/README.md](release/README.md),
[release/README.ja.md](release/README.ja.md),
[validation](release/VALIDATION.md), and
[hardware acceptance](release/HARDWARE_CHECKLIST.md).

Engine A/B routing decisions, Player semantics, transport/fade ownership, OSD,
and SID RTL/audio are unchanged. The candidate raises the implementation
capacity to 8 MiB without changing Packed MVGMSID v2 format; that capacity
extension remains hardware-unverified. Prepared cache files are hidden outside
the music library. Legacy v2.1 RBFs remain available for rollback.
