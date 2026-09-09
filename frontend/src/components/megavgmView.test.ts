import { MegaVGMStatus } from "../lib/models";
import {
  browseEntryDisabled,
  lifecycleControls,
  megaVGMView,
  navigationEnabled,
  pendingTimeoutRemaining,
  pendingSelectionResolution,
  PLAY_PENDING_TIMEOUT_MS,
  playbackObservationTiming,
  playRequestIsCurrent,
  lifecycleRequestSucceeded,
  selectionHasStarted,
  stopEnabled,
} from "./megavgmView";

const base: MegaVGMStatus = {
  mode: "STOCK",
  main: "STOCK",
  supervisorController: "STOPPED",
  controllerRunning: false,
};

function assert(condition: boolean, message: string): void {
  if (!condition) {
    throw new Error(message);
  }
}

assert(megaVGMView(base) === "stock", "STOCK must render the Start view");
assert(
  lifecycleControls("stock", false, false).showStart,
  "STOCK must show Start"
);
assert(
  !lifecycleControls("stock", true, false).startEnabled,
  "Start must be disabled while pending"
);
assert(
  megaVGMView({ ...base, mode: "STARTING", main: "STOPPED" }) === "starting",
  "STARTING must render progress"
);
const active: MegaVGMStatus = {
  ...base,
  mode: "MEGAVGM",
  main: "MODIFIED",
  supervisorController: "RUNNING",
  controllerRunning: true,
  state: "PLAYING",
  path: "/media/fat/MegaVGMDrive/Album/03 Selected.vgm",
  session: 27,
};
assert(megaVGMView(active) === "active", "MEGAVGM must render Now Playing");
assert(
  lifecycleRequestSucceeded(active, "start"),
  "authoritative active status must reconcile a late Start response"
);
assert(
  lifecycleRequestSucceeded(base, "exit"),
  "authoritative STOCK status must reconcile a late Exit response"
);
assert(
  !lifecycleRequestSucceeded(base, "start") &&
    !lifecycleRequestSucceeded(active, "exit"),
  "lifecycle errors must not clear before authoritative convergence"
);
assert(
  !selectionHasStarted(active, {
    requestId: 1,
    path: active.path || "",
    baselineSession: active.session,
    requestedAtMs: 100,
  }),
  "unchanged session must not complete Browse selection"
);
assert(
  selectionHasStarted(
    { ...active, context: "PLAYLIST", playlist: "Favorites", index: 1 },
    {
      requestId: 11,
      path: active.path || "",
      baselineSession: active.session,
      expectedPlaylist: "Favorites",
      expectedPlaylistIndex: 0,
      requestedAtMs: 100,
    }
  ),
  "exact controller playlist adoption must resolve without a duplicate load"
);
assert(
  selectionHasStarted(
    { ...active, session: (active.session || 0) + 1 },
    {
      requestId: 2,
      path: active.path || "",
      baselineSession: active.session,
      requestedAtMs: 100,
    }
  ),
  "matching path with a new session must complete Browse selection"
);
assert(
  !selectionHasStarted(
    { ...active, state: "LOADING", session: (active.session || 0) + 1 },
    {
      requestId: 3,
      path: active.path || "",
      baselineSession: active.session,
      requestedAtMs: 100,
    }
  ),
  "LOADING must not be presented as successful playback"
);
assert(
  lifecycleControls("active", false, false).showExit,
  "MEGAVGM must show Exit"
);
assert(
  navigationEnabled(active, false),
  "NEXT/PREV must remain enabled while playing"
);
assert(!navigationEnabled(active, true), "pending controls must be disabled");
const stopped = { ...active, state: "STOPPED" };
assert(
  navigationEnabled(stopped, false),
  "NEXT/PREV must remain enabled while stopped"
);
assert(stopEnabled(active, false), "STOP must be enabled while playing");
assert(
  stopEnabled({ ...active, state: "LOADING" }, false),
  "STOP must be available during an owned track load"
);
assert(!stopEnabled(stopped, false), "STOP must be disabled while stopped");
assert(
  !browseEntryDisabled("directory", "Album", "Album/03 Selected.vgm"),
  "Browse directories must remain enabled while Play is pending"
);
assert(
  !browseEntryDisabled("file", "Album/04 Another.vgm", "Album/03 Selected.vgm"),
  "unselected VGM rows must remain enabled while Play is pending"
);
assert(
  browseEntryDisabled("file", "Album/03 Selected.vgm", "Album/03 Selected.vgm"),
  "only the selected VGM row may be disabled while pending"
);
assert(
  !playRequestIsCurrent(4, 5) && playRequestIsCurrent(5, 5),
  "newer selection must supersede stale request callbacks"
);
const timing = playbackObservationTiming(
  {
    ...active,
    session: (active.session || 0) + 1,
    statusFileMtimeUnixMs: 10_000,
    statusReadUnixMs: 10_320,
    clientPollStartedMs: 700,
    clientPollReceivedMs: 712,
  },
  {
    requestId: 4,
    path: active.path || "",
    baselineSession: active.session,
    requestedAtMs: 100,
    acceptedAtMs: 250,
  },
  715
);
assert(!!timing, "matching owned session must produce timing diagnostics");
assert(
  timing?.requestToObservedMs === 615 &&
    timing.acceptedToObservedMs === 465 &&
    timing.statusFileToBackendMs === 320 &&
    timing.pollRoundTripMs === 12 &&
    timing.frontendApplyMs === 3,
  `unexpected playback timing: ${JSON.stringify(timing)}`
);

const delayedPending = {
  requestId: 5,
  path: "/media/fat/MegaVGMDrive/Other/Cross Directory.vgm",
  baselineSession: active.session,
  baselineIndex: active.index,
  requestedAtMs: 1000,
  acceptedAtMs: 1100,
};
assert(
  pendingSelectionResolution(
    {
      ...active,
      state: "LOADING",
      path: delayedPending.path,
      session: (active.session || 0) + 1,
      clientPollReceivedMs: 1200,
    },
    delayedPending,
    1201
  ) === "pending",
  "delayed PLAYING must keep only the selected row pending"
);
assert(
  pendingSelectionResolution(
    {
      ...active,
      path: delayedPending.path,
      session: (active.session || 0) + 4,
      index: 9,
      clientPollReceivedMs: 1300,
    },
    delayedPending,
    1301
  ) === "playing",
  "a direct PLAYING snapshot with a session jump must resolve pending"
);
assert(
  pendingSelectionResolution(
    {
      ...active,
      path: delayedPending.path,
      session: (active.session || 0) + 1,
      clientPollReceivedMs: 1050,
    },
    delayedPending,
    1101
  ) === "playing",
  "PLAYING cached before POST bookkeeping must resolve after pending registers"
);
assert(
  pendingSelectionResolution(
    active,
    delayedPending,
    1100 + PLAY_PENDING_TIMEOUT_MS
  ) === "timed_out",
  "accepted Play without confirmation must time out"
);
assert(
  pendingTimeoutRemaining(
    {
      ...delayedPending,
      requestedAtMs: 0,
      acceptedAtMs: undefined,
    },
    PLAY_PENDING_TIMEOUT_MS + 1000
  ) === undefined,
  "status timeout must not run while the Play HTTP request is pending"
);
assert(
  pendingTimeoutRemaining(
    { ...delayedPending, requestedAtMs: 0, acceptedAtMs: 9000 },
    9001
  ) ===
    PLAY_PENDING_TIMEOUT_MS - 1,
  "status timeout must begin when the backend accepts the request"
);
assert(
  pendingSelectionResolution(
    {
      ...active,
      mode: "STOCK",
      main: "STOCK",
      supervisorController: "STOPPED",
      controllerRunning: false,
      clientPollReceivedMs: 1200,
    },
    delayedPending,
    1201
  ) === "controller_stopped",
  "controller stop must release pending UI"
);

let stressStatus = active;
for (let track = 0; track < 25; track += 1) {
  const samePathReplay = track > 0 && track % 7 === 0;
  const path = samePathReplay
    ? stressStatus.path || ""
    : `/media/fat/MegaVGMDrive/${track % 2 ? "Disc_B" : "Disc_A"}/${String(
        track
      ).padStart(2, "0")} Track.vgm`;
  const stressPending = {
    requestId: 100 + track,
    path,
    baselineSession: stressStatus.session,
    baselineIndex: stressStatus.index,
    requestedAtMs: 2000 + track * 100,
    acceptedAtMs: 2010 + track * 100,
  };
  stressStatus = {
    ...stressStatus,
    state: "PLAYING",
    path,
    index: track + 1,
    session: (stressStatus.session || 0) + (track % 3) + 1,
    clientPollReceivedMs: 2050 + track * 100,
  };
  assert(
    pendingSelectionResolution(
      stressStatus,
      stressPending,
      2051 + track * 100
    ) === "playing",
    `sequential Browse Play ${track + 1} did not resolve`
  );
}
assert(
  megaVGMView({ ...base, mode: "SHUTTING_DOWN", main: "STOPPED" }) ===
    "restoring",
  "SHUTTING_DOWN must render restore progress"
);
assert(
  megaVGMView(undefined) === "unavailable",
  "disconnect must render reconnecting"
);
assert(
  megaVGMView(active) === "active",
  "reconnect must recover the active view"
);
