# v2.2 Engine C C6 exact hardware acceptance — NOT YET RUN

## 8 MiB Packed-v2 capacity gate

1. Preserve an existing 4 MiB-policy Volfied cache pair; do not delete it.
2. Play the raw Volfied SID and prove the old key is not a cache hit.
3. Measure the cold conversion time and record the new cache key.
4. Record prepared artifact bytes, WRITE count, and final native cycle; validate
   the payload/provenance pair and `capacity_bytes=8388608`.
5. Measure PROFILE_C load time.
6. Confirm playback passes the former approximately 3:30 capacity termination.
7. Continue through the approximately five-minute fallback endpoint without
   wrap, premature EOF, stale audio, or permanent Loading.
8. Replay the raw SID and prove an immediate strict cache hit.
9. Verify C→C performs no RBF reload.
10. Verify A→C→B→C and exact order/session ownership.
11. Load a near-8 MiB synthetic Packed-v2 artifact and confirm acceptance.
12. Present an 8 MiB+1 artifact and confirm explicit rejection with no address
    wrap, partial load, profile transition, or residual PLAYING state.

## Existing A/B/C and C6 regression

1. Return to STOCK, run `upgrade.sh`, preserve the printed backup path, and reboot.
2. Verify A/B/C RBF hashes and exact `active_rbf_argv` paths under
   `/media/fat/_Custom Cores/Cores/MegaVGMDrive_[ABC].rbf`.
3. Play one Engine A track and one Engine B track.
4. Play Commando Packed v2 for the full 270 seconds on Engine C.
5. Load one frozen MVGMSID v1 artifact through the production `.mvgmsid` route;
   confirm backward-compatible playback and a clean Natural EOF.
6. Play C→C: Commando→Power→Realm→Relaxation; confirm no RBF/Main reload and
   correct PAL/NTSC plus 6581/8580 session relatch.
7. Verify A→C, C→B, B→C, and C→A individually.
8. Play A→C→B→C→A and confirm exact order, one switch per boundary, and no
   duplicate load/session/ENDED.
9. Verify Repeat Off completion restores STOCK; verify mixed Shuffle.
10. Verify Stop and cross-profile Next/Previous; immediately after Stop, tap a
    Playlist track in the same profile and another profile and confirm both are
    admitted without a lockout.
11. Confirm same-profile A→A, B→B, C→C perform zero RBF reloads.
12. Confirm `error=00`, no stale audio, no permanent mute, and no phantom ENDED.
13. Check Player labels `SID 6581`/`SID 8580` and metadata without changing route.
14. Return to STOCK and run rollback; verify the previous v2.1 runtime and legacy
    RBF files remain available.
15. Put raw `Commando.sid` in the library, confirm Browse visibility, tap it,
    observe `Preparing SID…`, then verify automatic Engine C playback.
16. Play the same raw SID again and prove a persistent cache hit (no reconvert),
    including after reboot.
17. Validate raw Volfied voice/digi playback, C→C raw SID, and an A→SID→B mixed
    playlist. For each long Volfied LOADING transition, confirm the live PWA
    clears `Loading…` at authoritative PLAYING without a page reload.
18. During a cache miss, test Stop and Next; no late prepared result may load.
19. Confirm Favorites/Playlist persistence and the iPhone bottom-nav/safe-area
    layout remain unchanged.

Capture Supervisor/controller logs and runtime hashes on any failure. Host/QEMU
PASS is not a substitute for this checklist.
