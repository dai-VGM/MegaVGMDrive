# v2.2 Engine C C5 validation scope

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

The classifier validates MVGMSID v1 (128-byte header, 16-byte events) and Packed
v2 (128-byte header, canonical ULEB records) against the no-loop, single-SID,
exact PAL/NTSC, 4 MiB RTL subset. Malformed input is rejected before a profile
request. `.mvgmsid` is the sole library extension; raw `.sid` and `.mvgmsid2`
are excluded. Existing VGM A/B scanning is unchanged.

Controller and Supervisor ARM/QEMU suites cover AAA, BBB, CCC, AABBA, CCCCC,
ACCA, BCB, ABCBA, ACBCA, same-profile zero reload, cross-profile exact switch
counts, generation/domain rebase, races, repeats, shuffle, invalid input, strict
RBF argv, production default, and STOCK restoration. Remote tests cover Browse,
Favorites persistence, status metadata, `PROFILE_C`, and exact ARM HTTP assets.

All three generated host binaries are ARM32 EABI5 hard-float and static with no
PT_INTERP or DT_NEEDED. These are host/QEMU results; final production A/B/C
switching remains hardware-unverified until `HARDWARE_CHECKLIST.md` is run.
