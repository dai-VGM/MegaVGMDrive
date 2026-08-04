# AGENTS.md — Repository Instructions

These instructions apply to the entire repository. They are normative. A more
specific instruction from the user MAY narrow a task, but it MUST NOT silently
weaken the Golden Player Shell contract or a protected-file rule.

## 1. Project Identity

- The repository and FPGA core project name is MegaVGMDrive.
- The on-screen standalone player name is MegaVGMPlayer.
- Exact capitalization MUST be preserved. Names such as “Mega VGM Player” MUST
  NOT be presented as official names.
- Sound-profile RBFs MAY be separated by sound device.
- The Golden Player Shell is the common MiSTer-facing shell for every profile.
- The authoritative working directory is
  /Users/daizo/Projects/mister-vgm-golden.
- /Users/daizo/Projects/mister-vgm-work and
  /Users/daizo/Downloads/NanoDrive6-2.3.0 are historical references only and
  MUST NOT be modified.

## 2. Authoritative Development Environment

- The Mac repository is authoritative.
- RTL, QSF, QIP, scripts, tests, and documentation MUST be edited in the Mac
  repository.
- QSF and QIP files MUST NOT be edited on Windows.
- The complete Mac repository and project files MUST be synchronized to
  Windows before a Quartus build.
- Windows MUST be used only for Quartus Full Compilation and MiSTer hardware
  validation.
- Codex MUST NOT run Quartus on macOS.
- Codex MUST NOT search for a macOS Quartus installation or probe its path.
- After synchronization and before a clean Windows compile, delete the
  project-local db, incremental_db, and output_files directories.
- A Mac-side static source-graph audit MAY validate relative paths, file
  existence, and assignments. It MUST NOT be reported as a Quartus build.

## 3. Golden Player Shell

This is the highest-priority repository contract.

Golden Player Shell Stage A was hardware-validated on MiSTer and is immutable.

- Hardware-PASS baseline:
  35d99c23852a1290257021176e1fe5bc61446726
- Authoritative production source baseline:
  MegaVGMPlayer v1.0.1 at
  5ecce555edb80bdcb010a322ee46ba8837a6ee27
- Stage A project:
  MegaVGMPlayer_YM2610_GoldenShell_MiSTer
- Contract references:
  - docs/golden_player_shell/stable_source_manifest.json
  - docs/golden_player_shell/IMMUTABLE_CONTRACT.md
  - docs/golden_player_shell/STAGE_ROADMAP.md

The following Golden Shell areas are IMMUTABLE:

- production emu and the MiSTer shell
- video timing, scaler, sync, and Direct Video wiring
- OSD and Menu/Return behavior
- the physical Load VGM path
- title receiver, renderer, font, and surface
- PLL and the shell reset contract
- device, pin, voltage, and SDC assignments
- physical DDR upload backend and handshake
- upload FIFO and partial-word flush
- shell audio output format and AUDIO_L/R shell connection
- MiSTer system modules
- Stage A QPF, QSF, and QIP
- Golden Shell compatibility shim and Stage A inert adapter
- Golden Shell tests and immutable manifest

Golden Shell files MUST NOT be modified for sound-profile work. They MUST NOT
be copied, forked, or replaced by a similar implementation. Every profile MUST
directly reuse the hardware-validated source, blob, project, and adapter
contract.

A profile MUST NOT add its own emu, video timing, scaler, PLL, OSD, title
renderer, physical upload backend, or shell reset tree. A profile bug MUST NOT
be fixed by editing the shell. A Golden Shell blob or QSF audit failure is an
immediate stop condition.

The Stage A hardware result is verified as follows:

- production-equivalent video operated normally
- OSD and Menu operated
- VGM upload operated
- prepared title display operated
- software Reset and reload operated
- playback remained disabled and audio remained zero
- no freeze or video signal loss occurred
- no power cycle was required

## 4. Profile Development Boundary

PROFILE-MUTABLE work is limited to these four categories:

1. Parser adapter
   - VGM opcode decode
   - waits
   - loop and end behavior
   - register-write scheduling
2. Sound adapter
   - sound-chip wrapper
   - header-derived clock
   - reset and BUSY contract
   - audio L/R
   - chip-local sample-valid
3. Logical PCM/DDR adapter
   - VGM data-block classification
   - descriptor construction
   - logical ROM address mapping
   - profile-local read client or cache
   - PCM request/response adaptation
4. Profile-local diagnostics, tests, and documentation
   - profile state, counters, and debug values
   - synthetic fixtures and reference scanners
   - profile-specific documentation

Physical DDR upload and handshake MUST remain in the Golden Shell. Profile code
MAY request logical reads only through the fixed shell/profile adapter
contract. It MUST NOT reimplement MiSTer physical DDR signaling.

Profile code MUST NOT instantiate a second shell, video system, or upload path.
It MUST NOT depend on hierarchical synthesis references into sound cores.
Cross-module status and control MUST use explicit, synthesizable ports and
adapters.

## 5. Mandatory Stage-Gated Workflow

Every new sound profile MUST proceed in this order:

### Stage A — Golden Shell Baseline

- stable shell, OSD, title, and physical upload only
- no scanner, parser, sound device, or DDR read
- audio zero
- MiSTer hardware validation required

### Stage B — Full-File Scan Only

- header validation and compatibility classification
- data-block descriptors
- one scanner DDR-read client
- no playback parser or sound device
- audio zero
- MiSTer hardware validation required

### Stage C — Parser and Non-PCM Sound

- parser, waits, end, and loop control
- FM, PSG, or other non-PCM device
- PCM DDR reads disabled
- MiSTer hardware validation required

### Stage D — First PCM Client

- exactly one PCM logical-ROM/read client
- no second PCM client
- MiSTer hardware validation required

### Stage E — Additional PCM Client

- second or additional PCM client
- simultaneous arbitration MUST NOT yet be assumed
- MiSTer hardware validation required

### Stage F — Full Integration

- simultaneous clients
- loop, reload, cold start, and software Reset
- title, raw, and prepared-file compatibility
- all previously completed devices enabled
- complete regression and MiSTer hardware validation

A later stage MUST NOT begin before the previous stage passes MiSTer hardware
validation. Each stage SHOULD have a separate branch, project, commit, RBF, and
hardware result. An all-in-one implementation MUST NOT replace the staged
workflow. Simulation PASS MUST NOT be treated as hardware PASS.

A failure MUST be diagnosed within the boundary newly added by that stage.
Stage A MUST be inherited and MUST NOT be rebuilt.

## 6. Golden Shell Change Procedure

A Golden Shell change is legal only through this procedure:

1. Create a dedicated, versioned shell-development branch and project.
2. Preserve the current hardware-PASS shell unchanged.
3. Keep the shell change separate from all sound-profile work.
4. Run Stage A hardware validation.
5. Run every existing profile’s shell regression.
6. Validate video, OSD, title, upload, reset, Menu, and shell audio on MiSTer.
7. Obtain explicit hardware approval before promotion.
8. Create a new versioned manifest and tag.
9. Keep existing profiles pinned to the old shell until each is deliberately
   migrated.

A shell change MUST NOT be introduced incidentally while implementing a sound
device.

## 7. Lab Versus Production Logic

- Existing completed sound devices MAY be disabled or stubbed in a dedicated
  new-chip bring-up profile to reduce build time.
- Lab-only disable or stub macros MUST be clearly separated from production
  feature-enable logic.
- A macro whose name implies diagnostic-only behavior MUST NOT hide required
  production logic.
- Lab macros MUST NOT silently change a production build.
- Debug builds MUST be clearly identifiable and MUST NOT be released as
  production.
- Before reintegration, every previously completed device MUST be re-enabled.
- Reintegration MUST verify:
  - parser opcodes
  - raw audio
  - final audio routing and gain
  - sample-valid cadence
  - load and reload
  - reset
  - raw and prepared VGM title compatibility
  - the actual top-level build
  - loop behavior
  - X/Z, clipping, drops, underflow, and stale responses

## 8. Regression and Hardware Validation

Every functional stage MUST include:

- an independent reference where practical
- deterministic repeated simulation
- Icarus compile and elaboration
- Verilator lint and elaboration
- undefined modules = 0
- duplicate modules = 0
- latches = 0
- multiple drivers = 0
- combinational loops = 0
- relevant X/Z = 0
- git diff --check
- QSF/QIP source-graph audit
- forbidden-source audit
- Golden Shell immutable-blob audit
- production-blob audit
- protected-file audit

External-memory logic MUST satisfy all of these contracts:

- request, address, owner, and tag remain stable until acceptance
- responses use captured transaction metadata
- stale generations are rejected
- reset and reload flush outstanding state by an explicit contract
- request drops, response drops, and duplicate responses = 0
- underflow and owner mismatch = 0
- scan or read begins only after the upload-completion fence
- live addresses MUST NOT be used to route responses

The following stable production behavior is regression-sensitive and MUST NOT
be altered casually:

- parser PC, wait, loop, and 0x66 behavior
- 23-bit DDR loader/backend and exact 8 MiB physical-size contract
- audio sample-valid cadence
- JT12, JT89, JT51, and JT49 internal RTL
- SegaPCM normal-DDR adapter, prefetch, cache, hold, ownership, reset, and
  .reset(reset) connection
- production audio gain, routing, saturation, and selector behavior
- native video timing
- MVGMTTL validation and atomic title publication
- ordinary unmodified VGM playback

VGM header loops are intentionally followed indefinitely by the FPGA player.
Finite loop counts, fades, playlists, and next-track policy belong to a future
host or Web player and MUST NOT be inserted into profile RTL incidentally.

Quartus compilation alone is not hardware validation. MiSTer results MUST
explicitly cover video, OSD, Menu, Reset, load, reload, and any power-cycle
requirement. The previous stage’s behavior MUST remain unchanged. Work MUST
stop when the user reports unexplained freezes, signal loss, or global MiSTer
instability.

## 9. Protected Files and Diagnostics

- tb/tb_jt49_audio_compare.sv is the Sacred TB and MUST NOT be modified unless
  the user explicitly revokes its protection.
- Existing untracked diagnostics MUST NOT be deleted, renamed, reformatted, or
  committed.
- When protection is in scope, before/after SHA-256, size, mtime, and inode
  checks MUST be recorded.
- Existing diagnostic artifacts MAY be preserved in an explicitly identified
  stash. Such a stash MUST NOT be applied, dropped, or rewritten without
  authorization.
- Generated logs, WAV files, raw dumps, VCD/FST files, Quartus output, db,
  incremental_db, and output_files MUST NOT be committed.
- Debug overlays MUST fit within 29 visible rows.
- Diagnostic fields MUST be selected before implementation so every required
  value fits within that limit.
- SignalTap MUST NOT be added unless explicitly requested.
- Stable release artifacts and production RBFs MUST NOT be replaced without
  explicit authorization and hardware validation.

## 10. Build and Windows Handoff

After a Quartus project change, the final report MUST state:

- branch
- base HEAD, final HEAD, and commit hash
- changed files
- QPF path and revision name
- expected output_files/<revision>.rbf path
- db, incremental_db, and output_files as the directories to delete
- Windows synchronization and Full Compilation procedure
- exact MiSTer hardware test and expected behavior
- actual compile and hardware result, or an explicit statement that each
  remains pending

The standard Windows handoff is:

1. Synchronize the complete authoritative Mac working tree.
2. Open the reported QPF without editing QSF or QIP.
3. Delete project-local db, incremental_db, and output_files.
4. Run Processing > Start Compilation as a Full Compilation.
5. Copy only the reported RBF to the intended test location.
6. Perform and report the exact MiSTer test for the current stage.

Codex MUST NOT claim that Quartus compiled or that hardware passed unless that
specific Windows build and MiSTer test actually occurred. If Quartus was not
run on Mac, the report MUST say so; macOS Quartus is prohibited by Section 2.

## 11. Naming and Supported Features

MegaVGMDrive is the repository/core project. MegaVGMPlayer is the on-screen
standalone player.

Only hardware-validated production builds may define the production feature
list. The stable production baseline includes:

- YM2612 through Jotego JT12
- SN76489/PSG through Jotego JT89
- YM2151 through Jotego JT51
- YM2203 through JT12 OPN FM and JT49 SSG
- SegaPCM through Jotego JTOUTRUN/jtoutrun_pcm
- OSD-loaded raw VGM playback
- the 23-bit DDR VGM backend and files up to exactly 8 MiB physical size
- optional 128-byte MVGMTTL metadata trailer support
- parent-directory and basename title display
- MiSTer Template-compliant 15 kHz native video
- HDMI, Analog RGB, YPbPr, CRT, and Direct Video output

Mega CD is not currently supported. RF5C164 MUST NOT be listed as implemented.
32X is not currently supported. 32X PWM MUST NOT be listed as implemented.
YM2610 and YM2610B development branches MUST NOT be presented as production
support before their complete profile receives hardware validation.

A planned feature, test branch, simulation, or source presence MUST NOT be
reported as implemented production functionality.

Vendor-source provenance and licenses MUST be preserved. The complete JT12
tree MUST NOT be updated opportunistically. JT10/ADPCM dependencies used for
the YM2610 family MUST remain explicitly pinned to sources compatible with the
existing JT12 generation at commit
6d51e0b6f64728c73408079b2f5ffe911bfd88a9 unless a separately scoped,
validated migration is authorized.

## 12. Stop Conditions

Work MUST stop without a commit if:

- a Golden Shell immutable file would need to change
- stable emu, video, OSD, title, upload, or reset logic would need to be copied
  or forked
- the previous stage has not passed MiSTer hardware validation
- production source would need to change for profile-local work
- the physical DDR shell contract would need to be reimplemented
- the current branch or HEAD differs from the requested baseline
- the tracked or staged tree is unexpectedly dirty
- protected diagnostics or Sacred files changed
- simulation and its reference disagree
- an audio hash changes outside the explicit task scope
- any duplicate, drop, stale-response, underflow, or owner mismatch remains
- relevant X/Z remains
- any latch, multiple driver, or combinational loop remains
- QSF or QIP contains an absolute or test-only source path
- completion would require Quartus on Mac
- the user reports a global freeze or video signal loss and the failure
  boundary is not isolated

The stop report MUST identify the exact blocker, affected boundary, evidence,
and smallest safe next step. It MUST NOT substitute a speculative fix.

## 13. Commit Discipline

- main is the stable production branch. Feature branches MUST start from main
  unless the user or a stage contract names a different baseline.
- One scoped stage or governance change MUST be committed at a time.
- Shell, profile, diagnostics, and release changes MUST NOT be mixed.
- A commit MUST be created only after all required checks pass.
- The tracked and staged tree MUST be clean after the commit.
- Build output and copyrighted VGM or payload data MUST NOT be committed.
- Public tags and releases MUST NOT be rewritten unless explicitly requested.
- main MUST NOT be merged or rewritten, and GitHub Releases MUST NOT be
  modified, unless explicitly requested.
- Commits MUST NOT be pushed unless explicitly requested.
- A documentation-only task MUST NOT trigger unrelated RTL edits.
- Commit messages MUST describe the actual bounded change.
- Before completion, record the branch, base HEAD, final HEAD, working-tree
  state, changed files, and protected untracked files.
