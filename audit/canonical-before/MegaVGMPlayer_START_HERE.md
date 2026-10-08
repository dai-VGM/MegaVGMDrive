# MegaVGMPlayer — START HERE

Updated: 2026-10-08. Human index for the vNext canonical specification. This index does not override governance or either Contract.

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

- A/B vNext: **hardware-accepted candidates**, exact SHA256/size and scoped DAI confirmation registered in the [candidate ledger](MegaVGMPlayer_CURRENT/VNEXT_HARDWARE_ACCEPTED.md). Audio, all-channel Activity, transparent bottom Loading, PWA automatic switching/playback and existing Controller/Supervisor compatibility are confirmed for those two RBFs.
- Exact producing source/build binding remains **TBD**; latest source Artifact commits are candidate provenance only. Long-duration tests and full production admission are **NOT_RUN / not claimed**.
- Older B Loading FAIL_REOPENED/A Activity-excluded trim records remain historical. They do not describe the newly accepted RBFs or acquire a retroactive PASS.
- Accepted v2.3 A/B/C/D release identity remains in [BUILD_TARGETS](MegaVGMPlayer_CURRENT/BUILD_TARGETS.md) and the release registry, unchanged.

Pre-Quartus READY requires a validated [Reproducible Build Artifact](MegaVGMPlayer_Engine_Bringup_Runbook.md#human-facing-build-artifact-contract): extract ZIP → open the root canonical QPF in Quartus GUI → Full Compilation → inspect `output/`. `BUILD.bat` is an optional helper, excluded from READY/PASS; its failure does not establish a canonical QPF build failure. No QPF hunting, Windows source patches or Mac Quartus. A READY marker does not authorize the build or establish hardware PASS.

The common procedure is reconstructible from these documents and actual source. Historical snapshots are linked from the Runbook appendix, not current architecture authority.
