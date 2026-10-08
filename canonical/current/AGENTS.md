# Projects Canonical Governance

Updated: 2026-10-09. Normative governance for `/Users/daizo/Projects`.

## Scope and precedence

Read this file before repository-local instructions. Precedence is explicit user authority, this governance, the Platform/Engine Contracts in their respective domains, then the Bring-up Runbook. START_HERE is an index. Local `AGENTS.md` may add narrower or stricter constraints; it cannot replace or relax canonical policy. Stop and report an unresolved conflict before changing files. Do not extend an explicit exception to unrelated local instructions or future differences.

Normative requirements and observed implementations are distinct. A current worktree HEAD, a historical snapshot, a directory name or a PASS marker alone is not production authority.

## MegaVGMPlayer engine work bootstrap

For engine bring-up, modification, debugging, integration, production work or RBF switching/upload investigation, read **in full, in this order**, before source changes:

1. `/Users/daizo/Projects/AGENTS.md`
2. `/Users/daizo/Projects/MegaVGMPlayer_Platform_Contract.md`
3. `/Users/daizo/Projects/MegaVGMPlayer_Engine_Contract.md`
4. `/Users/daizo/Projects/MegaVGMPlayer_Engine_Bringup_Runbook.md`

Recognize terse prompts such as `Engine EでNESやる` and `次の音源やるぞ` automatically. Do not ask DAI to repeat the reading instruction or document list. If a required document is missing/unreadable or a conflict remains, stop and report it.

After reading, verify the applicable worktree, branch/HEAD, dirty/untracked state, actual source graph and frozen/protected boundaries. Establish engine scope and missing chip specifications, then form an implementation/validation plan. The common procedure must be reconstructible from these documents and actual source, without prior chat or DAI's memory. New task input supplies engine-specific facts and explicit decisions; it does not substitute for inspecting available evidence.

[START_HERE](MegaVGMPlayer_START_HERE.md) provides the human index. The [Engine Contract](MegaVGMPlayer_Engine_Contract.md#1-vnext-engine-plugin-architecture) owns vNext architecture; the [Runbook](MegaVGMPlayer_Engine_Bringup_Runbook.md#new-engine-plugin-workflow) supplies its implementation procedure.

## Golden Shell contract

Reuse the hardware-PASS Golden Shell. Frozen shared infrastructure includes video/raster/scaler/OSD, physical upload and DDR write/packing/drain/fence, `hps_io`/ioctl lifecycle, PLL/reset/Main-HPS plumbing, shared Transport, audio framing and proven shell diagnostics. New engines attach through the Engine Contract; they do not create independent video, upload, DDR writer, reset, status or Transport paths.

Common Parser, Strict Reader and Scheduler are reusable vNext infrastructure. Their semantics are not engine-local customization points. A missing supported grammar may receive an explicitly reviewed generic extension; do not fork a chip-specific parser or move execution/storage/policy into it. Engine-local work covers thin adapters, chip state/Core, Preflight when needed, sample/resource clients, output adaptation and required Activity metadata.

Changing frozen infrastructure requires explicit scope, an isolated candidate, comparison with the accepted lineage and renewed tests/build/hardware acceptance for the touched layer. A historical lab must not become a hidden dependency. Required UI and fault/status behavior cannot be removed as debug optimization; see the Engine Contract.

## Golden Player Platform contract

The [Platform Contract](MegaVGMPlayer_Platform_Contract.md) owns Player/PWA/Remote, Supervisor switching, Controller command ownership, navigation, user loop preferences and timing presentation. Ordinary engine work does not change those semantics or add an engine-name behavior branch, including in Main.

A genuine Platform revision must identify the insufficient clause, explain why Engine-side compliance cannot satisfy it, receive explicit scope and define Platform regression/hardware re-acceptance. Finite profile IDs, classifier/metadata vocabularies, registry and package inventories may need separately scoped data/schema integration; this is not permission to change generic state machines or UI policy.

## Source and build authority

macOS owns committed source and the exact QPF/QSF/QIP/Tcl graph. Windows performs the authorized Quartus build of an immutable **Reproducible Build Artifact**. Do not run Quartus on macOS or maintain a Windows-only source/configuration authority.

The [v2.4.0 Architecture Refresh RC](MegaVGMPlayer_vNext_Integrated_RC/README.md) and [adoption manifest](MegaVGMPlayer_vNext_Integrated_RC/release/v2.4.0/adoption-manifest.json) select A A1+A2, B seed3 optimization, unchanged stable C and D vNext with exact RBF/source/build evidence and scoped DAI hardware confirmation. The older [A/B candidate ledger](MegaVGMPlayer_CURRENT/VNEXT_HARDWARE_ACCEPTED.md) remains historical. v2.3 production/release authority is preserved; RC selection is not deployment or public release promotion.

Before a build, consult [BUILD_TARGETS](MegaVGMPlayer_CURRENT/BUILD_TARGETS.md) for existing production targets. An explicitly selected vNext candidate has its own graph and evidence; it does not replace the registered v2.3 production artifact automatically. Preserve canonical deployed naming `MegaVGMDrive_<engine>.rbf` and CORENAME `MegaVGMDrive`; candidate project names must remain distinct.

Every Engine A/B/C/D/E and future F/G/NES/PCE Pre-Quartus READY requires the Runbook's [Quartus Compatibility Gate](MegaVGMPlayer_Engine_Bringup_Runbook.md#quartus-compatibility-gate) and [Human-facing Build Artifact Contract](MegaVGMPlayer_Engine_Bringup_Runbook.md#human-facing-build-artifact-contract). The ZIP extraction root is the build root: sole canonical QPF/QSF, HANDOFF/checksums, `source/` inputs and `output/` results. The canonical Windows workflow is extract ZIP → open the root QPF in Quartus GUI → Full Compilation → inspect `output/`. `BUILD.bat` is optional, excluded from READY/PASS conditions; a helper failure is not a canonical QPF build failure. Canonical configuration is copied byte-for-byte; generators must not reinterpret and reserialize Tcl. Read-only graph evaluation is required. Test corpora/evidence are not build inputs unless the exact graph requires them.

The correction flow is Windows log → Mac fix → validation → commit → fresh validated Artifact. Windows-only patches and adopting their RBF are prohibited. READY is source/artifact readiness, not build authorization, fit, hardware PASS or promotion.

## Production Engine Admission Gate

Standalone audio Hardware PASS is not production Engine PASS. The [Engine Contract](MegaVGMPlayer_Engine_Contract.md#6-production-engine-admission) owns the full gate, including status/ioctl/Transport, deterministic lifecycle, all-channel Activity, transparent bottom Loading, exact artifact identity and generic Player transitions.

Static admission must inspect the actual graph, instantiated exporter/readback, required macros, CORENAME and canonical deployed RBF identity. Fresh pre-upload `version=2/session=0/IDLE/error=00` must be available independently of upload completion. Current-session ENDED/FATAL and playback loop facts must be wired. A textual registration or display change is insufficient. Keep simulation, Windows build and hardware evidence separate.

## Evidence vocabulary

- **REQUIRED**: normative acceptance condition; not a claim of implementation or PASS.
- **PROVEN — source/static**, **PROVEN — simulation**, **PROVEN — Windows build**, **PROVEN — hardware**: name the evidence type, exact scope and identity. These are not interchangeable.
- **TBD / NOT_RUN / FAIL_REOPENED**: unresolved, unperformed or failed/reopened gate. Do not infer PASS from adjacent audio or simulation evidence.

Record worktree/branch/HEAD and relevant dirty hashes, QPF/revision/tool version, Artifact/RBF full SHA256 and byte size, tested scope and user confirmation when applicable. A later source HEAD does not inherit an older RBF's hardware claim. Scope reductions such as representative checkpoints must be explicit; do not label them full traversal. Newly discovered differences need fixed evidence and review, not automatic allowlists. Required simulation deadline-fault negatives are not unexplained playback failures.

## Protected work

Preserve accepted production/release worktrees and graphs, Runtime/RC/Main/PWA, RBFs/hardware-PASS binaries, packages, tags, release assets and deployment paths. Editing/building/copying/deploying/publishing protected material requires explicit authority for that action. Ordinary engine work is isolated; never use a release tree as scratch. Preserve unrelated dirty/untracked files and Git history.

## Worktree hygiene

Derive the active closure from the exact current Build Artifact, then add current regression/tool/canonical-document dependencies. Classify by actual references and ownership, not names:

| Class | Required evidence/action |
|---|---|
| KEEP_ACTIVE | selected build input or current tooling/test/fixture/document/release authority |
| KEEP_REFERENCE | currently used semantic oracle, historical bug test, pinned provenance or license |
| ARCHIVE_SAFE | unreachable from all current closures; superseded/generated material with proven recovery |
| UNKNOWN | unresolved use/ownership/license/symlink/worktree/submodule; retain and stop removal |

Do not duplicate obsolete experiments in the active tree merely because they once worked. Preserve required vendor/license subsets and accepted artifacts. Generated reports/RBF/WAV/logs/traces belong in policy-managed output or archive, not accidental live inputs. First create an external local quarantine with original/archive paths, size, SHA256, tracked state, reason and restoration method; verify hashes before removal. Do not silently upload archives to cloud.

Tracked removals require a scoped cleanup commit after fresh generation/extraction, exact functional input/graph comparison and current-tier regressions. No blanket clean/reset/prune, Git-history destruction, unreviewed worktree retirement or removal of user diagnostics. A cleanup instruction does not authorize semantic changes. Detailed procedure: [Runbook hygiene](MegaVGMPlayer_Engine_Bringup_Runbook.md#worktree-hygiene-and-recovery).

## Working discipline

Prefer small, reviewable changes within explicit scope. Before implementation, establish chip authority and tests. Apply the Runbook's tiered regression, measured resource sizing and compatibility procedure; a behavioral model alone does not prove feasible FPGA implementation. Run appropriate checks and `git diff --check`; shared Markdown outside Git also receives before/after no-index whitespace validation. Report changes, exact validation scope, unrun gates and remaining TBD without upgrading evidence.
