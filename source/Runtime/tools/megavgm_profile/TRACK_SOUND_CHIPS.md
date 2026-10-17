# Read-only track chip evidence (Phase2A)

Base: `66f5928ee19895d02472f870fe38ecd3305e155f`.
No changes to SwitchOwner, Supervisor, channel request/reply encoding, lease,
session rebase, park/resume, policy/FADE_ONLY, classifier decisions or RTL.

## Contract

`Classification.sound_chips` is optional comma-separated display evidence.
The existing scanner observes accepted sound commands, then emits metadata only
after the original profile/header/bounds/unsupported/dual-chip validation passes.
Unused header clocks and ROM/data blocks alone do not assert a played chip.
No second scan, subprocess, cache, timer, file I/O or classification decision is
introduced into controller dispatch. Existing classification results are reused.

| Existing accepted command | Display evidence |
| --- | --- |
| 4F/50 | PSG |
| 52/53, 80..8F, E0 | YM2612 |
| 54 | YM2151 |
| 55 | YM2203 |
| C0 | SegaPCM |
| 58/59 | YM2610/YM2610B package declaration when present; otherwise track-local header/usage evidence |

Header0x4C bit31 declares that a file targets the YM2610B variant, as specified
by VGM. It does not prove that this particular track uses either added FM
channel, and real packs are not internally consistent enough to recover the
installed chip from that bit alone. The Ninja Warriors local pack has ten
bit31-set and four bit31-clear playable files, while Darius II has bit31 set in
all sixteen; neither pack uses a B-only FM channel. The per-track bytes therefore
cannot produce the authoritative package labels `YM2610B` and `YM2610`.

The importer now preserves the package's explicit `Music hardware:` field as
an exact, versioned `.megavgm-sound-chip` record in the prepared collection:

```text
version=1
sound_chip=YM2610B
```

Only exact `YM2610` and `YM2610B` declarations are accepted. `classify_file`
walks only canonical ancestors below the approved root, rejects symlinked,
non-regular, oversized or malformed records, and applies the declaration only
to `sound_chips`. Without a valid package record, the conservative track-local
fallback remains: a B-only key-on, frequency or channel-control write reports
YM2610B; the compatible four-FM-channel subset reports YM2610. Writes that only
initialize hidden operator slots do not count as audible use.

This keeps installed hardware identity separate from track-local channel usage.
This is display metadata only: PROFILE_B routing and validation are unchanged.
PSG is retained here and in the API. Only the Frontend hides it.
Chip usage means validated commands in the file, not instantaneous audible lanes.

The controller retains the classifier result with the selected path. Publication
copies it only when that path matches the snapshot path, into the same existing
atomic `megavgm_playlist.status` write as state/session/index/count:

```text
sound_chips=PSG,YM2612
```

There is no new ownership, generation or success condition. New selection
refreshes metadata; stop while parked clears it. Absent/unknown metadata stays
absent (including non-Phase2A route: no new classification is forced there).
Metadata is never consumed by playback logic. Current/required profile remain
exclusively RBF-switching information.

Remote adds optional JSON `soundChips`, read from this same atomic record. The
Frontend derives `Favorites · YM2612 · 4/10` from queue context plus this evidence,
never from current/required profile, filename, browsed folder or chip guesses.
Mixed main chips are retained; PSG-only has no chip label.

## Compatibility / delivery ordering

The old Remote playlist-status parser rejects unknown fields. Therefore deploy
the compatible Remote backend BEFORE this controller (or replace both while
STOCK). New Remote accepts legacy controller status without sound_chips. For
rollback, restore the old controller before reverting Remote. No automatic
deployment was performed. Existing Supervisor binary can remain: its completion
reader tests only the unchanged first `state=COMPLETE` line. Supervisor source,
switching state machine and its status ABI have zero diff.

ARM packaging was not requested in this change and has not been performed.
Hardware use requires an ARM build of this controller and Remote embedding the
matching Frontend; Mac host binaries are NOT deployable on MiSTer.

## Verification

Host build/test script, with new test_sound_chips and all existing Phase2A,
Supervisor and Playlist tests: PASS. Uses a new output directory:
`/Users/daizo/Projects/MegaVGMPlayer_TrackChip_Test/full`.
Initial sandbox run reached Supervisor Unix-socket test and was denied; full
rerun with local socket permission passed. No hardware tests were run.

New tests cover all supported labels, mixed PSG/YM2612, unused clocks, data-only
files, rejected/ambiguous input, dual chips, atomic publication and clearing.
Every PLAYING snapshot in the existing A/B integration suite asserts chip
metadata matches its exact path. Existing switch/load/session counts still pass.

Independent baseline comparison: compiled the unmodified classifier/CLI from
66f5928 and compared stdout and exit code byte-for-byte against this build over
all 212 local `.vgm` files under `/Users/daizo/Music`: identical profile, detail,
command count and selected paths. Metadata distribution before package records:

| Metadata | Files |
| --- | ---: |
| YM2610B | 15 |
| YM2151,SegaPCM | 59 |
| YM2610 | 79 |
| YM2151 | 44 |
| PSG,YM2612 | 2 |
| YM2203,SegaPCM | 12 |
| YM2203 | 1 |

Examples: Darius II/09 Planet Blue=YM2610; Metal Slug/07 Stage2=YM2610;
04 -Sub_ Last Wave=PSG,YM2612; Space Harrier/01 Credit=YM2203.
These are host classification observations, not new hardware playback claims.

With package declarations applied to the same 212-file tree, exactly the 14
locally present Ninja Warriors files change from the conservative fallback
`YM2610` to `YM2610B`; all profile/detail/command results are byte-identical.
The resulting counts are YM2610B=29 and YM2610=65, with every other label
unchanged. A fresh import of the original Ninja Warriors ZIP classifies all
17 tracks as YM2610B. The 16 local Darius II tracks classify as YM2610 when
paired with that package's YM2610 declaration.
