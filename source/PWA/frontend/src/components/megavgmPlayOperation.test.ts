import type { MegaVGMStatus, MegaVGMTransportStatus } from "../lib/models";
import {
  beginPlayOperation,
  reducePlayOperation as step,
  PlayOperation,
} from "./megavgmPlayOperation";

function assert(value: unknown, message: string): asserts value {
  if (!value) throw new Error(message);
}
const path = (n: number) => `/media/fat/MegaVGMDrive/Night Striker/${n}.vgm`;
const start = (id = 1, n = 1, baseline?: number) =>
  beginPlayOperation({
    requestId: id,
    path: path(n),
    baselineSession: baseline,
    requestedAtMs: 100,
    expectedPlaylist: "Favorites",
    expectedPlaylistIndex: n - 1,
  });
const status = (
  n: number,
  session: number,
  poll: number,
  state = "PLAYING"
): MegaVGMStatus => ({
  mode: "MEGAVGM",
  main: "MODIFIED",
  controllerRunning: true,
  supervisorController: "RUNNING",
  path: path(n),
  session,
  index: n,
  count: 10,
  context: "PLAYLIST",
  playlist: "Favorites",
  state,
  clientPollStartedMs: poll,
  clientPollReceivedMs: poll + 10,
});
const observe = (o: PlayOperation, s: MegaVGMStatus) =>
  step(o, { type: "observe", status: s });
const ack = (o: PlayOperation, id = o.requestId) =>
  step(o, { type: "accept", requestId: id, atMs: 5000, path: o.path });
function retired(o: PlayOperation, name: string) {
  assert(o.disposition !== "pending", `${name}: spinner remains`);
  assert(!o.message, `${name}: false error`);
  assert(ack(o) === o, `${name}: late ACK resurrects`);
}
// A/E/J: cold tap, LOADING/PLAYING before HTTP, EOF and multiple auto-nexts.
let o = observe(start(), status(1, 1, 200, "LOADING"));
assert(
  o.selectedSession === 1 && !o.selectedPlayingObserved,
  "record pre-ACK LOADING"
);
o = observe(o, status(1, 1, 500));
assert(
  o.selectedPlayingObserved && o.disposition === "completed",
  "record pre-ACK PLAYING"
);
for (const s of [
  status(1, 1, 600, "ENDED"),
  status(2, 2, 700),
  status(3, 3, 800),
  status(4, 4, 900),
])
  o = observe(o, s);
retired(o, "A cold short / J long first track");
// B/F: ACK first, warm current session must not falsely complete same-path re-play.
o = ack(start(2, 1, 10));
o = observe(o, status(1, 10, 6000));
assert(
  o.disposition === "pending",
  "old warm session must not confirm new play"
);
o = observe(o, status(1, 11, 6100));
o = observe(o, status(2, 12, 6200));
retired(o, "B/F warm");
// C: selected PLAYING entirely missed; cleanup is NOT selected-track success.
o = observe(start(), status(2, 2, 500));
assert(
  o.disposition === "advanced" &&
    !o.selectedPlayingObserved &&
    o.selectedSession === undefined,
  "C: do not fabricate selected PLAYING evidence"
);
retired(o, "C");
// LOADING anchor -> ENDED, or next session, without a selected PLAYING sample.
for (const next of [status(1, 1, 300, "ENDED"), status(2, 2, 300, "LOADING")]) {
  o = observe(observe(start(), status(1, 1, 200, "LOADING")), next);
  assert(
    o.disposition === "advanced" && !o.selectedPlayingObserved,
    "anchor progress"
  );
}
// D: newer intent owns the receipt, even across delayed old success/error.
o = start(5, 5, 3);
assert(ack(o, 1) === o, "D old ACK mutated new generation");
assert(
  step(o, { type: "fail", requestId: 1, message: "old error" }) === o,
  "D old error"
);
// G/H: controls retire receipt synchronously, before any API result.
for (const action of [
  "Next",
  "Previous",
  "Stop",
  "Exit",
  "Refresh",
  "rapid Next",
]) {
  o = step(start(), { type: "supersede" });
  retired(o, action);
  assert(
    step(o, { type: "fail", requestId: 1, message: "late" }) === o,
    action
  );
}
// I: real HTTP failure remains visible; later proven success reconciles it.
o = step(start(), { type: "fail", requestId: 1, message: "Play failed" });
assert(
  o.disposition === "failed" && o.message === "Play failed",
  "I real failure"
);
assert(ack(o) === o, "I late ACK cannot re-arm failure");
o = observe(o, status(1, 1, 300));
retired(o, "I later authoritative success");
// Timeout retires only UX, including never-settling HTTP; no false playback error.
o = step(start(), { type: "expire", requestId: 1, atMs: 8099 });
assert(o.disposition === "pending", "timeout too early");
o = step(o, { type: "expire", requestId: 1, atMs: 8100 });
retired(o, "8s cleanup");
assert(
  step(o, { type: "fail", requestId: 1, message: "real rejection" }).message ===
    "real rejection",
  "actual rejection after UI expiry must remain visible"
);
o = observe(o, status(4, 4, 9000));
retired(o, "late progress after timeout");
// Raw SID preparation is authoritative progress before a new FPGA session.
// It keeps the receipt alive past the ordinary 8s HTTP/loading UX bound, but
// does not fabricate selected-track PLAYING success.
o = observe(start(21, 1, 7), status(1, 7, 200, "PREPARING"));
assert(
  o.disposition === "pending" &&
    o.playbackProgressObserved &&
    !o.selectedPlayingObserved &&
    o.selectedSession === undefined,
  "PREPARING must be progress, not playback success"
);
o = step(o, { type: "expire", requestId: 21, atMs: 9000 });
assert(o.disposition === "pending", "active preparation must not show timeout");
o = observe(o, status(1, 8, 9100, "LOADING"));
o = observe(o, status(1, 8, 9200, "PLAYING"));
retired(o, "raw SID prepare to PLAYING");
// Engine switches rebase the FPGA session counter. The old and new engines may
// both report session=1; the newer authoritative switch generation must retire
// the UI receipt while the raw SID remains the visible identity. The prepared
// cache path is transport-only and must never replace the operation/status path.
const rawSID: string = "/media/fat/MegaVGMDrive/SID/1Volfied.sid";
const cachedSID: string =
  "/media/fat/MegaVGMPlayer/cache/sid/fixture-key.mvgmsid";
const transport = (
  generation: string,
  state: MegaVGMTransportStatus["switchState"],
  currentProfile: MegaVGMTransportStatus["currentProfile"] = "PROFILE_C"
): MegaVGMTransportStatus => ({
  epoch: "megavgm-phase2a.fixture",
  switchGeneration: generation,
  switchState: state,
  currentProfile,
  requiredProfile: "PROFILE_C",
  domain: generation,
  baseline: 0,
  profileChanged: currentProfile !== "PROFILE_C" || state !== "PLAYING",
  path: cachedSID,
});
const rawStatus = (
  poll: number,
  state: string,
  generation: string,
  session = 1,
  context: "DIRECTORY" | "PLAYLIST" = "PLAYLIST"
): MegaVGMStatus => ({
  ...status(1, session, poll, state),
  path: rawSID,
  title: "1Volfied",
  context,
  playlist: context === "PLAYLIST" ? "Favorites" : undefined,
  transport: transport(generation, state === "PLAYING" ? "PLAYING" : "READY"),
});
for (const context of ["PLAYLIST", "DIRECTORY"] as const) {
  o = beginPlayOperation({
    requestId: context === "PLAYLIST" ? 30 : 31,
    path: rawSID,
    baselineSession: 1,
    baselineTransportEpoch: "megavgm-phase2a.fixture",
    baselineSwitchGeneration: "7",
    expectedPlaylist: context === "PLAYLIST" ? "Favorites" : undefined,
    expectedPlaylistIndex: context === "PLAYLIST" ? 0 : undefined,
    requestedAtMs: 100,
  });
  o = observe(o, rawStatus(200, "LOADING", "8", 1, context));
  assert(
    o.disposition === "pending" &&
      o.playbackProgressObserved &&
      o.selectedSession === 1 &&
      o.path === rawSID &&
      o.path !== cachedSID,
    `${context}: rebased LOADING was not anchored to raw SID identity`
  );
  o = step(o, { type: "expire", requestId: o.requestId, atMs: 9100 });
  assert(o.disposition === "pending", `${context}: long load expired`);
  o = observe(o, rawStatus(9200, "PLAYING", "8", 1, context));
  retired(o, `${context}: same-number session rebase`);
}
// Same epoch generations must move forward, not merely differ. A late older
// receipt cannot prove this selection; a new supervisor epoch can.
o = beginPlayOperation({
  requestId: 32,
  path: rawSID,
  baselineSession: 1,
  baselineTransportEpoch: "megavgm-phase2a.fixture",
  baselineSwitchGeneration: "8",
  requestedAtMs: 100,
});
o = observe(o, rawStatus(200, "PLAYING", "7", 1, "DIRECTORY"));
assert(o.disposition === "pending", "older switch generation confirmed Play");
o = observe(o, {
  ...rawStatus(300, "PLAYING", "1", 1, "DIRECTORY"),
  transport: {
    ...transport("1", "PLAYING"),
    epoch: "megavgm-phase2a.successor",
  },
});
retired(o, "new switch epoch with rebased session");
// C->C still uses the ordinary session advance and does not need an RBF reload.
o = beginPlayOperation({
  requestId: 33,
  path: rawSID,
  baselineSession: 1,
  baselineTransportEpoch: "megavgm-phase2a.fixture",
  baselineSwitchGeneration: "8",
  requestedAtMs: 100,
});
o = observe(o, rawStatus(200, "PLAYING", "8", 2, "DIRECTORY"));
retired(o, "C to C session advance");
// Freshness: response to a poll started before tap, and out-of-order polls.
o = observe(start(), status(1, 1, 99));
assert(
  o.disposition === "pending" && !o.selectedPlayingObserved,
  "pre-tap poll accepted"
);
o = observe(o, status(1, 1, 300, "LOADING"));
assert(observe(o, status(1, 1, 200)) === o, "out-of-order poll accepted");
// No cold false stop from bootstrap status; real Stop after receipt clears.
o = observe(start(), {
  mode: "STOCK",
  main: "STOCK",
  controllerRunning: false,
  supervisorController: "STOPPED",
  clientPollStartedMs: 200,
});
assert(o.disposition === "pending", "bootstrap STOCK is not a failure");
retired(observe(o, status(1, 0, 300, "STOPPED")), "controller stop");
// Repeat/shuffle/index wrap: no requirement for exactly index+1 or session+1.
for (let i = 0; i < 100; i++) {
  o = observe(start(i + 1, 1, i * 10), {
    ...status(7, i * 10 + 3, 500),
    shuffle: true,
  });
  assert(
    o.disposition === "advanced" && !o.selectedPlayingObserved,
    "stress skipped snapshot"
  );
  retired(o, `stress ${i}`);
}
console.log(
  "Play operation A-J, freshness, late callbacks, timeout and 100 transitions: PASS"
);
