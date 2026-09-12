# MegaVGMPlayer v2.2 C5 candidate — production Engine C

- Packed MVGMSID v2 Engine C is available as `MegaVGMDrive_C.rbf` under
  `/media/fat/_Custom Cores/Cores/` and joins automatic A/B/C switching.
- Frozen MVGMSID v1 remains supported by the same Engine C RBF.
- Prepared SID files use `.mvgmsid`; raw `.sid` conversion remains future work.
- Browse, Playlists, Favorites, status, and the Player carry SID 6581/8580
  metadata without using display metadata for routing.
- Engine A/B payloads are byte-identical to v2.1; no FPGA resynthesis occurred.
- Legacy v2.1 RBFs are preserved and may coexist with the new names.
- The package includes matching exact-path Supervisor/controller builds and a
  transactional v2.1-to-v2.2 rollback path.
- Upgrade preflight accepts the normal post-reboot absence of Supervisor runtime
  status only after strict live process/path/SHA and inactive-session verification.

No SID RTL/audio, OSD, transport/fade, Main, importer, or A/B routing semantics
change is included. This candidate is not published and awaits the A/B/C MiSTer
hardware checklist.
