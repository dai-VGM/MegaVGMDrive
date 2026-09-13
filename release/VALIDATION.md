# v2.2 Engine C C6 validation scope

## Frozen FPGA artifacts

- A: `5755b74d9b1e10e1da1d6c101892bc95ca8960851a851cc9076d1861c9571f1e`.
- B: `b435417f268a81a39af6bf2408f364945d151e391425775ab7d01ed4899bec95`.
- C: `0f205de6ab30e86477fdf1b0797e82158cc5b14fdfa37e7011f3c94cbb72c479`,
  2,669,332 bytes, Packed v2 RTL commit
  `53291cd59a64dee7c3c4edb5a2f0f0a8e69c99db`, QPF
  `hw/engine_c_packed_v2/MegaVGMPlayer_EngineC_PackedV2_Validation_MiSTer.qpf`,
  macro-selected CORENAME `MegaVGMDrive`.

The exact C bytes completed the user-reported Commando Packed v2 270-second and
Volfied digi/voice hardware tests. This evidence fixes the RBF provenance; it
does not claim the new production host integration has passed hardware testing.

## Host contract

The raw-SID path first validates a PSID/RSID single-SID header, then executes the
pinned standalone preparer. Raw bytes are never sent through index-1. The
resulting cache object must pass the unchanged strict MVGMSID v1/Packed-v2
classifier before PROFILE_C is requested. `.mvgmsid2` remains excluded and
existing VGM A/B scanning is unchanged.

The preparer is ARM32 EABI5 hard-float and statically linked, with no PT_INTERP
or DT_NEEDED. Its observer captures every `sidemu::writeReg` transaction before
the emulator write using the native PHI1 cycle. Tests cover cache hit/miss,
source/version identity, corruption regeneration, concurrent producers,
unknown metadata, malformed/multi-SID input, exact sidecars, duration DB hit and
miss, deterministic Packed v2 output, and C1→Packed-v2 byte equivalence.

Controller and Supervisor ARM/QEMU suites cover AAA, BBB, CCC, AABBA, CCCCC,
ACCA, BCB, ABCBA, ACBCA, same-profile zero reload, cross-profile exact switch
counts, generation/domain rebase, races, repeats, shuffle, invalid input, strict
RBF argv, production default, and STOCK restoration. Remote tests cover Browse,
Favorites persistence, status metadata, `PROFILE_C`, and exact ARM HTTP assets.

Raw-SID controller tests additionally cover the 120-second prepare watchdog,
75-second completion, completion at the deadline, timeout generation
invalidation with no PROFILE request/index-1/PLAYING publication, immediate
retry, cooperative SIGTERM and forced SIGKILL reap, and PID-scoped temporary
payload cleanup. Cleanup preserves published cache pairs, lock files, other-PID
temps, near matches, symlinks, and directories; failures are logged.

The production-default regression also covers missing test-profile directory and
missing profile file: both select `PHASE2A_AUTO` and
`/media/fat/MegaVGMPlayer/megavgm_playlist-phase2a`. Explicit lab profiles retain
their previous selection behavior.

Supervisor prerequisite tests use one exact, case-sensitive production extension
set: `.vgm`, `.mvgmsid`, and `.sid`. Direct children pass; uppercase variants,
nested descendants, `..` paths, and unsupported suffixes fail. The existing
regular-file check remains before membership admission. A raw `.sid` admitted by
this gate is forwarded unchanged to the controller, while the existing Phase2A
preflight continues to select PROFILE_C.

Installer gates compare every installed production payload with the package SHA,
including the Phase2A controller, SID preparer, Supervisor, Remote, all three RBFs,
Main, importer, and control helper. The service gate then requires the packaged,
installed, and runtime `/tmp/megavgm_remote` SHA values to match, and verifies that
the reported PID executes that exact runtime path. A stale controller, preparer,
installed Remote, runtime Remote, or failed service identity check cannot create
the transaction `COMPLETE` marker. Clean install, upgrade, rollback/reinstall,
interrupted recovery, and the deployed ARM Remote `.sid` Browse path are covered.

The generated Remote, controller, Supervisor, and preparer are ARM32 EABI5
hard-float and static with no PT_INTERP or DT_NEEDED. These are host/QEMU
results; final C6 auto-prepare and A/B/C switching remain hardware-unverified
until `HARDWARE_CHECKLIST.md` is run.
