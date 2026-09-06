# Phase 2A — opt-in host profile switching

Base: `a8344a12eb9a5eb438ef2dc96e0a5326526ec292` (Supervisor FADE_ONLY test profiles).
Branch/worktree: `phase2a-host-profile-switch` / `mister-vgm-phase2a-host-switch`.
This is NOT a production promotion. Main, Remote/frontend, A/B RBFs, audio/fade,
and the wire formats for playlist snapshots / Main commands are unchanged.

## Frozen prerequisites

- Main: `a0e7b7d3557457a80ecd62a6bb4643585c33b78fbe515a7a7a5783b05b5addb5`.
- A: `/media/fat/_Utility/MegaVGMPlayer_Transport13FadeOnly_A_MiSTer.rbf`.
- B: `/media/fat/_Utility/MegaVGMPlayer_Transport13FadeOnly_B_MiSTer.rbf`.
- Hardware prerequisite reported by user: FADE_ONLY `4D 56 02 02`, same-session
  ENDED 100ms after transfer completion on both A/B. This host implementation's
  real switching/audio results still require hardware tests.

## Source-grounded classifier

`profile.cpp` is linked into BOTH test binaries. Cold Supervisor classifies the
selected snapshot entry (or selected/first folder entry) before stopping stock
Main. Controller classifies every reserved selection BEFORE a switch request,
policy write or index-1 load. Canonical realpaths must remain below
`/media/fat/MegaVGMDrive`; regular uncompressed VGM only, max 64MiB.

Evidence: A `rtl/vgm_loaded_player.sv` ST_DECODE/ST_ARG2/ST_BLOCK_TYPE, production
`MD_COMMANDS_ENABLED` and YM2151 build modes; B
`rtl/ym2610_player/ym2610_player_scanner.sv` ST_VALIDATE/ST_COMMAND/ST_BLOCK_TYPE
in the frozen B worktree. The classifier is a *profile requirement classifier*,
not a replacement for each RBF's scanner/register/descriptor/capacity validation.

| Actual command/data usage | Result |
|---|---|
| 4F/50 PSG, 52/53 + 80–8F/E0 YM2612, 54 YM2151, 55 YM2203, C0 SegaPCM; blocks 00/80 | A |
| 58/59 YM2610/YM2610B; blocks 82/83 | B |
| Both A and B sound usage | AMBIGUOUS (no switch/load) |
| No sound usage | AMBIGUOUS (no clock-only guess) |
| Other opcode/block, dual chip, unsupported version | UNSUPPORTED |
| Broken/truncated header/command/block, invalid loop target, absent required clock, unavailable/outside-root file | ERROR |

Version range is 1.10–1.71. Bounds, data offset, full command boundaries through
the first EOF and the loop command boundary are checked. Waits are 61/62/63/70–7F.
Data payloads are skipped by their checked lengths, never searched as opcodes.
For B the explicit data offset is required, matching its scanner. YM2610B's
variant flag is allowed; dual-chip flag is not. Header clocks for *used* lanes
must exist; unused clocks do not invent a second profile. Unknown sound opcodes
that A's RTL happens to skip are NOT classified as supported.

Local corpus audit: 212 `.vgm` files, A=118 / B=94, no exceptions/unknowns needed.
Examples: Space Harrier Credit and After Burner Final Take Off -> A; Night
Striker Coin/Urban Trail/Aquarius, Ninja Warriors Daddy Mulk/Japanese Smile,
Metal Slug Stage 1 and Darius II -> B. This is classification evidence, not an
audio hardware regression claim. VGZ/compressed stream commands are deliberately
not silently accepted.

## Ownership / transaction

```
controller: existing traversal selects/reserves index ONCE
  -> classify -> PARKED (same live queue + shuffle/history)
  -> private latest-generation request
Supervisor:
  same resident -> READY lease (no RBF reload)
  different resident + PLAYING -> FADE_ONLY -> owned-session ENDED
  already ENDED/IDLE -> no redundant fade required
  -> drain all modified Main processes using existing stable-zero contract
  -> keep existing bind, start modified Main, strict SHA verification
  -> load_core required RBF -> verified successor PID/SHA/argv
  -> fresh status v2, session=0, IDLE, error=0
  -> reread latest request BEFORE any READY grant
controller: latest READY lease -> policy index2 -> generated VGM index1 ONCE
  -> Main acknowledgment + expected new session -> PLAYING (or short ENDED)
```

The controller process is *cooperatively parked*, not killed/reconstructed from
the original snapshot. During this phase it does not execute its ordinary
ENDED auto-next branch and emits no Main commands. Thus FADE_ONLY ENDED cannot
issue the old-RBF next load observed in the prerequisite test. Supervisor alone
owns Main lifecycle, retaining the existing bind and verified stock recovery.
No concurrent lifecycle thread, parallel bootstrap or additional fade engine.

The channel is a new root-owned 0700 `/tmp/megavgm-phase2a.XXXXXX` directory for
each ENTER; it is the run epoch. Request/reply files are bounded regular 0600
records, O_NOFOLLOW/CLOEXEC, temp+fsync+rename. It remains as diagnostic evidence
until reboot. An immutable separate FADE_ONLY payload cannot overwrite the
controller's ordinary 0/1 loop-policy payload.

`generation` owns the latest selection. `domain` increments per actual RBF
exchange. READY includes profile, fresh baseline and Main identity
`PID:start_ticks:exe_device:exe_inode`; Supervisor has verified its SHA/argv.
Controller requires matching current lease, live identity, and Main's
`megavgm_load_file.status` witness (`generation_valid=1`, matching generation,
publisher PID, path, index=1, TRANSFER_SUCCESS), plus baseline+1 *within that
domain*. There is no ordering comparison against the old RBF's session.
Old session 57 -> new baseline 0 -> session 1 is explicitly tested.

Main clears/recreates FPGA status on core discovery. Existing `load_rbf` also
removes stale status/CORENAME before the new discovery; old Main is fully drained.
In this test route it also removes the previous Main load-acknowledgment file,
so even PID reuse cannot reuse an old command witness.
Old lease/generation/PID cannot authorize a late status record. The existing
diagnostic load acknowledgment is now used as an additional fail-closed witness
in this test route; failure to publish it times out safely, never causes retry.

Short tracks: when Main acknowledges the exact load and the correct new domain's
session is already ENDED before polling saw PLAYING, this test route accepts
completion without claiming a PLAYING observation. It advances only once.
Non-Phase2A controller behavior is unchanged.

## Races and failures

- Next/Previous/Play/Playlist while PARKED updates existing traversal/context and
  sends a newer generation. The old reply cannot dispatch a VGM. Fade is not
  restarted. Repeat/Shuffle update preferences locally, with policy deferred
  until the next lease. No extra snapshot/index increment on rebind.
- If READY was just published but the controller has not consumed it, a newer
  request can still carry the previous domain. It can supersede only an unused
  grant: same attested successor, exactly the granted baseline, no new index-1
  session. A changed baseline rejects the stale-domain request. Both sides of
  this race have host tests.
- A request arriving during blocking hardware configuration is reread before
  READY. If the target profile changed after configuration was committed, another
  required RBF exchange may occur, but no obsolete VGM load is issued.
- Stop while fading requests existing immediate reset_core; Stop while Main is
  being replaced is processed at the first safe successor boundary. No VGM is
  loaded; STOPPED is published only after authoritative IDLE. No magic sleep.
- Repeat One keeps resident profile. Repeat Context/Shuffle switch only where
  actual selected profiles differ, preserving the controller's live history.
- Unsupported/error classification issues no switch/load. Current reservation is
  not advanced again. Main/RBF/ownership/transaction failure uses existing safe
  Supervisor stock restoration. The request and controller trace retain the
  failing reserved selection; this phase does not promise resumable recovery
  after a fatal rollback or reconstruct a lost shuffle history.
- Existing EXIT/recovery retains exclusive Supervisor ownership. No timeout was
  increased: preparation and fade completion are bounded at 60s; existing Main
  readiness and stable-drain bounds are reused, not audio delays.

## Tests / reproducibility

`sh tools/megavgm_profile/build_and_test.sh /absolute/new/output host`

Compiles actual test controller + SwitchOwner with simulated Main/FPGA, plus
existing Supervisor/controller tests. Coverage: AAA/BBB/AABBA/ABABA; 100 alternating
loads; real controller park with FADE_ONLY->ENDED; rapid Next while fade active;
Stop->Next; request superseded during RBF configuration; fresh session reset;
stale generations/status; failed RBF keeps reserved index; classification failure
no load; short tracks including delayed acknowledgment; Repeat One/All; Shuffle;
single-controller Main drain/successor/SHA/stock restoration. Sanitizer execution
uses the same integration test. Existing autoplay/controller/control/mode tests
also run unchanged. Unit simulations are not hardware PASS.

ARM build uses the existing `mister-gcc10` Lima VM and official GCC 10.2 compiler:
`-march=armv7-a -mfpu=vfpv3 -mfloat-abi=hard -static` with C++14/Werror and
`-DMEGAVGM_PHASE2A`. Copy a git archive of the exact commit into a new VM directory,
verify archive SHA, then run this same script with `arm`. QEMU executes the ARM
tests and exact final CLI binaries. ELF checks require ARM EABI5/hard-float,
VFP registers, no PT_INTERP / DT_NEEDED. No Docker, Quartus or package installation.

QEMU filesystem qualification: the existing directory-discovery test fails on
the VM's ext4 under ARM-user emulation because its 64bit host directory cookies
cannot be represented by ARM32 `readdir` (probe: errno 75/EOVERFLOW; cookies up to
9223372036854775807, although inodes are small). The **same unmodified test ELF**
passes on tmpfs. ARM tests therefore run in a private mount namespace with a
test-only tmpfs `/tmp`; the normal VM mounts/files remain untouched. No assertion
is skipped, no production filesystem implementation/build ABI is changed.

## Hardware installation / rollback

Artifacts: `megavgm_supervisor` (test build), `megavgm_playlist` (test build), and
read-only `megavgm_classify`. Preserve production controller, Remote and RBFs.

1. Exit MegaVGM and verify STOCK. Copy Supervisor under a `.new` filename. Back up
   existing Supervisor with a unique name; do not overwrite an existing backup.
2. Install the test controller ONLY as
   `/media/fat/MegaVGMPlayer/megavgm_playlist-phase2a` (production
   `/media/fat/Scripts/megavgm_playlist` remains untouched).
3. After SHA verification, replace the Supervisor path the existing Remote calls,
   `/media/fat/MegaVGMPlayer/megavgm_supervisor`, retaining its backup. Default mode
   still uses the unchanged production controller/RBF route.
4. While STOCK: `megavgm_supervisor test-profile phase2a`. Selection is temporary
   `/tmp`, and rejected while an ENTER/active/drain owner holds the existing lock.
5. Use existing Remote Playlist UI: create a **separate** mixed test playlist, e.g.
   Space Harrier Credit (A), Night Striker Coin (B), Final Take Off (A), Daddy Mulk
   (B), another A. Do not replace Favorites or alter any stored production list.
6. Start a selected row. No UI sound-family button, manual load_core or new
   Remote endpoint is needed. Test both first-A and first-B cold entry.
7. Return: Exit -> verify STOCK -> `megavgm_supervisor test-profile default`.
   Restore the saved Supervisor if desired. Do not replace Remote/Main/RBFs.

## Exact hardware checklist (NOT YET VERIFIED)

- First A/B cold Playlist: selected count/index preserved, modified Main runtime
  SHA matches frozen value; correct `_Utility` RBF argv; first fresh session 1.
- AAA: 0 exchanges; BBB: one initial cold B boot then 0 exchanges.
- AABBA: 2 exchanges. ABABA: 4 exchanges. Count actual load_core events, not UI.
- For cross-profile manual Next: same old session -> FADE_ONLY -> ENDED; **no
  intervening old-RBF index1**. New successor identity -> IDLE0 -> policy2 -> one
  generated index1 -> new session1. Record exactly one load per reserved track.
- Short Coin/Title/Opening and natural EOF: index advances once; no skipped or
  doubled tracks. Loop-limit retains existing two-loop predicted 2s fade/no loop3.
- Repeat One: no unnecessary reload/switch; Repeat Context and Shuffle preserve
  order/history and switch only at profile boundaries.
- Rapid Next while fading AND while Main restarts: only latest reserved VGM gets
  index1. Stop during both windows: no late VGM load; STOPPED; Next/Play resumes.
- YM2610B FM/SSG/ADPCM-A/B and A-family audio: no old-session sound, permanent mute
  or missing intro. These audio checks require listening; host tests cannot prove them.
- EXIT/natural playlist completion: stock Main restored, no extra controller or
  Main process, existing production route still usable after `default`.
- Collect `/tmp/megavgm_supervisor.log`, `.status`, `/tmp/megavgm_playlist.trace`,
  `.status`, `/tmp/megavgm_load_file.log`, `.status`, `/tmp/MegaVGMPlayer.status`,
  and the private Phase2A request/reply directory before reboot.

No Phase 2B or production promotion is authorized by these host test results.
