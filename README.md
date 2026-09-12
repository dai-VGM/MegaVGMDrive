# MegaVGMPlayer v2.2 Engine C C5 candidate

This branch integrates the hardware-tested Packed MVGMSID v2 Engine C into the
existing automatic production routing. Prepared SID files use the single
`.mvgmsid` extension; strict magic/header/body validation, not the extension,
selects PROFILE_C. MVGMSID v1 remains accepted by the same hardware parser.

See [release/README.md](release/README.md),
[release/README.ja.md](release/README.ja.md),
[validation](release/VALIDATION.md), and
[hardware acceptance](release/HARDWARE_CHECKLIST.md).

Engine A/B routing decisions, Player semantics, transport/fade ownership, OSD,
SID RTL/audio, and the 4 MiB Engine C capacity are unchanged. Raw `.sid` files
are not accepted in this stage. Legacy v2.1 RBFs remain available for rollback.
