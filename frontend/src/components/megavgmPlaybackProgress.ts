import type { MegaVGMStatus } from "../lib/models";

export interface PlaybackTelemetry {
  session?: number;
  path?: string;
  state?: string;
  elapsedMs: number;
  plannedDurationKind: "UNKNOWN" | "FINITE" | "INFINITE";
  plannedDurationMs?: number;
  durationSource?: string;
  pollStartedMs: number;
  receivedMs: number;
}

export interface PlaybackProgress {
  elapsedMs: number;
  elapsedLabel: string;
  totalLabel: string;
  determinate: boolean;
  fraction: number;
  kind: PlaybackTelemetry["plannedDurationKind"];
}

const MAX_INTERPOLATION_MS = 1500;

export function observePlaybackTelemetry(
  current: PlaybackTelemetry | undefined,
  status: MegaVGMStatus | undefined
): PlaybackTelemetry | undefined {
  if (!status || status.clientPollStartedMs === undefined) return current;
  if (current && status.clientPollStartedMs <= current.pollStartedMs)
    return current;
  const kind = status.plannedDurationKind ?? "UNKNOWN";
  return {
    session: status.session,
    path: status.path,
    state: status.state,
    elapsedMs: Math.max(0, status.elapsedMs ?? 0),
    plannedDurationKind: kind,
    plannedDurationMs:
      kind === "FINITE" && (status.plannedDurationMs ?? 0) > 0
        ? status.plannedDurationMs
        : undefined,
    durationSource: status.durationSource,
    pollStartedMs: status.clientPollStartedMs,
    receivedMs: status.clientPollReceivedMs ?? status.clientPollStartedMs,
  };
}

export function formatPlaybackTime(milliseconds: number): string {
  const totalSeconds = Math.max(0, Math.floor(milliseconds / 1000));
  const seconds = totalSeconds % 60;
  const minutes = Math.floor(totalSeconds / 60) % 60;
  const hours = Math.floor(totalSeconds / 3600);
  return hours > 0
    ? `${hours}:${minutes.toString().padStart(2, "0")}:${seconds
        .toString()
        .padStart(2, "0")}`
    : `${Math.floor(totalSeconds / 60)}:${seconds.toString().padStart(2, "0")}`;
}

export function playbackProgress(
  telemetry: PlaybackTelemetry | undefined,
  nowMs: number,
  loading: boolean
): PlaybackProgress {
  if (!telemetry || loading) {
    return {
      elapsedMs: 0,
      elapsedLabel: "0:00",
      totalLabel: "--:--",
      determinate: false,
      fraction: 0,
      kind: "UNKNOWN",
    };
  }
  let elapsedMs = telemetry.elapsedMs;
  if (telemetry.state === "PLAYING" && nowMs >= telemetry.receivedMs) {
    elapsedMs += Math.min(nowMs - telemetry.receivedMs, MAX_INTERPOLATION_MS);
  }
  const finite =
    telemetry.plannedDurationKind === "FINITE" &&
    telemetry.plannedDurationMs !== undefined;
  const ended = telemetry.state === "ENDED" || telemetry.state === "COMPLETE";
  const fraction = finite
    ? ended
      ? 1
      : Math.max(0, Math.min(1, elapsedMs / telemetry.plannedDurationMs!))
    : 0;
  return {
    elapsedMs,
    elapsedLabel: formatPlaybackTime(elapsedMs),
    totalLabel: finite
      ? formatPlaybackTime(telemetry.plannedDurationMs!)
      : telemetry.plannedDurationKind === "INFINITE"
      ? "∞"
      : "--:--",
    determinate: finite,
    fraction,
    kind: telemetry.plannedDurationKind,
  };
}
