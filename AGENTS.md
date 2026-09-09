# AGENTS.md

## Product and repository

The user-facing product is **MegaVGMPlayer v2.0**, an FPGA music player for MiSTer.

**MegaVGMDrive** is the underlying repository and FPGA/core development project. User-facing documentation and normal operating instructions should lead with MegaVGMPlayer rather than presenting the internal sound-engine builds as separate products.

Normal operation uses the Remote/PWA Player. The user does not manually select an A/B RBF:

1. MiSTer remains in STOCK mode after boot.
2. A Remote Player request enters MegaVGMPlayer through the production Supervisor route.
3. The Phase2A host classifier and controller select the required FPGA sound engine.
4. The Supervisor switches engines when necessary while preserving playlist ownership.
5. Playlist completion or Exit restores stock MiSTer automatically.

## Production layout

The production RBF paths are:

```text
/media/fat/_Custom Cores/Cores/MegaVGMPlayer_Transport13FadeOnly_A_MiSTer.rbf
/media/fat/_Custom Cores/Cores/MegaVGMPlayer_Transport13FadeOnly_B_MiSTer.rbf
```

The standard VGM library root remains:

```text
/media/fat/MegaVGMDrive/
```

Runtime components belong under:

```text
/media/fat/MegaVGMPlayer/
```

Remote and importer scripts belong under:

```text
/media/fat/Scripts/
```

Do not use `_Utility`, `_custom_core`, or `_Custom Cores` without its `Cores` subdirectory as a production A/B RBF load path. References to an old path are permitted only in explicit migration, rollback, or cleanup documentation.

Production Phase2A must not depend on `/tmp/megavgm_supervisor-test/profile`. Test profiles are optional lab overrides, not a production prerequisite.

## Canonical development workflow

- The macOS repository and its QPF/QSF files are the canonical source.
- Do not maintain a separately edited Windows QSF.
- Quartus Full Compilation is performed on Windows; do not attempt macOS Quartus builds.
- Windows is the compilation and hardware-validation side, not an independent source tree.
- A release RBF must resolve the intended canonical sources, come from the documented Windows build, and be validated on real MiSTer hardware.
- Do not call a simulation-only, host-only, compiled-but-untested, or otherwise hardware-unverified result `PASS`.

Use a dedicated branch, worktree, and versioned project for risky or staged work. Do not overwrite a production/PASS QPF, QSF, RBF, or known-good runtime artifact while developing a replacement.

## MegaVGMPlayer v2.0 transport freeze

The v2.0 Player and transport behavior are production-frozen. Do not casually modify:

- Playlist snapshot and queue semantics
- Previous, Next, and Stop behavior
- Repeat One and Repeat Context
- Shuffle and automatic next
- the common fade owner and established fade timing
- the `FADE_ONLY` ABI
- index-1 and index-2 semantics
- Phase2A classification and switching
- switch-generation ownership and session rebase
- controller ownership and auto-next suppression during a switch
- restoration to STOCK after completion or Exit

Any requested change in these areas needs an explicit regression plan, comparison with the production lineage, and real-hardware validation. Documentation-only or UI-only work must not silently change transport behavior.

## Common transport ABI

The common transport contract is shared by the production sound engines. A new engine must adapt to this contract rather than invent a profile-specific transport.

### Index 1: VGM load

- index-1 carries the actual VGM download.
- A load rejected before acceptance does not increment the session.
- An accepted index-1 load begins a new session exactly once and publishes the established loading lifecycle.
- Validation, initialization, or profile-start failure after acceptance keeps that new session and publishes it as `FATAL`; the session is not rolled back.
- Repeated accepted loads produce monotonically advancing sessions within one resident RBF instance.

### Index 2: policy and transition

Index-2 is isolated from the VGM download/reset path and never increments the session.

Existing policy payloads remain backward compatible:

```text
4D 56 02 00
4D 56 02 01
```

Do not reinterpret their established policy meanings.

`FADE_ONLY` is encoded as:

```text
4D 56 02 02
```

When accepted during `PLAYING`, `FADE_ONLY` follows the existing single 100 ms fade owner, reaches gain zero, and publishes `ENDED` exactly once in the same session. Old-session output remains silent until a subsequent accepted index-1 load.

Index-2 must never:

- be parsed or downloaded as VGM data;
- reset the VGM player through the index-1 path;
- increment or replace the session;
- re-arm old-session transition gain;
- emit old-session audio after `FADE_ONLY` has completed.

Duplicate `FADE_ONLY`, Natural EOF, Stop, and FATAL races must preserve the established single-owner and exactly-once completion rules.

## Phase2A switching contract

The host classifier determines the required profile. The Supervisor owns RBF switching, while the controller owns the playlist snapshot, selected index, shuffle history, and command sequencing.

For a same-profile transition, keep the resident RBF and do not reload it.

For a different-profile transition:

- reserve the selected next index exactly once;
- park normal controller auto-next ownership;
- send `FADE_ONLY` to the current session and wait for its authoritative `ENDED`;
- stop the old controller/Main lifecycle through the Supervisor contract;
- switch to the required production RBF;
- verify the modified Main successor and obtain a fresh RBF status baseline;
- rebind the same playlist snapshot and reserved index;
- transfer policy through index-2 and the selected VGM through index-1 exactly once;
- accept the new session using switch generation, profile, successor identity, and fresh status rather than comparing its number globally with the old RBF session.

An RBF switch can reset the FPGA session counter. A new session value smaller than the previous RBF's value is valid when it belongs to the new authoritative switch generation.

Do not alter routing decisions based on a UI sound-chip label. Sound-chip labels are informational metadata; Phase2A routing uses its classifier contract.

## Production and lab separation

Production consists of the Phase2A automatic route and the release-matched Supervisor, controller, modified Main, Remote, importer, and A/B RBF artifacts.

Lab-only facilities include:

- `fade-only-a` and `fade-only-b` test profiles;
- `ym2610b-phase1b`;
- debug overlays and diagnostic QPF/QSF projects;
- UART or debug builds;
- source-disable, stub, and other isolation experiments.

Keep lab profiles available when required for diagnosis, but never make a lab profile file, lab RBF path, diagnostic macro, or test artifact a hidden production dependency. Starting or changing a lab test profile while a production session owns playback must follow the existing Supervisor safety rules.

## Supported sound families

Current production sound families include:

- YM2612
- YM2151
- YM2203
- SegaPCM
- YM2610
- YM2610B

Supporting PSG/SSG and ADPCM paths remain part of the appropriate engine implementation. Do not list Mega CD / RF5C164 or 32X PWM as implemented in v2.0.

The UI sound-chip field is informational and may use importer metadata such as `.megavgm-sound-chip`. Display metadata must not change profile classification, command validation, RBF selection, or playback sequencing.

## Adding a sound engine

Future engines C, D, and later should proceed in stages:

1. Bring up and validate the sound-chip implementation without disturbing existing engines.
2. Adapt the engine to the common MegaVGMPlayer transport ABI.
3. Add host-classifier support without weakening existing classification.
4. Register the engine in the profile table and Supervisor routing.
5. Preserve the same playlist, transition, session-rebase, and STOCK-restoration semantics.
6. Run simulation and host integration tests, Windows Full Compilation, and real-hardware validation.

Do not redesign the Remote Player or expose an engine-selection workflow for each new engine. A/B and later profile letters are implementation details, not user-facing editions.

## Testing and regression expectations

Before reporting completion, run the tests relevant to the touched layer and state exactly what was and was not run.

Transport or switching changes require coverage proportional to their risk, including where applicable:

- cold first load and repeated warm loads;
- same-profile and cross-profile transitions;
- automatic next, manual Next, Stop, Repeat One, Repeat Context, and Shuffle;
- short-track and rapid-command races;
- exactly-once ENDED, load, reset, and session behavior;
- stale-generation suppression and session rebase;
- permanent-mute and stale-audio prevention;
- playlist completion and Exit restoration to STOCK;
- existing production sound-title regressions on real hardware.

Do not replace proof of event ordering or ownership with a longer timeout, fixed delay, or inferred UI timing.

## Artifact and deployment safety

Never infer that a file is production merely from its filename. Establish exact source commit, build provenance, SHA-256, and hardware-validation history.

For runtime deployment:

1. enter STOCK when required by the component lifecycle;
2. upload the candidate under a `.new` or otherwise distinct staging name;
3. verify its SHA-256 before replacement;
4. preserve the existing artifact as a timestamped or clearly named backup;
5. replace atomically where the filesystem and script permit;
6. verify the runtime executable identity and SHA;
7. verify HTTP routes/status for Remote changes and authoritative status for playback changes;
8. retain a tested rollback path.

Do not overwrite known-good rescue artifacts. Do not delete legacy RBFs or user data as incidental cleanup. Preserve unrelated changes in dirty worktrees.

## Release discipline

- Avoid unrelated cleanup during release and hotfix work.
- Preserve production-PASS artifacts and do not rebuild RBFs without a concrete need.
- Keep release components on an explicitly documented compatible lineage.
- Do not change source while asked only to package existing exact commits.
- Do not alter release assets, tags, or published artifacts unless the user explicitly requests it.
- Report hardware-unverified items as unverified, never as `PASS`.

## Reporting expectations

Report the outcome first, followed by:

1. exact changed files and commits;
2. the contract or behavior affected;
3. tests and static audits run;
4. artifact paths and SHA-256 values when artifacts are produced;
5. Windows compilation and real-hardware status when relevant;
6. remaining risks, missing evidence, or rollback instructions.

Keep patches small, reviewable, and scoped to the request. Preserve known-good production behavior unless the task explicitly authorizes changing it.
