# Engine C C4 transport validation CORENAME build

This lab-only validation revision changes the effective MiSTer `CONF_STR` core
name from `MegaVGM Engine C C2 Lab` to the existing production-family name
`MegaVGMDrive`. The SID implementation, MVGMSID parser, native scheduler,
audio/reset/publication path, common transport/fade owner and status-v2 RTL are
unchanged from `aaea4d01becafba262b712f148ee092265a932b7`.

The original C4 QPF remains available and retains its original CORENAME. The
new Windows Full Compilation target is:

```text
hw/engine_c_c4/MegaVGMPlayer_EngineC_C4_Transport_Validation_MiSTer.qpf
```

Expected Quartus output:

```text
hw/engine_c_c4/output_files_validation/MegaVGMPlayer_EngineC_C4_Transport_Validation_MiSTer.rbf
```

For the existing lab Supervisor route, stage that output under a new filename,
verify its checksum, preserve the previous C4 RBF, then atomically replace:

```text
/media/fat/_Utility/MegaVGMPlayer_EngineC_C4_Transport_MiSTer.rbf
```

The Supervisor and modified Main are not changed by this revision.
