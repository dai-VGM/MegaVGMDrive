import {
  formatPlaybackTime,
  observePlaybackTelemetry,
  playbackProgress,
} from "./megavgmPlaybackProgress";
import type { MegaVGMStatus } from "../lib/models";

function assert(condition: boolean, message: string): void {
  if (!condition) throw new Error(message);
}

const status = (
  session: number,
  poll: number,
  state: string = "PLAYING"
): MegaVGMStatus => ({
  mode: "MEGAVGM",
  main: "MODIFIED",
  supervisorController: "RUNNING",
  controllerRunning: true,
  state,
  session,
  path: `/track-${session}.vgm`,
  elapsedMs: 37000,
  plannedDurationKind: "FINITE",
  plannedDurationMs: 222000,
  clientPollStartedMs: poll,
  clientPollReceivedMs: poll + 20,
});

const observed = observePlaybackTelemetry(undefined, status(1, 1000))!;
const moving = playbackProgress(observed, 1520, false);
assert(moving.elapsedMs === 37500, "PLAYING interpolation missing");
assert(
  moving.elapsedLabel === "0:37" && moving.totalLabel === "3:42",
  "time format"
);
assert(
  moving.determinate && moving.fraction > 0 && moving.fraction < 1,
  "finite progress"
);

const loading = playbackProgress(observed, 1520, true);
assert(
  loading.elapsedMs === 0 && loading.totalLabel === "--:--",
  "loading reset"
);

const next = observePlaybackTelemetry(observed, {
  ...status(2, 2000, "LOADING"),
  elapsedMs: 0,
})!;
assert(next.session === 2 && next.elapsedMs === 0, "session reset");
const stale = observePlaybackTelemetry(next, status(1, 1500))!;
assert(stale.session === 2, "stale telemetry rolled progress back");

const stopped = playbackProgress(
  observePlaybackTelemetry(next, {
    ...status(2, 3000, "STOPPED"),
    elapsedMs: 0,
  }),
  4000,
  false
);
assert(stopped.elapsedMs === 0, "STOPPED must not interpolate");

const ended = playbackProgress(
  observePlaybackTelemetry(next, status(2, 3000, "ENDED")),
  4000,
  false
);
assert(
  ended.elapsedMs === 37000 && ended.fraction === 1,
  "ENDED must freeze and fill"
);

const infinite = playbackProgress(
  observePlaybackTelemetry(undefined, {
    ...status(3, 1000),
    plannedDurationKind: "INFINITE",
    plannedDurationMs: undefined,
  }),
  1020,
  false
);
assert(
  !infinite.determinate && infinite.totalLabel === "∞",
  "Repeat One infinity"
);

const unknown = playbackProgress(
  observePlaybackTelemetry(undefined, {
    ...status(4, 1000),
    plannedDurationKind: "UNKNOWN",
    plannedDurationMs: undefined,
  }),
  1020,
  false
);
assert(
  !unknown.determinate && unknown.totalLabel === "--:--",
  "unknown duration"
);
assert(formatPlaybackTime(3661000) === "1:01:01", "hour formatting");

console.log(
  "authoritative playback progress/interpolation/stale telemetry PASS"
);
