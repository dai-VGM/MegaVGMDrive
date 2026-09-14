# v2.2 Engine C C6 validation scope

## Frozen FPGA artifacts

- A: `5755b74d9b1e10e1da1d6c101892bc95ca8960851a851cc9076d1861c9571f1e`.
- B: `b435417f268a81a39af6bf2408f364945d151e391425775ab7d01ed4899bec95`.
- C: `efb29a236cb5858d00d462bb049ad9d65d8dea55c7b7bb50afc3434a8967a633`,
  2,677,904 bytes, 8 MiB Packed-v2 RTL commit
  `1a66fcb5e0eaf963fc57a40d78c580f79ce591f5`, QPF
  `hw/engine_c_packed_v2/MegaVGMPlayer_EngineC_PackedV2_Validation_MiSTer.qpf`,
  `C2_MAX_FILE_BYTES=8388608`, macro-selected CORENAME `MegaVGMDrive`.

The C bytes are a Windows Quartus Full Compilation from the stated source
authority. Existing 4 MiB C hardware evidence belongs to the superseded RBF;
the new 8 MiB capacity and production host integration remain hardware-unverified.

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

The implementation maximum is exact 8 MiB. Native, classifier, and RTL tests
accept 4 MiB+1, 8 MiB-1, and exact 8 MiB; 8 MiB+1 is rejected without partial
WRITE or address wrap. FPGA upload accepts final byte `0x7fffff` and rejects
`0x800000`. Packed-v2 format/version is unchanged. Cache identity and
machine-readable provenance include `capacity_bytes=8388608`, preventing old
4 MiB-policy Volfied cache entries from becoming new-policy hits.

The production preparer build is guarded by an explicit full source commit.
The guard verifies the independent checkout's actual `HEAD`, rejects any
tracked or untracked dirt, and only then invokes the authority commit's existing
ARM build script. The packaged binary embeds
`6aee1ee2abad8555d2a9c34b1fd7b20f3ad295d9`; a cache produced by the superseded
mis-stamped `81fa235b7f6ef180b6c6392a042502952e72252e` binary is therefore a strict
cache miss and remains untouched on disk.

Controller and Supervisor ARM/QEMU suites cover AAA, BBB, CCC, AABBA, CCCCC,
ACCA, BCB, ABCBA, ACBCA, same-profile zero reload, cross-profile exact switch
counts, generation/domain rebase, races, repeats, shuffle, invalid input, strict
RBF argv, production default, and STOCK restoration. Remote tests cover Browse,
Favorites persistence, status metadata, `PROFILE_C`, and exact ARM HTTP assets.

Playlist warm-admission tests accept exactly controller `PLAYING` and `STOPPED`,
dispatch one `PLAYLIST` helper command for either state, and reject PREPARING,
LOADING, SUSPENDED, COMPLETE, FATAL, unknown, or malformed status without a
helper dispatch. Rejections record controller status, HTTP 409, error code, and
operation ID. The exact ARM HTTP gate also covers STOPPED acceptance and
PREPARING rejection.

Frontend operation tests cover a Volfied-equivalent long raw-SID LOADING path
whose Engine C session number equals the prior engine session. A newer
authoritative transport epoch/switch generation retires Loading on PLAYING;
older generations do not, the raw `.sid` remains the visible identity, and the
prepared cache path remains transport-only. Browse, Playlist, bottom Player,
Stop/Next/Previous, A/B/C display, reload state, and 100 transitions regress.

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
