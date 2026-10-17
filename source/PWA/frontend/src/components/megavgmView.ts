import { MegaVGMStatus } from "../lib/models";

export type MegaVGMView =
  | "stock"
  | "starting"
  | "active"
  | "restoring"
  | "failure"
  | "unavailable";

export function megaVGMView(status?: MegaVGMStatus): MegaVGMView {
  if (!status) {
    return "unavailable";
  }
  switch (status.mode) {
    case "STOCK":
      return "stock";
    case "STARTING":
      return "starting";
    case "MEGAVGM":
      return "active";
    case "SHUTTING_DOWN":
      return "restoring";
    default:
      return "failure";
  }
}

export function navigationEnabled(
  status: MegaVGMStatus | undefined,
  mutationPending: boolean
): boolean {
  return (
    status?.mode === "MEGAVGM" &&
    status.controllerRunning &&
    (status.state === "PREPARING" ||
      status.state === "PLAYING" ||
      status.state === "STOPPED") &&
    !mutationPending
  );
}

export function stopEnabled(
  status: MegaVGMStatus | undefined,
  mutationPending: boolean
): boolean {
  return (
    status?.mode === "MEGAVGM" &&
    status.controllerRunning &&
    (status.state === "PREPARING" ||
      status.state === "LOADING" ||
      status.state === "PLAYING") &&
    !mutationPending
  );
}

export function lifecycleControls(
  view: MegaVGMView,
  startPending: boolean,
  exitPending: boolean
) {
  return {
    showStart: view === "stock",
    startEnabled: view === "stock" && !startPending,
    showExit: view === "active",
    exitEnabled: view === "active" && !exitPending,
  };
}

export interface PendingMegaVGMSelection {
  requestId: number;
  path: string;
  baselineSession?: number;
  baselineIndex?: number;
  baselineTransportEpoch?: string;
  baselineSwitchGeneration?: string;
  expectedPlaylist?: string;
  expectedPlaylistIndex?: number;
  requestedAtMs: number;
  acceptedAtMs?: number;
}

export const PLAY_PENDING_TIMEOUT_MS = 8000;

export function pendingTimeoutRemaining(
  pending: PendingMegaVGMSelection | undefined,
  observedAtMs: number,
  timeoutMs = PLAY_PENDING_TIMEOUT_MS
): number | undefined {
  if (pending?.acceptedAtMs === undefined) {
    return undefined;
  }
  return Math.max(0, timeoutMs - (observedAtMs - pending.acceptedAtMs));
}

export type PendingSelectionResolution =
  | "pending"
  | "playing"
  | "controller_stopped"
  | "timed_out";

export interface PlaybackObservationTiming {
  requestToObservedMs: number;
  acceptedToObservedMs?: number;
  statusFileToBackendMs?: number;
  pollRoundTripMs?: number;
  frontendApplyMs?: number;
}

export function lifecycleRequestSucceeded(
  status: MegaVGMStatus | undefined,
  operation: "start" | "exit"
): boolean {
  if (!status) return false;
  if (operation === "start") {
    return (
      status.mode === "MEGAVGM" &&
      status.main === "MODIFIED" &&
      status.controllerRunning
    );
  }
  return status.mode === "STOCK" && status.main === "STOCK";
}

export function browseEntryDisabled(
  type: "file" | "directory",
  entryPath: string,
  selectedPlayPath: string | undefined
): boolean {
  return type === "file" && entryPath === selectedPlayPath;
}

export function playRequestIsCurrent(
  requestId: number,
  latestRequestId: number
): boolean {
  return requestId === latestRequestId;
}

export function selectionHasStarted(
  status: MegaVGMStatus | undefined,
  pending: PendingMegaVGMSelection | undefined
): boolean {
  if (!status || !pending || status.mode !== "MEGAVGM") {
    return false;
  }
  const sessionAdvanced =
    pending.baselineSession === undefined ||
    status.session !== pending.baselineSession;
  const exactPlaylistAdoption =
    pending.expectedPlaylist !== undefined &&
    pending.expectedPlaylistIndex !== undefined &&
    status.context === "PLAYLIST" &&
    status.playlist === pending.expectedPlaylist &&
    status.index === pending.expectedPlaylistIndex + 1;
  return (
    status.controllerRunning &&
    status.state === "PLAYING" &&
    status.path === pending.path &&
    typeof status.session === "number" &&
    (sessionAdvanced || exactPlaylistAdoption)
  );
}

export function pendingSelectionResolution(
  status: MegaVGMStatus | undefined,
  pending: PendingMegaVGMSelection | undefined,
  observedAtMs: number,
  timeoutMs = PLAY_PENDING_TIMEOUT_MS
): PendingSelectionResolution {
  if (!pending) {
    return "pending";
  }
  if (selectionHasStarted(status, pending)) {
    return "playing";
  }
  const pendingSince = pending.acceptedAtMs ?? pending.requestedAtMs;
  if (observedAtMs - pendingSince >= timeoutMs) {
    return "timed_out";
  }
  const snapshotIsNewerThanAcceptance =
    pending.acceptedAtMs !== undefined &&
    status?.clientPollReceivedMs !== undefined &&
    status.clientPollReceivedMs >= pending.acceptedAtMs;
  if (
    snapshotIsNewerThanAcceptance &&
    status &&
    (status.mode !== "MEGAVGM" || !status.controllerRunning)
  ) {
    return "controller_stopped";
  }
  return "pending";
}

function elapsed(later: number | undefined, earlier: number | undefined) {
  if (later === undefined || earlier === undefined || later < earlier) {
    return undefined;
  }
  return later - earlier;
}

export function playbackObservationTiming(
  status: MegaVGMStatus | undefined,
  pending: PendingMegaVGMSelection | undefined,
  observedAtMs: number
): PlaybackObservationTiming | undefined {
  if (!status || !pending || !selectionHasStarted(status, pending)) {
    return undefined;
  }
  return {
    requestToObservedMs: observedAtMs - pending.requestedAtMs,
    acceptedToObservedMs: elapsed(observedAtMs, pending.acceptedAtMs),
    statusFileToBackendMs: elapsed(
      status.statusReadUnixMs,
      status.statusFileMtimeUnixMs
    ),
    pollRoundTripMs: elapsed(
      status.clientPollReceivedMs,
      status.clientPollStartedMs
    ),
    frontendApplyMs: elapsed(observedAtMs, status.clientPollReceivedMs),
  };
}

// Generic resource error presentation; no profile/Engine policy or state.
export const RESOURCE_CAPACITY_MESSAGE =
  "This track exceeds the core's PCM memory capacity and cannot be played.";
export function resourceRejectionMessage(status: MegaVGMStatus | undefined, pending = false): string | undefined {
  if (!pending && status?.mode === "MEGAVGM" && status.controllerRunning &&
      status.state === "STOPPED" && status.detail?.startsWith("TRACK_LOAD_REJECTED: ")) {
    const reason = status.detail.slice("TRACK_LOAD_REJECTED: ".length);
    return reason.startsWith("resource_capacity_exceeded: ")
      ? RESOURCE_CAPACITY_MESSAGE
      : `This track could not be loaded. ${reason.slice(reason.indexOf(": ") + 2)}`;
  }
  return !pending && status?.mode === "STOCK" && !status.controllerRunning &&
    status.detail === "STOCK MISTER RESTORED: resource_capacity_exceeded"
    ? RESOURCE_CAPACITY_MESSAGE : undefined;
}
export function playFailureMessage(error: unknown, fallback: string): string {
  const value = error as { response?: { data?: { error?: unknown } } } | undefined;
  return value?.response?.data?.error === "resource_capacity_exceeded"
    ? RESOURCE_CAPACITY_MESSAGE : fallback;
}
