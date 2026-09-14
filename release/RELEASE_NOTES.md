# MegaVGMPlayer v2.2 C6 candidate — Raw SID Auto Prepare

- Packed MVGMSID v2 Engine C is available as `MegaVGMDrive_C.rbf` under
  `/media/fat/_Custom Cores/Cores/` and joins automatic A/B/C switching.
- Frozen MVGMSID v1 remains supported by the same Engine C RBF.
- Raw single-SID `.sid` files now appear in Browse and are prepared on demand
  into a persistent, strictly validated Packed v2 cache on MiSTer.
- Packed-v2 capacity is raised from 4 MiB to exact 8 MiB without a format or
  version change. Cache identity includes `capacity_bytes=8388608`, so existing
  4 MiB-policy cache files remain untouched but are not reused by this build.
- Cache misses publish authoritative `Preparing SID…`; cache hits use the
  normal C5 load path. Stop/Next/Previous/new Play cancel the prior preparation.
- Pinned libsidplayfp 3.1.1 captures actual SID bus WRITEs at native PHI1 cycle
  precision and emits Packed v2 directly—no v1 intermediate or 44.1 kHz timing
  quantization.
- Exact model/timing metadata is required. Multi-SID and BASIC-ROM-required
  inputs are explicitly unsupported in this initial stage.
- Browse, Playlists, Favorites, status, and the Player carry SID 6581/8580
  metadata without using display metadata for routing.
- Playlist Play can immediately hand off to a resident controller after Stop;
  transitional and terminal non-playable controller states remain rejected.
- Long raw-SID engine switches clear the optimistic `Loading…` receipt from the
  authoritative switch generation even when the new RBF rebases to the same
  numeric session; raw `.sid` remains the user-visible identity.
- Engine A/B payloads are byte-identical to v2.1. Engine C was rebuilt from the
  fixed 8 MiB RTL authority; its extended capacity awaits MiSTer validation.
- Legacy v2.1 RBFs are preserved and may coexist with the new names.
- The package includes matching exact-path Supervisor/controller builds and a
  transactional v2.1-to-v2.2 rollback path.
- Upgrade preflight accepts the normal post-reboot absence of Supervisor runtime
  status only after strict live process/path/SHA and inactive-session verification.

No SID RTL/audio, OSD, transport/fade, Main, importer, or A/B routing semantics
change is included. This candidate is not published and awaits the A/B/C MiSTer
hardware checklist.
