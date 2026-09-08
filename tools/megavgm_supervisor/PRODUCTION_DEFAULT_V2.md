# v2.0 production ENTER default

Base: 66f5928ee19895d02472f870fe38ecd3305e155f.

In a MEGAVGM_PHASE2A build, apply_test_profile now selects PHASE2A_AUTO
when the selector directory or profile file is absent. ENTER already calls this
function before phase2a_preflight; the existing preflight classifies the selected
VGM, selects the resident engine and establishes the existing channel. The
controller path is /media/fat/MegaVGMPlayer/megavgm_playlist-phase2a.

This does not launch anything at boot. Stock MiSTer remains running until ENTER.
The existing completion/Exit recovery restores stock Main.

The selector is still /tmp/megavgm_supervisor-test/profile for explicit lab use.
`test-profile default` deletes that override and now returns to production auto.
`test-profile phase2a` remains accepted for compatibility. Fixed lab profiles
fade-only-a, fade-only-b and ym2610b-phase1b explicitly select phase2a=false and
/media/fat/Scripts/megavgm_playlist. They remain locked to STOCK-only selection.
Invalid or unsafe selector files still fail closed; they are not ignored.
Non-MEGAVGM_PHASE2A builds retain the old absent-file default.

The A/B filenames remain exactly:

- /media/fat/_Utility/MegaVGMPlayer_Transport13FadeOnly_A_MiSTer.rbf
- /media/fat/_Utility/MegaVGMPlayer_Transport13FadeOnly_B_MiSTer.rbf

No changes to classifier, SwitchOwner, Phase2Service, Remote, controller,
FADE_ONLY, snapshot ownership, Main verification, session rebase or RBFs.

Validation combines route tests (three fresh Paths instances with the temporary
selector directory removed to simulate reboot, default cleanup, fixed lab
overrides, ENTER/Exit/normal completion) with existing Phase2A real-controller
simulation tests (same-profile zero reload, mixed A/B transitions, rapid Next,
Stop, stale status and session reset) and Supervisor lifecycle tests.
These are host/QEMU simulations, not an actual MiSTer reboot or Remote HTTP test.
