# Frozen inputs and switch-latency hardware-candidate provenance

## Adopted latency optimizations

This unpublished hardware candidate combines exactly two adopted changes:

- Supervisor Phase 1 authority `70d2aefd121f975210be6b59886a8211bd7ec150`, integrated at `1ba36ce10cdd41d48ca0194de26d08ce2eb89c5d` only to pin the candidate Main SHA. The successor Main uses condition-based verification. The 200 ms service cadence and 1500 ms stable-zero contract remain unchanged.
- Main authority `144ae51a2b289fc86f2e09131e3173be9f0e45e2`, limiting upload ProgressMessage publication to a 100 ms monotonic interval while preserving immediate start, 0%, 100%, completion, error/cancel, and phase changes.

Rejected Supervisor Phase 2 `db7b0f084edc33fd0471fcfdd7ad84bb057a6573` is not included. The integration was built from a clean independent checkout after proving that Phase 2 is not an ancestor.

| Component | Source | Artifact SHA-256 |
|---|---|---|
| Main | `144ae51a2b289fc86f2e09131e3173be9f0e45e2` | `b691d783a26a9ab94a338433e4f43cf69237cc3a1f7e19bdd3f753f906dc0742` |
| Supervisor | `1ba36ce10cdd41d48ca0194de26d08ce2eb89c5d` over Phase 1 `70d2aefd121f975210be6b59886a8211bd7ec150` | `c83caf59e9685e4bbb777c2f225c90c2bf591a627f1431dffd00e7ef01aadc0e` |

## Engine C C7.2 manual loop hardware candidate

This lab candidate adds strict manually authored loop metadata and matching
Packed-v2 checkpoint/replay. It is not a public or final v2.2 RC. Engine A/B,
Main, Remote, Frontend, Packed-v2 format/version, SID audio calculations, and
the established transport/fade ownership remain unchanged.

| Component | Exact source commit | ARM artifact SHA-256 |
|---|---|---|
| Controller | `1cffacda1feed2cb26e54f0d557565ca2f68203b` | `6e1b11f1b84cac228459ace91fb69f27469024d74062f28007e1edb6af9c221c`; strict Packed-v2 v2 loop validation; existing watchdog/cancellation and routing ownership unchanged |
| Supervisor | `1cffacda1feed2cb26e54f0d557565ca2f68203b` | `4200ae6b6ab7a5e359bc7a080a94ee3fae456c73c4e4e2abd178f6fdd53760dd`; shared strict classifier and production A/B/C route |
| Standalone Remote/frontend | `9f13f04d0117036809fa06c756540e92df8bfd50` | `4f8a6762441291ccc6bc0c8ce395937197b5a27a7aca06698de15e967f2a05bb`; exact PLAYING/STOPPED playlist warm admission and status/error/operation trace; authoritative transport epoch/switch generation retires local Loading across legal equal-number session rebases; embedded `assets/megavgm-f6c226d2.js` SHA `6f7aed749a58c8ae87e7f231e6d12bff11d86f6581b20b637d89c3b42b93bba1` |
| Direct Packed-v2 SID preparer | `247d0f198d52ca7789a845a878679c87b2f7e7dc` | `4c640b2c5946e4b541cfdae11d298ec9d3e5a01c9fa840dae9dab5afe4da3f0f`; embedded commit matches the clean checkout; manual sidecar identity and resolved boundaries are included in cache/provenance |
| Engine C C7.2 RBF | RTL `8e5f1111f8b0afdd6b75ae0011ba891ef344a87d` | `d6d7bb22beed1366be41b34ab12699cbc3174c46f00705c8f36cd16fd1510dc5`; 2,677,792 bytes; supplied Windows Quartus Full Compilation; hardware validation pending |

The preparer statically links libsidplayfp 3.1.1, fixed upstream commit
`732fa8ec8131fc75aafc2eaea583ddcdeea2a3cc`. The exact upstream archive SHA is
`12b79190593bf480b2d11481b5c2de62bac07f344437a66cd8d887329875c626`.
The release carries that archive, GPL-2.0-or-later text, exact observer patch,
preparer source, dependency lock, tests, and native/ARM build recipes under
`source/megavgm_sid_prepare/`. No Commodore ROM or SID tune is included.

The production ARM build uses `production_build_arm.sh` around the authority
commit's unchanged `build_arm.sh`. The guard requires an explicit full source
SHA, proves that it equals the checkout's real `HEAD`, and rejects tracked or
untracked dirt before compilation. The production build was made from an
independent detached checkout at `247d0f198d52ca7789a845a878679c87b2f7e7dc`;
it does not follow a host linked-worktree `.git` pointer inside the Lima VM.

The hook executes immediately before `sidemu::writeReg(addr,data)` reaches the
emulator and records native PHI1 cycle, SID index, register, and data. It does
not poll registers, reconstruct snapshots, or generate MVGMSID v1. The raw SID
path preserves the original track as queue/status identity; only a strictly
validated atomic cache artifact is passed to the existing PROFILE_C classifier.

Manual loop metadata changes output identity without changing Packed MVGMSID
v2 format/version. The cache key includes the exact sidecar SHA, requested
boundaries, subtune, source SHA, snap policy, converter commit, and the existing
`capacity_bytes=8388608`. Sidecar removal or editing naturally selects another
key without deleting an old cache entry.

Release installer commit `bde4bef` treats package bytes as the deployment
authority. It re-hashes every installed production target, restarts the
standalone Remote, then requires the package, installed file, runtime copy,
service identity, and `/proc/<pid>/exe` SHA/path to agree before creating the
transaction `COMPLETE` marker.

## Engine C C5 production integration

The v2.2 C5 candidate retains the Phase 1 inputs documented below and adds only
the reviewed production path for prepared SID streams.

| Component | Exact source / artifact | SHA-256 |
|---|---|---|
| Engine C Packed v2 RBF | `MegaVGMPlayer_EngineC_PackedV2_Validation_MiSTer.rbf`; RTL `53291cd59a64dee7c3c4edb5a2f0f0a8e69c99db` | `0f205de6ab30e86477fdf1b0797e82158cc5b14fdfa37e7011f3c94cbb72c479` |
| Controller | `823881ab69d6074ffa991bfc98e9662d9ebf2b88` | `76f8ac60faae7d0bbdf79fa8dc5c4899ed33c3e6ef02aa82902907c865171df1` |
| Supervisor | `aa3e2bab7606084063845275797f8380e45dc259` | `8e4c22b97215451accce369f4c81353e467674a8e23c04ff5fb68fa8900b4d75` |
| Standalone Remote | `8af356aa58eda6d78953d64e614f66288d4570c1` | `8e23be45da2069e8b1c29bbad8ce14d004d3653970cbc13eebe21d4647ebd02d` |

The RBF is 2,669,332 bytes. Its QPF provenance is
`hw/engine_c_packed_v2/MegaVGMPlayer_EngineC_PackedV2_Validation_MiSTer.qpf`;
the validation QSF selects `ENGINE_C_C4_MEGAVGMDRIVE_CORENAME=1`, yielding the
exact core name `MegaVGMDrive`. The user confirmed the exact RBF SHA with a full
270-second Commando Packed v2 run and Volfied digi/voice playback. That evidence
validates the FPGA artifact, not the new production A/B/C host integration.

The controller classifies only a strictly valid MVGMSID v1 or Packed v2 stream
as PROFILE_C. Both use `.mvgmsid` for library discovery. Raw `.sid` and the
experimental `.mvgmsid2` suffix are excluded. Existing A/B VGM decisions are
unchanged. The Supervisor uses exact A/B/C paths and preserves the established
switch generation, controller parking, session rebase, and STOCK restoration
contract.

## Source imports

| Component | Exact input |
|---|---|
| MegaVGM backend + tests | `/Users/daizo/Projects/mrext-track-chip-status`, `6ef56324b91df854080f65f5c4c0f0535740b4ca` |
| Player/frontend assets | `/Users/daizo/Projects/mrext-client-final-header-logo`, `8dc1988b106276e215de5e3164a2307e90aa9017` |
| Host/classifier/status (unchanged) | `e01c872d6854edce77c1fbc7a8f68239f8ecf045` |

Imported production Go files: `megavgm.go`, `favorites.go`, `playlists.go`,
`sound_chips.go`, `transport_status.go`. Original test assertions copied verbatim;
test-only `retireFixture` cleans up asynchronous trace writers before TempDir
removal. A separate
`lifecycle.go` adds only cancellation of the diagnostic convergence monitor after
HTTP drain; it has no playback command path.

Frontend `MegaVGMPlayer*`, `megavgm*`, `useMegaVGMScroll`, and
`remoteHeaderPresentation` are byte-identical imports. `models.ts`/theme definitions
and branding assets are copied. `tests/extract-frontend.cjs` documents the mechanical
API/query extraction. Same-origin constructor and dedicated entrypoint are new.
The original Remote shared Layout is not imported. Upstream license files retained.

## Exact production helper

Local source artifact:
`/Users/daizo/Projects/MegaVGMPlayer_Remote3/megavgm_ctl-transport-m5`

Copy in this candidate: `artifacts/megavgm_ctl.production`.

- 961808 bytes
- SHA-256 `378905c80c22f0b072e248d6fdb67238f2727a38287f4407b2596c8c2a9ae45b`
- ARM32 EABI5 hard-float, static, stripped
- Runtime dependency remains `/media/fat/Scripts/megavgm_ctl`.
- Saved build tree: existing `mister-gcc10` Lima,
  `/tmp/controller-m5-build/tools/megavgm_playlist/`.
- **All five compile input files match commit
  `9e2dd45fbd986378bbdaba326d8e722df2b89c27` exactly** in MegaVGMDrive.
  Do not substitute current `playlist_control.cpp` from e01c872d: that file has
  later changes. The helper is its own frozen dependency.

| File | SHA-256 |
|---|---|
| ctl.cpp | `39279713f238dbdee3f15a46c814fcc7a2f6afe6d26756cfd64d289127edffc4` |
| playlist_control.cpp | `cfd6f864ff711ffa1e631b2cda6c5a1d9ada530d382800b69b5b5e18a78f6b85` |
| playlist_control.h | `559ceb77711cd0d29e12adac17f257ad244d266778785f15f22f5f0cdf881ef0` |
| playback_mode.cpp | `43bb2c0a07f1d9713bdfa971cebdf36abc32ea1531185b1d664c4016f9a85c5b` |
| playback_mode.h | `cf16ff0dd564649f8f06884cdfca6dfaefdac3b7bd433462917470812171bb23` |

Reproducibility proof, using the existing official toolchain, separate disposable
output only (the production artifact was not changed):

```sh
cd /tmp/controller-m5-build/tools/megavgm_playlist
/opt/gcc-arm-10.2-2020.11-x86_64-arm-none-linux-gnueabihf/bin/arm-none-linux-gnueabihf-g++ \
  -O2 -std=c++14 -Wall -Wextra -Wpedantic \
  ctl.cpp playlist_control.cpp playback_mode.cpp -static -s \
  -o /tmp/megavgm-ctl-phase1-provenance-check
/opt/gcc-arm-10.2-2020.11-x86_64-arm-none-linux-gnueabihf/bin/arm-none-linux-gnueabihf-elfedit \
  --output-osabi GNU /tmp/megavgm-ctl-phase1-provenance-check
```

Before OSABI normalization the only difference was ELF byte offset 7 (SYSV=0
versus GNU=3). After normalization, full-file `cmp` and expected SHA matched.
This proves a reproducible equivalent recipe, not recovered historical shell
history. ELF `.comment` also identifies GCC 10.2.1 20201103, ARM 10.2-2020.11.
The verification output is not distributed in place of the original helper.

## New daemon build

Existing `remote3-arm-gate` Lima: Go 1.21.9, `arm-linux-gnueabihf-gcc`,
`GOOS=linux GOARCH=arm GOARM=7 CGO_ENABLED=1`, external `-static`, stripped,
`-trimpath`. Full recipe: `tests/build-arm.sh`.

Only standalone daemon is a new runtime artifact. Existing Remote, Supervisor,
controller, Main, RBF, importer and startup scripts were not modified or replaced.
