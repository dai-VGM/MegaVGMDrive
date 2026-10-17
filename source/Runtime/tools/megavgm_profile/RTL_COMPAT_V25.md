# v2.5 A/D admission companion (isolated, not deployed)

Base Runtime: 4c1ccf7cbd35799d00295a72c4b262fd3cb088a6.
Remote/PWA remains bc2d745329f001c174ee0912ff14edab0bb4f83f.
The accepted package e0ea6db8be3349936f037ce65f7a6a6be0f9ccc20cd868675b58b735fb82efbe is preserved.

New build capabilities are default OFF, independently of existing chip vocabulary:
- MEGAVGM_HOST_K053260_EMPTY_ROM=1: only with the separately validated A empty-ROM RTL candidate. Metadata-only blocks do not consume data descriptors, clear ROM, or fabricate resident pages. Any sample reference still needs actual data; the 192-page limit remains.
- MEGAVGM_HOST_MSM6295_PCM_ONLY=1: only with the separately validated D unused-YM RTL candidate. MSM6295 validates its own header. Any real YM2151 WRITE still requires an unflagged nonzero YM clock.

Never enable these capabilities with the old A/D RBFs. No new hardware identity is asserted before a separately approved Windows build/CPF and hardware validation. This is source alignment only, not a replacement Host package or deployment instruction.

Controller/Supervisor/Remote/PWA, session/lease/epoch/queue ownership and recoverable-load-error policy remain unchanged. Native enabled and legacy-capability suites exercise the existing Controller, Repeat/Shuffle, Stop/Reload/Next and stale ownership paths. Actual Parodius03/33 and VaporTrail02 classification is checked separately against the matching RTL simulation. Source bytes are unchanged.

The D 4MHz test covers header admission and preservation of the existing implementation. It does not establish 4MHz JT51 pitch accuracy; the existing D physical-clock policy is unchanged.
