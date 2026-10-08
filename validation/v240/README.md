# v2.4.0 integration validation — 2026-10-09

Gate: RC_READY, scoped local package/integration only. No new compilation, hardware test, deployment or GitHub/tag/push action.

- Current selection replaces the failing historical A da862ee with approved A1+A2 b4e1b9c. Complete prior audit bytes remain under history/96edaa2; its BLOCKED result is historical and is not relabelled PASS.
- A/B/C/D exact RBF size/hash, producing source/config and scoped user receipt are in release/v2.4.0/adoption-manifest.json. Stable C and eight non-engine payloads are unchanged from the public v2.3 ZIP.
- A/B/D Build Artifacts were freshly extracted: 195/161/132 build inputs respectively, root QPF/QSF and recursive graph complete, no duplicate/missing/absolute/parent/stale source, source order/defines preserved, Quartus compatibility gate PASS. Canonical configuration bytes were not reserialized.
- Read-only Windows SSH checks verified 488 exact build inputs plus three RBFs against the selected Mac bytes (491 expected-hash comparisons). Twelve map/fit/STA/flow report hashes were recorded, giving 503 file checks. No Windows files were changed.
- Saved A/B/D four-corner/five-check Timing evidence passes constrained checks with zero TNS. A +0.088ns / B +0.467ns / D +0.495ns worst setup. B's two independent builds matched; no independent new A/D rebuild is claimed. I/O/constraint caveats remain in TIMING.md and the manifest.
- Ten compared Common Parser/Reader/Scheduler files are byte-identical A/B/D. Engine bindings and D's pinned Transport owner variant remain separate. Canonical runtime filenames and embedded PWA identity match retained host payloads.
- Package tests freshly extracted all members, checked payload hashes/modes and checksum coverage, verified SID source/licenses, and rejected corruption, incomplete checksum coverage, wrong payload mode and missing payload. Two isolated assembly runs produced identical ZIP bytes.
- Isolated temporary-filesystem upgrade from v2.3, idempotent reinstallation and rollback passed; user music/playlists/remote/startup were preserved. ARM executables and services were not run. This is not a MiSTer installation test. Installer algorithm bytes are unchanged apart from v2.4 backup/staging namespace identifiers.
- All twelve protected repository HEAD/status/diffs and seventeen protected file hashes were checked unchanged. The integrated repository and five explicitly requested canonical documents are the only published modifications.

Saved functional regression evidence is reused, not relabelled as newly run: A2 includes L0/L12 audio equivalence, Maximum Power #111 frame15, Reader/Scheduler/SegaPCM/boundary/horizon/Avalon checks; B/D and original admission records retain their existing named scope. No functional RTL/source-graph settings were changed, so no Quartus or heavy audio rerun was required by this metadata assembly.

C's original producing Windows build is not recovered. Its unchanged legacy source closure is archived without inventing a new root-QPF project. Long-duration/all-track/full production admission and additional hardware DDR measurements remain unrun. v2.3 and accepted original RBFs are protected.

Current entry points:

- `python3 tools/verify_v240.py`
- `python3 tools/verify_artifact_identity.py /path/to/MegaVGMPlayer-v2.4.0.zip`
- `python3 tools/test_v240_package.py /path/to/MegaVGMPlayer-v2.4.0.zip --base-v23 /path/to/MegaVGMPlayer-v2.3.zip`

Final commit-bound ZIP identity and final fresh-extract checks are recorded separately in final-package.json after committing the integration inputs.
