# Four-engine candidate deployment

This is the unpublished hardware-accepted final RC. Do not replace or edit the
public v2.2 release, tag, ZIP, or assets.

## Golden Player Platform authority

The accepted common Player baseline is documented in
`/Users/daizo/Projects/MegaVGMPlayer_Platform_Contract.md` and is pinned to:

- Runtime authority `f381918ad9c536433effea6158e9d1dc8aa831ae`;
  accepted Controller source `ffd3336fb60472c82e4ece3133e407d15b671667`;
  `megavgm_playlist` 1,068,308 bytes, SHA-256
  `18fffb80c4ddaa45435be644d85b874046b30adf842e952ed1048169886565e5`.
- Remote/PWA source `45a45d8013fbc6292008af5d0269811493d8860e`;
  `megavgm_remote-same-track-45a45d8` 10,121,840 bytes, SHA-256
  `c54a121c3c6efea1cb32cec3610495c9fea95924a9914136e0fa8620593ca139`.
- Embedded PWA `megavgm-ff892105.js`, SHA-256
  `0ea1ba5090707425182ea94b4b2d66c4a8df3f48616e13a0666193c327680ffd`.

These source/artifact identities were verified locally. Their stated Player/UI
behavior is hardware-PROVEN; this does not promote or mutate public v2.2.

The final staging destination is
`/Users/daizo/Projects/MegaVGMPlayer_vNext_4Engine_Staging/MegaVGMPlayer-vNext-4Engine-RC`
and is populated from `release/final_authorities.json` with the accepted
Controller/Remote above, transparent Main/Supervisor, final A/B/C/D RBFs, and
the matched importer/classifier. All twelve payload sizes/full hashes are
recomputed in ARTIFACT_MANIFEST.md and SHA256SUMS. The public predecessor is
read-only. See FINAL_PROMOTION.md for the generation and release gate.

Supervisor source `8c1b57019a318ec7b96a0ec14674b3cab3cd518d`, SHA256
`db9d85cb1d2d6e84605ae2a6635070c231bc8a2ae9ef4b495469bfcd80ad4846`
pins Main SHA256 `bbc83ce23d8fbac365a5011553ee18fa29276cfbbd51ce4d8bb1bf83c52fa646`.
Importer and classifier are deployed together to `/media/fat/Scripts/`, mode
0755. Their accepted hashes are respectively
`65d54baefbd6f24c9698f5a551a30f69f3edf56ec36aa906e7fbb09b972f54b5` and
`41fa84090099c51147b8bd61b9703e34b732061acd8e025a22ef7be3c49171fb`.

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
