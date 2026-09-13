# MegaVGMPlayer v2.2 C6 candidate — Raw SID Auto Prepare

- Packed MVGMSID v2 Engine C is available as `MegaVGMDrive_C.rbf` under
  `/media/fat/_Custom Cores/Cores/` and joins automatic A/B/C switching.
- Frozen MVGMSID v1 remains supported by the same Engine C RBF.
- Raw single-SID `.sid` files now appear in Browse and are prepared on demand
  into a persistent, strictly validated Packed v2 cache on MiSTer.
- Cache misses publish authoritative `Preparing SID…`; cache hits use the
  normal C5 load path. Stop/Next/Previous/new Play cancel the prior preparation.
- Pinned libsidplayfp 3.1.1 captures actual SID bus WRITEs at native PHI1 cycle
  precision and emits Packed v2 directly—no v1 intermediate or 44.1 kHz timing
  quantization.
- Exact model/timing metadata is required. Multi-SID and BASIC-ROM-required
  inputs are explicitly unsupported in this initial stage.
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
