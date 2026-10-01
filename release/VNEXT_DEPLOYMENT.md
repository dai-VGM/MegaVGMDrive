# Four-engine candidate deployment

This is an unpublished hardware-acceptance candidate. Do not replace or edit the
public v2.2 release, tag, ZIP, or assets.

## Golden Player Platform authority

The accepted common Player baseline is documented in
`/Users/daizo/Projects/MegaVGMPlayer_Platform_Contract.md` and is pinned to:

- Runtime/Controller source `76cf4abff9eac21a7acc090514385d5c8c534b10`;
  `megavgm_playlist` 1,068,308 bytes, SHA-256
  `29a0fc7ad60d2003757d87f14da831a24b84d517ad51dc6c1e741878092efd25`.
- Remote/PWA source `fab3f55fa601ddd8e0931615aa3bfe91b8c6b66c`;
  `megavgm_remote-parent-folder-fab3f55` 10,121,840 bytes, SHA-256
  `04d5b2e6d6b135de7f919a97c39e07743a414e0cbf33a36f3c9ee54e9645a388`.
- Embedded PWA `megavgm-ff892105.js`, SHA-256
  `0ea1ba5090707425182ea94b4b2d66c4a8df3f48616e13a0666193c327680ffd`.

These source/artifact identities were verified locally. Their stated Player/UI
behavior is hardware-PROVEN; this does not promote or mutate public v2.2.

The existing generated staging tree at
`/Users/daizo/Projects/MegaVGMPlayer_vNext_4Engine_Staging/MegaVGMPlayer-vNext-4Engine-RC`
is **stale for the common Player binaries**: it contains Controller source
`27a93571a3b4da7cfc5ab38b35085ff901998d16` / SHA-256
`6b2ae98d9d996339710084c34862e5c2c737a939e50c970f1ef3b0335be3f73e`
and Remote source `f63e358b7eb7014b891ff2bd7e4a782b26a94893` / SHA-256
`22a67d0bb1262c0a2a88cb839520664f740a9321dee60c0edc31d69cc46df2ea`.
Do not treat that directory as the final Player authority or silently replace it;
regenerate a new staging directory from the authorities above in a separately
approved promotion task. Its A/B/C/D RBF bytes already match current authorities.

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
