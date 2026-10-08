# MegaVGMPlayer v2.4.0 — Architecture Refresh RC

Status: **RC_READY** — scoped local integration, with disclosed provenance/test limitations. No deployment, GitHub Release, tag or push.

Selected A1+A2 A, optimized seed3 B, unchanged stable C and D vNext are frozen as separate RBFs/builds. This refresh adds no chip and does not combine engines. Existing Main/Runtime/PWA/helper bytes and canonical A–D launch names are retained.

| Engine | Adopted source/config | RBF SHA256 | Windows evidence |
|---|---|---|---|
| A | `b4e1b9c` | `57b005ae66c586189e153cfe09b4b680e781deaec29bac1f19654e42f5b9b6c3` | all4corner constrained PASS |
| B | `2241e0f` / implementation99d4928 / seed3 | `70392ce76932c85c21cd5f2ef3a73f1b07026e7573c8e75e753a804660d51507` | all4corner constrained PASS |
| C | `82402ec` | `45f63808ca4d9871716af0bbc46f2335cd49d14fceafb537108ef2fa9f3e6110` | retained stable legacy; no new signoff |
| D | `26d5078` | `064c398c42d7daa729bf5081efba6213ca872d8f7f9b1889f1004a24e0422ed7` | all4corner constrained PASS |

See [adoption manifest](release/v2.4.0/adoption-manifest.json), [Release Notes](release/v2.4.0/RELEASE_NOTES.md), [build instructions](release/v2.4.0/BUILD.md), [Timing](release/v2.4.0/TIMING.md), [scoped hardware receipts](release/v2.4.0/HARDWARE_ACCEPTANCE.md), [known limits](release/v2.4.0/KNOWN_LIMITATIONS.md) and [publication checklist](release/v2.4.0/GITHUB_RELEASE_PREPARATION.md).

The old A Timing blocker is resolved by selecting b4e1b9c, not by changing the old RBF or waiving Timing. The complete [original BLOCKED audit](history/96edaa2/README.md) and its commit/checksums are preserved. Current canonical snapshots are in canonical/current; before snapshots remain in canonical/before. Existing production/v2.3 authorities remain untouched.

Validation: `python3 tools/verify_v240.py`. Package assembly: `python3 tools/build_v240.py --base-v23 /path/to/MegaVGMPlayer-v2.3.zip --out /new/isolated/output`. Never use an existing production directory as output. Source ZIPs under artifacts/build are exact copies; C retains the explicitly documented legacy-layout exception. BUILD.bat is optional.

RC_READY means this scoped local integration/package is prepared. It does not mean public release, deployment, a newly completed full-admission/long-duration/all-track matrix or hardware proof of every software-reference edge case.
