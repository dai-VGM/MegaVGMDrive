# Four-engine candidate deployment

This is an unpublished hardware-acceptance candidate. Do not replace or edit the
public v2.2 release, tag, ZIP, or assets.

On MiSTer, exit MegaVGMPlayer and verify STOCK before replacement. Upload every
candidate as a distinct `.new` file, compare its SHA-256 with `SHA256SUMS`, retain
a timestamped backup of the current file, then rename on the FAT filesystem.
Never copy directly over a running executable or resident core.

The canonical RBF destinations are:

```
/media/fat/_Custom Cores/Cores/MegaVGMDrive_A.rbf
/media/fat/_Custom Cores/Cores/MegaVGMDrive_B.rbf
/media/fat/_Custom Cores/Cores/MegaVGMDrive_C.rbf
/media/fat/_Custom Cores/Cores/MegaVGMDrive_D.rbf
```

After installing the matching Supervisor, controller, and Remote, use the
existing service contract to restart the Remote. Verify its executable identity
and SHA, then exercise A→B→C→D→A, same-engine transitions, Repeat All wrap,
Stop/resume, mid-playlist selection, cold-start selection, and reconnect. Engine
D acceptance must include Dragon Saber, Starblade, Rolling Thunder 2, Phelios,
and Metal Hawk, including title, System 2/21, activity, loop, Stop, and Next.
