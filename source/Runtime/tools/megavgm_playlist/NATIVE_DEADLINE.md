# Phase 3.3 native metadata deadline — isolated Host candidate

User-approved policy extension (2026-10-14); production HOLD. No FPGA, shared
Transport, Main, PWA or audio Core change. Hardware NOT_RUN.

The owned preparer emits an optional NATIVE_TIMING_V1 receipt after its existing
path response, on --timing-receipt only. It comes from the same strictly admitted,
selected image and verified immutable source/cache publication. The legacy
path-only and inspect outputs are unchanged. Controller accepts this result only
from its active preparation process; cancellation/retarget destroys the receipt.

NSFe signed milliseconds map to physical tracks, not plst positions. Missing,
short-array or negative time means no automatic end. Zero time is valid. Missing
or negative fade uses this player's explicit interim default of 100ms; zero fade
is preserved. NSF1 does not gain a deadline.

End target = time + resolved fade, uint64. Request delay from first owned PLAYING
= max(target - 100ms, 0). Existing immutable MV02/02 FADE_ONLY is sent once through
Runtime.issue_stop (wire transport only). It does NOT enter the user's Stop branch,
publish STOPPED or synthesize ENDED. Current owned session ENDED must be read before
the existing PlaybackTraversal and SwitchOwner may advance. Stop/Next wins over
expiry; local timer lifetime cannot cross reload. A fresh Main identity/domain/lease
load ACK is checked before expiry. Missing ENDED fails at the existing Stop timeout.

This matches the user's requested END-TARGET approximation, not the metadata fade
envelope. E.g. time 89000 + fade1850 => request at90750ms, existing100ms ramp,
end target90850ms. For targets <100ms, earliest fade request is immediate and the
hardware tail still takes about100ms. Poll interval, first PLAYING observation and
Main transfer/Status delays remain observable. No sample-exact claim.

Repeat/Shuffle/PREV retain existing traversal. A finite timed track in ONE ends
and reloads the same item; planned total under ONE still displays INFINITE per the
current presentation contract. OFF/ALL publish max(metadata target,100ms), reflecting the minimum hardware tail, with explicit
NATIVE_METADATA_END_TARGET_100MS_FADE_APPROXIMATION source. Unknown-time NSF/NSFe
remains unchanged. Timer metadata is separate from display-only PlaybackTiming.

Owner scope: Controller invocation + track iteration + generation + FPGA session;
existing profile lease checks add domain, Main identity and acknowledgment path.
There are no callbacks, background timers, new queue or independent fade owner.
The unchanged four-byte FPGA control has no session token: external arbitrary
index-1 loads racing an already submitted command are outside the serialized
Controller guarantee and still need hardware observation. Host checks do not
claim a new atomically session-tagged FPGA ABI.

Reference: https://www.nesdev.org/wiki/NSFe (time/fade/plst). The numerical default
is a player policy, not a format-mandated value.

Regression: existing Phase2A real Controller/SwitchOwner suite plus boundary,
missing/zero/max, same-session ENDED, no-END timeout, Stop/Next during fade, Reload,
stale-session/lease loss, failure, ONE/ALL/Shuffle and E-to-F cases. Native receipt
parser and actual Go preparer with a read-only original NSFe are also tested.
Mutation negatives remove generation/session matching, single-send, correct end
request offset, and unknown-time disabling. All must compile and be detected.

Use existing tools/megavgm_profile/build_and_test.sh with
MEGAVGM_HOST_MSM6295=1 and host/arm modes. Legacy playlist/run_host_tests.sh is not
a Phase2A runner: its non-Phase2A compile already lacks profile types at the fixed
base. Do not change production code to make that obsolete compile path pass.
New package/source identities replace none of the accepted fixed bytes. Deployment,
RBF switching, hardware acceptance and production promotion need separate scope.
