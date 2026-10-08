# MegaVGMPlayer — START HERE

Updated: 2026-10-09. Human index for the vNext canonical specification. This index does not override governance or either Contract.

Read in this order, in full before engine source changes:

1. [AGENTS.md](AGENTS.md) — governance, bootstrap, protected boundaries, authority and worktree hygiene.
2. [Platform Contract](MegaVGMPlayer_Platform_Contract.md) — Player/PWA/Remote/Controller/Supervisor policy, user preferences and engine switching.
3. [Engine Contract](MegaVGMPlayer_Engine_Contract.md) — reusable vNext pipeline, plugin interfaces, logical time, resources, reset, UI/status and production admission.
4. [Bring-up Runbook](MegaVGMPlayer_Engine_Bringup_Runbook.md) — implementation steps, tiered tests, resource/Quartus audits, Build Artifact and troubleshooting.

The [automatic bootstrap](AGENTS.md#megavgmplayer-engine-work-bootstrap) applies even to `Engine EでNESやる` / `次の音源やるぞ`; DAI need not repeat the document list. If entering the Runbook directly, read documents 1–3 first. Missing documents or unresolved authority conflicts stop source work. After reading, verify worktree/branch/HEAD/dirty state, actual graph, protected boundaries, engine scope and missing chip facts, then plan.

The vNext engine model is:

```text
Byte/Resource Source → Strict Reader → Common Parser
 → Scheduler / Logical Timebase → Engine Adapter → Sound Core → Output Adapter
                                                        ↕ optional
                                                Storage / Sample Client
```

Sample data uses a side path; it is not decoded by Parser or routed through the audio output adapter as file data. Engines needing admission/resource preparation use Parser PASS1 → Preflight/preparation → PASS/ready → Parser PASS2 → playback. [Engine architecture and ownership](MegaVGMPlayer_Engine_Contract.md#1-vnext-engine-plugin-architecture) are normative.

Start future C/D/E/F/G/NES/PCE work with the [plugin workflow](MegaVGMPlayer_Engine_Bringup_Runbook.md#new-engine-plugin-workflow), not by copying an old chip-specific parser or a complete historical project. Missing grammar is audited and extended explicitly; unknown future chips are not promised adapter-only support. SID/MVGMSID remains a separate prepared-format path.

Current evidence, not automatic production promotion:

- [v2.4.0 Architecture Refresh RC](MegaVGMPlayer_vNext_Integrated_RC/README.md) selects A A1+A2 (`b4e1b9c`), B optimization (`99d4928`, seed3 config `2241e0f`), unchanged C (`82402ec`) and D (`26d5078`). Exact hashes, Build Artifacts, constrained Timing and scoped user hardware receipts are in the [adoption manifest](MegaVGMPlayer_vNext_Integrated_RC/release/v2.4.0/adoption-manifest.json).
- A/B/D reuse Common Reader/Parser/Scheduler and retained Golden/Transport boundaries with engine-specific bindings. C preserves its independent SID native-cycle prepared-format path. Future NES/PCE/GB starts with this plugin model; missing generic opcode support requires explicit review.
- A/B/D all-four-corner constrained Timing passes are recorded. B has two independent matching Full Compilations; A/D do not claim an independent rebuild. C retains its stable v2.3 binary; original producing build is not recovered.
- Long-duration, all-track compatibility and the complete admission matrix are not newly claimed. The previous A Timing failure is preserved and resolved by selecting A1+A2; older UI/registration records remain historical for their exact hashes.
- Existing v2.3 production authority in [BUILD_TARGETS](MegaVGMPlayer_CURRENT/BUILD_TARGETS.md) and the release registry remains unchanged. No deployment/tag/push/publication is implied.

Pre-Quartus READY requires a validated [Reproducible Build Artifact](MegaVGMPlayer_Engine_Bringup_Runbook.md#human-facing-build-artifact-contract): extract ZIP → open the root canonical QPF in Quartus GUI → Full Compilation → inspect `output/`. `BUILD.bat` is an optional helper, excluded from READY/PASS; its failure does not establish a canonical QPF build failure. No QPF hunting, Windows source patches or Mac Quartus. A READY marker does not authorize the build or establish hardware PASS.

The common procedure is reconstructible from these documents and actual source. Historical snapshots are linked from the Runbook appendix, not current architecture authority.
