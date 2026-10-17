# v2.5 recoverable pre-transfer load rejection

Scope: isolated Host candidate, production HOLD. Base Runtime762615900d487c9ab8e247829a85e418b95f0cae includes Phase3.9 Runtime3da014e ownership/Repeat fixes through bc3a99e. No Main/RTL/RBF changes.

The classification rejection formerly returned InvalidTrackPath, ending Controller with code1. Supervisor correctly interpreted unexpected Controller death as a safety failure and restored Stock Main. Do not suppress that Supervisor safety path.

A controlled classification or completed container-conversion refusal now requests the existing Supervisor-owned Stop transaction before any index1 transfer. Only a real STOPPED lease and unchanged Main/session permit the Controller to wait for user intent. Retain selected queue index and repeat/shuffle state; no automatic skip/retry. Stop is idempotent; explicit Next/Previous/Play/Playlist can recover. A new successful target clears the old error atomically. No fake FPGA accepted session, ENDED, ROM or sound writes.

Optional atomic Controller fields load_error/load_error_detail are published only with STOPPED, same selected path/index and retained session. Detail is bounded/single-line. Remote passes them through the existing generic detail display. PREPARING/LOADING/new target do not carry old errors. Cold preflight can still reject before a Controller exists, leaving already-Stock Main unchanged.

Main/lease/domain/epoch/session changes, FPGA FATAL, status/control failures, owner release timeout, preparation watchdog or failed process launch are not converted into successful load errors. Existing Supervisor restoration remains enabled for actual process death. Legacy noninteractive use without ControllerIo retains its CLI failure result. Post-transfer legacy FPGA-fault queue policy is unchanged; no new skip behavior is added.

Empty K053260 declaration (encoded block length8, payload0) remains unsupported by selected FPGA. A metadata-only block is distinguished from malformed length<8, but is not forwarded. 192-page capacity remains fixed. D's PCM-only zero-YM-clock issue is separate and still rejected because selected FPGA preflight has the same restriction.

Regression: build_and_test.sh with both Host capability defines1; native and Linux ARM/QEMU. Set MEGAVGM_CREDIT_ASSET and MEGAVGM_GAMEOVER_ASSET to immutable original03/33 VGM files for real-asset Controller replay. Linux-only tests exercise actual child Controller-loop survival, explicit Next to a valid track, /proc Main identity and lease/epoch negatives; Main/FPGA are simulated. This is not hardware acceptance.
