# v2.3 final promotion

The accepted four-engine candidate is version 2.3, proposed tag `v2.3` and
release title `MegaVGMPlayer v2.3`. Existing public v2.2 is immutable.
No tag or GitHub Release may be created until DAI explicitly approves.

`final_authorities.json` pins the unchanged 12 hardware-accepted payloads and
Runtime HEAD `f381918ad9c536433effea6158e9d1dc8aa831ae`. Official binaries are
copied without compilation. Engine C is OSD_Visual; PWA is megavgm-ff892105.js.
SID preparer/control-helper source paths retain public v2.2 provenance.

Generate into a new directory using the canonical promotion path:

```sh
python3 -B release/package.py --audit
python3 -B release/package.py --build /absolute/new-output/MegaVGMPlayer-v2.3
python3 -B release/package.py --verify /absolute/new-output/MegaVGMPlayer-v2.3
python3 -B release/package.py --promote-staging /absolute/new-output/MegaVGMPlayer-v2.3
python3 -B release/package.py --archive /absolute/new-output/MegaVGMPlayer-v2.3
```

The ZIP is `MegaVGMPlayer-v2.3.zip`; its actual SHA256 is recorded in
`MegaVGMPlayer-v2.3.zip.sha256`. Staging predecessors are retained recoverably.
Both manifest and provenance describe package version 2.3. Historical public
v2.2 source references and SID corresponding source/licenses remain intact.

New stage/restore/last-backup identifiers use `.v23-*`; checkpoints use
`backups-v2.3-*`. The shared `.v22-install-lock` remains compatible with older
installers to prevent concurrent transactions. Accepted v2.1 startup markers
remain compatibility identifiers, not current release-version declarations.

For metadata-only correction, prove all payload bytes, hashes, sizes, modes,
Runtime HEAD and embedded PWA unchanged before reusing host/ARM and
importer/title/autoplay2/admission evidence. Preserve the original results and
package SHA in `reused_regressions`; do not claim they executed against the
new package. `tests/final_release_gate.py` checks this proof.

Rerun only the isolated Linux installer/lifecycle gate after changing installer
version identifiers. Use `--rerun-lifecycle` with copied evidence; it copies an
exact current package/test snapshot into the existing Linux VM and verifies
both hashes before execution. Clean install, historical public v2.2 upgrade,
rollback/reinstall, interruption recovery, mode repair and user-data preservation
must pass. No heavy Runtime, Quartus or hardware rerun is needed.

The final gate also verifies version identity, archive/sidecar hashes,
inventory/modes, staging equality, authority contracts, relevant worktree
cleanliness and `git diff --check`. Any failed check prevents eligibility.
Tag `v2.3` must be absent locally and on an explicitly approved GitHub remote
before any tag operation. Never create or change `v2.2`, force-update a tag,
or publish without separate explicit approval. If approved, create only a Draft.
