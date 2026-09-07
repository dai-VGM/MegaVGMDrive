# Phase2A read-only transport status

Base f280fb1. Control state, classifier, channel requests/replies, Main/FIFO,
FADE_ONLY payload, controller and RTL are frozen. This extension is optional in
`megavgm_supervisor.status` and emitted only by an active Phase2A service.

Fields (one atomic record, no independently sampled status file):

| Field | Meaning |
|---|---|
| switch_epoch | basename of EXISTING private per-ENTER channel; no new epoch |
| switch_generation | EXISTING controller request / owner reply uint64 generation |
| switch_state | IDLE, PARKED, FADING, SWITCHING, READY, PLAYING, ENDED, STOPPED, FAILED |
| current_profile | verified resident PROFILE_A or PROFILE_B |
| required_profile | accepted target PROFILE_A/B; UNKNOWN only on invalid request |
| switch_domain | existing owner reply domain (can be old while parked) |
| switch_baseline | READY grant baseline in that domain |
| switch_changed | display receipt: this generation selected a different resident, or actually called replace |
| switch_path | existing selected path, not a queue/index replacement |

IDLE is no request yet. PARKED/READY/STOPPED/FAILED project existing owner replies.
FADING is the existing ending flag / fade host call; SWITCHING is the synchronous
replace host call. READY is **not PLAYING**. PLAYING/ENDED are observed only with:
existing FileClient load_acknowledged proof (epoch/channel, generation, domain,
profile, verified Main PID/start identity, index=1, target path, transfer success)
AND status v2 session=uint32(baseline+1) / real PLAYING or ENDED. A former session
57 cannot be used to reject a fresh new-RBF session 1. Missing telemetry cannot
revert PLAYING/ENDED to READY within the same generation. FATAL is displayed as
FAILED. Leaving MEGAVGM publishes STOPPED (FAILURE publishes FAILED).

All extra reads/publications are observations. They do not invoke control
commands; their success/failure is ignored by the transport engine. write_reply
remains immediately after owner.tick; telemetry is not an acceptance barrier.
The fading() accessor returns existing flags and is not used in control logic.

Remote validates the optional group atomically; absence is legacy-compatible.
JSON `transport` uses epoch, switchGeneration, switchState, currentProfile,
requiredProfile, domain, baseline, profileChanged, path. uint64 fields use decimal
strings to avoid JavaScript rounding. Unknown future status keys remain tolerated;
malformed/partial known groups, duplicates and invalid enums fail validation.

Frontend uses this receipt for labels only, independent of 6db875e PlayOperation.
Same-profile requests never say Switching. Different-profile PARKED/FADING/
SWITCHING/READY show Switching; authoritative PLAYING/ENDED/STOPPED/FAILED end it.
Older generations/epochs/polls and late active records cannot resurrect retired
receipts. Local Play/Next/Previous/Stop/Exit retire old display ownership without
changing the commands they send. No timer, path or chip inference is used.

PROFILE_A label: "YM2151 / SegaPCM family" (also includes actual supported
YM2612/PSG/YM2203 commands; not a claim that every track uses YM2151).
PROFILE_B label: "YM2610B". Only current_profile selects this label.

Host tests cover state projection/fresh sessions/no Runtime calls, atomic export,
full existing Supervisor/Phase2A/Playlist corpus tests. Remote tests cover optional
group validation and exact uint64 passthrough. Frontend pure/DOM tests cover both
same-profile paths, A/B transitions, stale generations/epochs, Stop/failure and
existing cold short-track/late-HTTP/100-play regressions. Hardware not yet tested.
