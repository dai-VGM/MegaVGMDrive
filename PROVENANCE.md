# Frozen inputs and helper provenance

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
