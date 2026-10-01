import type { MegaVGMStatus } from "../lib/models";

export type MegaVGMTrackRowState = "idle" | "pending" | "playing";

// Never use the currently browsed folder/selected playlist as playback truth.
export function playbackSource(status: MegaVGMStatus): string {
  return status.context === "PLAYLIST"
    ? status.playlist || "Playlist"
    : displayDirectory(status.path);
}

export function playbackContextLabel(status: MegaVGMStatus): string {
  const details = playbackContextDetails(status);
  return details.position
    ? `${details.sourceAndChips} · ${details.position}`
    : details.sourceAndChips;
}

export function playbackContextDetails(status: MegaVGMStatus): {
  sourceAndChips: string;
  position?: string;
} {
  const chips = trackSoundChipLabel(status.soundChips);
  const position =
    status.index !== undefined && status.count !== undefined
      ? `${status.index}/${status.count}`
      : undefined;
  return {
    sourceAndChips: playbackSource(status) + (chips ? ` · ${chips}` : ""),
    position,
  };
}

export function playbackEnginePositionLabel(
  status: MegaVGMStatus
): string | undefined {
  const engine = trackSoundChipLabel(status.soundChips);
  const position =
    status.index !== undefined && status.count !== undefined
      ? `${status.index}/${status.count}`
      : undefined;
  return [engine, position].filter(Boolean).join(" · ") || undefined;
}

// Display only: use atomic classifier evidence; never infer from profile/path.
export function trackSoundChipLabel(chips?: string[]): string | undefined {
  if (!Array.isArray(chips)) return undefined;
  const order = [
    "YM2612",
    "YM2151",
    "YM2203",
    "SegaPCM",
    "PSG",
    "YM2610",
    "YM2610B",
    "SID 6581",
    "SID 8580",
    "C140",
  ];
  return order.filter((chip) => chips.includes(chip)).join(" + ") || undefined;
}

export const MEGAVGM_DELETE_COLOR = "#7F8B96";
export const MEGAVGM_DELETE_HOVER_COLOR = "#AAB4BD";

export function preservePlaybackTab<T extends string>(current: T): T {
  return current;
}

const DRIVE_ROOT = "/media/fat/MegaVGMDrive";

function lastPathComponent(path: string): string {
  const normalized = path.replace(/\/+$/, "");
  const separator = normalized.lastIndexOf("/");
  return separator < 0 ? normalized : normalized.slice(separator + 1);
}

export function displayDirectory(path: string | undefined): string {
  if (!path) return "Music Library";
  let directory = path;
  if (/\.(?:vgm|mvgmsid|sid)$/i.test(lastPathComponent(path))) {
    const separator = path.lastIndexOf("/");
    directory = separator < 0 ? "" : path.slice(0, separator);
  }
  const name = lastPathComponent(directory);
  if (!name || directory === DRIVE_ROOT) return "MegaVGMDrive";
  return name.replace(/_/g, " ");
}

export function trackRowState(
  rowPath: string,
  currentPath: string | undefined,
  pendingPath: string | undefined,
  currentContext = true
): MegaVGMTrackRowState {
  if (pendingPath === rowPath) return "pending";
  if (currentContext && currentPath === rowPath) return "playing";
  return "idle";
}
