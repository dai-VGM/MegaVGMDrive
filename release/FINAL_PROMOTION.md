# v2.2 final promotion

Package version remains 2.2. This is an unpublished replacement RC; no tag or
GitHub/public release may be changed until the final gate report is reviewed.

`final_authorities.json` pins the 12 hardware-accepted payloads and Runtime HEAD
`f381918ad9c536433effea6158e9d1dc8aa831ae`. The official accepted binaries are
copied; fresh regression build outputs do not supersede hardware authority.
Engine C is OSD_Visual. The embedded PWA remains megavgm-ff892105.js.

Generate into a new output directory:

```sh
python3 release/promote_v22.py --audit
python3 release/promote_v22.py --build /absolute/new-output/MegaVGMPlayer-v2.2
python3 release/promote_v22.py --verify /absolute/new-output/MegaVGMPlayer-v2.2
```

Use the canonical Runtime host/ARM build_and_test route and the Runtime importer,
title integration, and autoplay2 suites. Playlist/same-track, profile/sound-chip,
Supervisor, process stabilization, and SID preparation are covered by canonical
host and ARM builds. The historical standalone playlist runner is not an
authority and is not changed for this promotion.

On the existing Linux VM, run the isolated lifecycle test:

```sh
limactl shell mister-gcc10 env PYTHONDONTWRITEBYTECODE=1 python3 \
  /Users/daizo/Projects/MegaVGMPlayer_vNext_4Engine_RC/tests/phase2_install_gate.py \
  /absolute/new-output/MegaVGMPlayer-v2.2
```

After lifecycle validation, promote the verified package into the existing
four-engine staging path; its predecessor is retained recoverably:

```sh
python3 release/promote_v22.py --promote-staging /absolute/new-output/MegaVGMPlayer-v2.2
python3 release/promote_v22.py --archive /absolute/new-output/MegaVGMPlayer-v2.2
```

Release gate requires: clean relevant worktrees (including pre-existing
untracked files); authority/manifest/hash/mode/inventory match; canonical host
and ARM/QEMU PASS; importer/metadata/idempotency/8 MiB/overflow/title/autoplay2
PASS; A/B/C/D admission PASS; negative fixtures rejected; fresh install,
v2.2-predecessor upgrade, rollback/reinstall and interruption recovery PASS.
Per-file renames are atomic; multi-file failures retain PREPARED backups and
must be recovered before publishing COMPLETE. Later user edits are preserved.

The executable final gate is `tests/final_release_gate.py`. Provide the exact
canonical host/ARM build directories and an evidence directory. Its
`--run-supplemental` option records importer/title/autoplay2/admission/lifecycle
logs and exit codes. It verifies the evidence against the tested package hash
and lifecycle-test source, then rechecks all relevant worktrees. Any non-green
condition returns exit 1 and is recorded in the requested JSON report.

Keep source/megavgm_sid_prepare and its corresponding-source/license files in
the package. No lab tune, fixture, old classifier/importer, or legacy RBF is a
current payload. Recoverable transaction backups are not active payloads.

Only after a green gate and explicit review approval should release/tag commands
be considered. The existing public v2.2 and tag are immutable during this phase;
choosing a public tag/asset replacement policy is a separate publication action.
