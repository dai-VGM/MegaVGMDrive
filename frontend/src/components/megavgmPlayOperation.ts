import type { MegaVGMStatus } from "../lib/models";
import type { PendingMegaVGMSelection } from "./megavgmView";
import { PLAY_PENDING_TIMEOUT_MS } from "./megavgmView";

export type PlayDisposition =
  | "pending"
  | "completed"
  | "advanced"
  | "superseded"
  | "invalidated"
  | "failed";

// Frontend receipt only; never grants controller/queue ownership.
export interface PlayOperation extends PendingMegaVGMSelection {
  disposition: PlayDisposition;
  selectedSession?: number;
  selectedPlayingObserved: boolean;
  lastPollStartedMs?: number;
  playbackProgressObserved: boolean;
  message?: string;
}

export type PlayOperationEvent =
  | { type: "observe"; status?: MegaVGMStatus }
  | { type: "accept"; requestId: number; atMs: number; path: string }
  | { type: "fail"; requestId: number; message: string }
  | { type: "expire"; requestId: number; atMs: number }
  | { type: "supersede" };

export function beginPlayOperation(
  intent: PendingMegaVGMSelection
): PlayOperation {
  return {
    ...intent,
    disposition: "pending",
    selectedPlayingObserved: false,
    playbackProgressObserved: false,
  };
}

export function playOperationRemaining(
  operation: PlayOperation,
  nowMs: number
): number {
  // Bounded UX even if HTTP never settles. Acceptance does not restart the clock.
  return Math.max(
    0,
    PLAY_PENDING_TIMEOUT_MS - (nowMs - operation.requestedAtMs)
  );
}

export function reducePlayOperation(
  operation: PlayOperation,
  event: PlayOperationEvent
): PlayOperation {
  if ("requestId" in event && event.requestId !== operation.requestId)
    return operation;
  if (event.type === "supersede") {
    return { ...operation, disposition: "superseded", message: undefined };
  }
  if (event.type === "observe") {
    // Failed/expired receipts may have their message reconciled by later truth,
    // but can never become pending again. Superseded generations stay retired.
    if (["completed", "advanced", "superseded"].includes(operation.disposition))
      return operation;
    const s = event.status;
    const poll = s?.clientPollStartedMs;
    if (
      !s ||
      poll === undefined ||
      poll < operation.requestedAtMs ||
      poll <= (operation.lastPollStartedMs ?? -Infinity)
    )
      return operation;
    let next = { ...operation, lastPollStartedMs: poll };
    const session = s.session;
    const active = s.mode === "MEGAVGM" && s.controllerRunning;
    const newSession =
      typeof session === "number" &&
      (operation.baselineSession === undefined
        ? session > 0
        : session !== operation.baselineSession);
    const contextMatches =
      operation.expectedPlaylist === undefined ||
      (s.context === "PLAYLIST" && s.playlist === operation.expectedPlaylist);
    const targetMatches =
      contextMatches &&
      s.path === operation.path &&
      (operation.expectedPlaylistIndex === undefined ||
        s.index === operation.expectedPlaylistIndex + 1);
    if (
      active &&
      newSession &&
      targetMatches &&
      (s.state === "LOADING" || s.state === "PLAYING")
    ) {
      next = {
        ...next,
        selectedSession: session,
        playbackProgressObserved: true,
      };
      if (s.state === "PLAYING") {
        return {
          ...next,
          disposition: "completed",
          selectedPlayingObserved: true,
          message: undefined,
        };
      }
    }
    const selectedEnded =
      operation.selectedSession !== undefined &&
      session === operation.selectedSession &&
      (s.state === "ENDED" || s.state === "COMPLETE");
    const selectedAdvanced =
      operation.selectedSession !== undefined &&
      typeof session === "number" &&
      session !== operation.selectedSession &&
      (s.state === "LOADING" || s.state === "PLAYING");
    // We missed the selected PLAYING window. This is UI retirement, NOT proof
    // that the requested track played. No index+1 assumption (shuffle/repeat).
    const missedShortTrack =
      active &&
      contextMatches &&
      newSession &&
      s.state === "PLAYING" &&
      s.path !== undefined &&
      s.path !== operation.path;
    if (selectedEnded || (active && selectedAdvanced) || missedShortTrack) {
      return {
        ...next,
        disposition: "advanced",
        playbackProgressObserved: true,
        message: undefined,
      };
    }
    // Ignore STOCK/STARTING bootstrap snapshots before acceptance. Explicit
    // Stop/Next/Exit already synchronously supersede the receipt at the UI.
    if (
      s.state === "FATAL" ||
      s.state === "STOPPED" ||
      s.state === "COMPLETE" ||
      (operation.acceptedAtMs !== undefined &&
        poll >= operation.acceptedAtMs &&
        (s.mode === "STOCK" ||
          s.mode === "FAILURE" ||
          s.mode === "SHUTTING_DOWN"))
    ) {
      return { ...next, disposition: "invalidated", message: undefined };
    }
    return next;
  }
  if (
    event.type === "fail" &&
    operation.disposition === "invalidated" &&
    !operation.playbackProgressObserved
  ) {
    // A real HTTP rejection after UX expiry is still an error, not a spinner.
    return { ...operation, disposition: "failed", message: event.message };
  }
  // Terminal receipts ignore late HTTP success/error; they never resurrect a row.
  if (operation.disposition !== "pending") return operation;
  if (event.type === "accept") {
    return { ...operation, acceptedAtMs: event.atMs, path: event.path };
  }
  if (event.type === "fail") {
    return { ...operation, disposition: "failed", message: event.message };
  }
  if (
    event.type === "expire" &&
    playOperationRemaining(operation, event.atMs) === 0
  ) {
    // No assertion that playback failed merely because a poll/ack was missed.
    return { ...operation, disposition: "invalidated", message: undefined };
  }
  return operation;
}
