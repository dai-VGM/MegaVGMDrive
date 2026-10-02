# Historical v2.2 switch-latency hardware candidate validation

Archived checklist for the earlier lab candidate. Current v2.3 accepted payloads
are unchanged; this version-only correction does not require a new hardware run.
See [FINAL_PROMOTION.md](FINAL_PROMOTION.md).

This package is a lab hardware candidate, not a public or final v2.2 RC. Do
not add manual loop metadata to Commando, Volfied, or another real tune during
this first acceptance pass.

## OSD and latency acceptance

1. Load a large Engine A/B VGM and a multi-megabyte prepared SID.
2. Confirm 0%, intermediate progress, 100%, and completion are visible and natural.
3. Confirm no stale progress remains; error and cancel publication are not delayed.
4. Exercise A→B→C, C→C, C→A, and C→B. Confirm switching is visibly faster without a stuck or wrong core.
5. Confirm Stop, Next, Previous, and replacement retain their existing behavior.
6. Record Supervisor status/log timestamps, Main ownership, active RBF, session, and subjective OSD notes.

This candidate retains the 200 ms Supervisor cadence and 1500 ms stable-zero contract. It does not include the rejected 50 ms cadence experiment.

## Fixture authority

- Raw SID: `/media/fat/MegaVGMDrive/C7_2_Hardware_Test/C7_2_Manual_Loop_PAL_6581.sid`
- Sidecar: the adjacent `.sid.loop.json`
- Model/timing: PAL / MOS6581
- Requested intro boundary: 1000 ms
- Requested loop end: 3000 ms
- Resolved native cycles: `972363..2937989`
- Packed loop write index: `107`
- Packed canonical write count: `115`
- Expected cold-cache key: `05c08152edf3b1bd5e24a3d25d3e079d4acdc66480c51490991200c4a9a365fc`

The fixture is original MegaVGMPlayer test code. It contains an audible
ascending one-second introduction followed by one canonical two-second,
four-note loop traversal.

## Safe installation

1. Keep the current known-good package and rollback checkpoint available.
2. Enter and verify STOCK mode.
3. Run `install.sh` or `upgrade.sh` from this extracted candidate.
4. Verify installed files against `SHA256SUMS`.
5. Reboot and verify MiSTer starts in STOCK mode.
6. Open the existing MegaVGMPlayer PWA. Do not manually select an RBF.

## Manual-loop acceptance

1. Select the synthetic raw SID and confirm the adjacent sidecar is recognized.
2. With no matching cache entry, confirm cold prepare publishes a strict
   Packed MVGMSID v2 pair with `LOOP_VALID=1`.
3. Confirm PROFILE_C loads without an A/B behavior change.
4. Hear the one-second ascending intro exactly once.
5. At the first loop boundary, listen for a pop, pitch discontinuity, gap, or
   stale sample. All must be absent.
6. Confirm the second and third loop traversals remain continuous.
7. Select Repeat One and observe at least ten boundaries. Confirm the loop
   counter increments once per boundary and no session reset occurs.
8. Select the finite two-loop policy and confirm one fade and exactly one
   authoritative ENDED event.
9. Stop during an active traversal. Confirm immediate silence, no phantom
   ENDED, then clean replay including the intro.
10. Replace the track during a traversal. Confirm existing fade/replacement
    ordering, no stale audio, and one new accepted session.
11. Replay within PROFILE_C and confirm no RBF reload.
12. Exercise Previous and Next, then replay the fixture.
13. Confirm no stale SID model, clock, oscillator, filter, envelope, audio, or
    session state across repeated loads.

Record cache payload/provenance, Controller trace, Supervisor status, FPGA
status, loop counts, session numbers, timestamps, and subjective audio notes.
Simulation and Windows compilation are not substitutes for this checklist.
