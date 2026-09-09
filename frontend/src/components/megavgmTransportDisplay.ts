import type { MegaVGMStatus, MegaVGMTransportStatus } from "../lib/models";

export interface TransportDisplay {
  receipt?: MegaVGMTransportStatus;
  pollStarted: number;
  retired: boolean;
  oldEpochs: string[];
  switching: boolean;
  failed: boolean;
}
export const emptyTransportDisplay = (): TransportDisplay => ({
  pollStarted: -1,
  retired: false,
  oldEpochs: [],
  switching: false,
  failed: false,
});
const compareGeneration = (a: string, b: string) =>
  a.length - b.length || a.localeCompare(b);

// Display receipt ONLY. Never dispatches, retries, changes a PlayOperation or
// treats a later track as proof that an earlier Play request succeeded.
export function observeTransport(
  previous: TransportDisplay,
  status?: MegaVGMStatus
): TransportDisplay {
  if (!status) return previous;
  const stamp = status.clientPollStartedMs ?? 0;
  if (stamp < previous.pollStarted) return previous;
  const t = status.transport;
  if (!t)
    return { ...previous, pollStarted: stamp, switching: false, failed: false };
  const old = previous.receipt;
  if (
    previous.oldEpochs.includes(t.epoch) ||
    (old?.epoch === t.epoch &&
      compareGeneration(t.switchGeneration, old.switchGeneration) < 0)
  )
    return previous;
  const same =
    old?.epoch === t.epoch && old.switchGeneration === t.switchGeneration;
  const terminal = ["IDLE", "PLAYING", "ENDED", "STOPPED", "FAILED"].includes(
    t.switchState
  );
  if (
    same &&
    old &&
    ["PLAYING", "ENDED", "STOPPED", "FAILED"].includes(old.switchState) &&
    !terminal
  )
    return previous;
  const stopped =
    status.mode !== "MEGAVGM" ||
    !status.controllerRunning ||
    status.state === "STOPPED" ||
    status.state === "FATAL";
  const retired = (same && previous.retired) || terminal || stopped;
  return {
    receipt: t,
    pollStarted: stamp,
    retired,
    oldEpochs:
      old && old.epoch !== t.epoch
        ? [...previous.oldEpochs, old.epoch]
        : previous.oldEpochs,
    switching: !retired && t.profileChanged,
    failed:
      !stopped &&
      t.switchState === "FAILED" &&
      !(same && previous.retired && !previous.failed),
  };
}

export function invalidateTransport(
  display: TransportDisplay
): TransportDisplay {
  return { ...display, retired: true, switching: false, failed: false };
}
