# Scoped user hardware acceptance

Authority: DAI explicit v2.4.0 Architecture Refresh request, 2026-10-09. No fresh hardware test was performed during integration. Earlier NOT_RUN generation receipts are retained, not edited.

- Engine A: audio playback, PWA startup, transparent bottom Loading, Activity OSD, track switching. RBF SHA256 `57b005ae66c586189e153cfe09b4b680e781deaec29bac1f19654e42f5b9b6c3`.
- Engine B: audio playback, PWA startup, track switching. RBF SHA256 `70392ce76932c85c21cd5f2ef3a73f1b07026e7573c8e75e753a804660d51507`.
- Engine C: retained stable audio/PWA acceptance; native-cycle path unchanged. RBF SHA256 `45f63808ca4d9871716af0bbc46f2335cd49d14fceafb537108ef2fa9f3e6110`.
- Engine D: YM2151/C140 playback, PWA startup, transparent bottom Loading. RBF SHA256 `064c398c42d7daa729bf5081efba6213ca872d8f7f9b1889f1004a24e0422ed7`.

Production requirements still include all-channel Activity, transparent bottom Loading, playback/PWA/automatic switching, Stop/Next/Reload/loop, current status/session and long-duration stability. A narrower reported receipt is not an implicit PASS for every remaining path. Long-duration/full-asset/full admission and a new package deployment are NOT_RUN/not claimed.
