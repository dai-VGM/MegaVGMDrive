import {
  emptyTransportDisplay,
  observeTransport,
  invalidateTransport,
} from "./megavgmTransportDisplay";
import { playbackContextLabel } from "./megavgmPresentation";
import type { MegaVGMStatus, MegaVGMTransportStatus } from "../lib/models";
function assert(v: unknown, message: string) {
  if (!v) throw new Error(message);
}
let clock = 0;
const t: MegaVGMTransportStatus = {
  epoch: "megavgm-phase2a.abc",
  switchGeneration: "7",
  switchState: "FADING",
  currentProfile: "PROFILE_A",
  requiredProfile: "PROFILE_B",
  domain: "1",
  baseline: 57,
  profileChanged: true,
  path: "/media/fat/MegaVGMDrive/Night_Striker/01 Coin.vgm",
};
const status = (transport: MegaVGMTransportStatus): MegaVGMStatus => ({
  transport,
  mode: "MEGAVGM",
  main: "MODIFIED",
  supervisorController: "RUNNING",
  controllerRunning: true,
  state: "LOADING",
  playlist: "Favorites",
  context: "PLAYLIST",
  index: 4,
  count: 10,
  clientPollStartedMs: ++clock,
});
for (const profile of [
  "PROFILE_A",
  "PROFILE_B",
  "PROFILE_C",
  "PROFILE_D",
] as const) {
  const s = status({
    ...t,
    currentProfile: profile,
    requiredProfile: profile,
    profileChanged: false,
    switchState: "READY",
  });
  assert(
    !observeTransport(emptyTransportDisplay(), s).switching,
    "same-profile must remain Loading"
  );
}
for (const [from, to] of [
  ["PROFILE_A", "PROFILE_B"],
  ["PROFILE_B", "PROFILE_A"],
  ["PROFILE_A", "PROFILE_C"],
  ["PROFILE_C", "PROFILE_B"],
  ["PROFILE_B", "PROFILE_C"],
  ["PROFILE_C", "PROFILE_A"],
  ["PROFILE_C", "PROFILE_D"],
  ["PROFILE_D", "PROFILE_A"],
  ["PROFILE_A", "PROFILE_D"],
  ["PROFILE_D", "PROFILE_C"],
] as const) {
  let display = emptyTransportDisplay();
  for (const state of ["FADING", "SWITCHING", "PARKED", "READY"] as const) {
    display = observeTransport(
      display,
      status({
        ...t,
        currentProfile: state === "READY" ? to : from,
        requiredProfile: to,
        switchState: state,
      })
    );
    assert(display.switching, `${state} switching missing`);
  }
  display = observeTransport(display, {
    ...status({
      ...t,
      currentProfile: to,
      requiredProfile: to,
      domain: "2",
      baseline: 0,
      switchState: "PLAYING",
    }),
    state: "PLAYING",
    session: 1,
  });
  assert(!display.switching, "fresh session 1 after 57 clears Switching");
  display = observeTransport(display, status(t));
  assert(
    !display.switching && display.receipt?.currentProfile === to,
    "late same-generation active receipt cannot revive or regress profile"
  );
}
let d = observeTransport(emptyTransportDisplay(), status(t));
d = invalidateTransport(d);
d = observeTransport(d, status(t));
assert(!d.switching, "Stop/Next invalidation remains retired");
d = observeTransport(d, status({ ...t, switchGeneration: "8" }));
assert(d.switching, "new generation is observable");
d = observeTransport(d, status(t));
assert(d.receipt?.switchGeneration === "8", "late previous generation ignored");
d = observeTransport(
  d,
  status({ ...t, switchGeneration: "8", switchState: "FAILED" })
);
assert(d.failed && !d.switching, "failure shown without spinner");
d = invalidateTransport(d);
d = observeTransport(
  d,
  status({ ...t, switchGeneration: "8", switchState: "FAILED" })
);
assert(!d.failed, "dismissed failure cannot revive");
d = observeTransport(
  d,
  status({ ...t, epoch: "megavgm-phase2a.new", switchGeneration: "1" })
);
assert(d.switching, "new ENTER epoch can reset generation");
d = observeTransport(d, status({ ...t, switchGeneration: "999" }));
assert(d.receipt?.epoch === "megavgm-phase2a.new", "late old epoch ignored");
d = observeTransport(d, { ...status(d.receipt!), state: "STOPPED" });
assert(!d.switching, "authoritative Stop clears spinner");
assert(
  playbackContextLabel({
    ...status({ ...t, currentProfile: "PROFILE_B" }),
    soundChips: ["YM2610B"],
  }) === "Favorites · YM2610B · 4/10",
  "queue source/profile/index"
);
assert(
  playbackContextLabel({
    ...status({
      ...t,
      currentProfile: "PROFILE_C",
      requiredProfile: "PROFILE_C",
    }),
    soundChips: ["SID 6581"],
  }) === "Favorites · SID 6581 · 4/10",
  "SID chip label comes from track metadata"
);
assert(
  playbackContextLabel(status({ ...t, currentProfile: "PROFILE_B" })) ===
    "Favorites · 4/10",
  "resident profile must never substitute for missing track-chip evidence"
);
assert(
  !observeTransport(emptyTransportDisplay(), {
    ...status(t),
    transport: undefined,
  }).switching,
  "legacy producer remains supported"
);
console.log(
  "Transport display A/B/C/D same/cross-profile, stale generations/epochs, Stop/error, profile/source: PASS"
);
