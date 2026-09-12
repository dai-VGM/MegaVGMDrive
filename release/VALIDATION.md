# v2.2 Stage 1 validation scope

## Frozen RBF provenance

- Engine A: `5755b74d9b1e10e1da1d6c101892bc95ca8960851a851cc9076d1861c9571f1e`.
  Byte-identical to the v2.1 hardware-PASS artifact; no Quartus build.
- Engine B: `b435417f268a81a39af6bf2408f364945d151e391425775ab7d01ed4899bec95`.
  Byte-identical to the v2.1 hardware-PASS artifact; no Quartus build.
- Engine C: `117adcd8d9360388826f60f4207c5b547daee58f5f0ba2e456f10e7bf41abed8`.
  Exact C4 CORENAME-validation artifact from source commit
  `5d0c9b73f70dd3912e112b172d36329d3e3d9cfe`; the user confirmed C4
  transport/audio hardware behavior on this exact SHA.

The package copies these bytes to `MegaVGMDrive_A.rbf`,
`MegaVGMDrive_B.rbf`, and `MegaVGMDrive_C.rbf`. Engine C is staging-only:
PROFILE_C and SID classification are not enabled in Stage 1.

## Host binaries

- Supervisor source `45d04cd993d9c7b5d85afb88ec563b811cf67e2c`;
  SHA `3c3e9d0141efa8966cdb2dfdd53d2e7edb7a35e55f23495879b8ac4a2ccfc5bf`.
- Controller source `ad450e076291e6cdf58fdb17f1ab5c88b114a797`;
  SHA `8e25bb51e849a0b7ca8b0f037656b8a297637881985fc2f0e3c7a0b66f4f56d3`.

Both are ELF32 ARMv7 EABI5 hard-float, statically linked, with no PT_INTERP
and no DT_NEEDED. Their binary strings contain only the exact new A/B paths;
no C route was introduced. Host and QEMU suites cover A→B→A, same-profile no
reload, exact argv rejection, missing RBF failure, switch/session races,
production-default routing, and STOCK restoration fixtures.

## Package gates

The isolated install/upgrade/rollback suite verifies nine payload files,
internal and archive checksums, exact RBF names/hashes, old v2.1 RBF preservation,
new-name coexistence, transactional backups, recoverable removal of introduced
files, data persistence, duplicate install, corrupt package rejection, symlink
rejection, and later-edit refusal.

The reboot-like preflight fixture reproduces both `STATUS_UNAVAILABLE` and the
failed `supervisor exit` control-plane result. It accepts one exact-SHA stock Main
without persisted status, and rejects a modified Main, wrong Main SHA, active
controller, multiple MiSTer processes, active session state, and persisted
MEGAVGM-active status. Persisted `mode=STOCK/main=STOCK` retains the original path.

These are host/QEMU results. The renamed-path package and new Supervisor/controller
have not yet completed the final MiSTer reboot/switch/rollback checklist.
