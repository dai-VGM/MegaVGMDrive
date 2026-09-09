import {
  displayDirectory,
  playbackContextLabel,
  playbackContextDetails,
  MEGAVGM_DELETE_COLOR,
  MEGAVGM_DELETE_HOVER_COLOR,
  preservePlaybackTab,
  trackRowState,
  trackSoundChipLabel,
} from "./megavgmPresentation";
import type { MegaVGMStatus } from "../lib/models";

const contextStatus: MegaVGMStatus = {
  mode: "MEGAVGM",
  main: "MODIFIED",
  supervisorController: "RUNNING",
  controllerRunning: true,
  context: "PLAYLIST",
  playlist: "Favorites",
  path: "/media/fat/MegaVGMDrive/Night_Striker/04 Urban Trail.vgm",
  index: 4,
  count: 10,
  shuffle: true,
  repeat: "ALL",
};
assert(
  playbackContextLabel(contextStatus) === "Favorites · 4/10",
  "snapshot source wins over file directory"
);
assert(
  JSON.stringify(playbackContextDetails(contextStatus)) ===
    JSON.stringify({ sourceAndChips: "Favorites", position: "4/10" }),
  "queue metadata must expose a separate fixed-position counter"
);
assert(
  playbackContextLabel({
    ...contextStatus,
    context: "DIRECTORY",
    count: 21,
  }) === "Night Striker · 4/21",
  "folder source comes from actual playing path"
);
assert(
  playbackContextLabel({
    ...contextStatus,
    playlist: "My Playlist",
    index: 2,
    count: 8,
  }) === "My Playlist · 2/8",
  "index/count preserved without shuffle reinterpretation"
);

function assert(condition: boolean, message: string): void {
  if (!condition) throw new Error(message);
}

for (const [chips, label] of [
  [["PSG", "YM2612"], "YM2612"],
  [["YM2151", "SegaPCM"], "YM2151 / SegaPCM"],
  [["YM2203"], "YM2203"],
  [["YM2610B"], "YM2610B"],
  [["YM2610"], "YM2610"],
  [["SegaPCM"], "SegaPCM"],
] as [string[], string][]) {
  assert(trackSoundChipLabel(chips) === label, "actual chip label");
  assert(
    playbackContextLabel({ ...contextStatus, soundChips: chips }) ===
      `Favorites · ${label} · 4/10`,
    "atomic queue/chip label"
  );
  assert(
    JSON.stringify(
      playbackContextDetails({ ...contextStatus, soundChips: chips })
    ) ===
      JSON.stringify({
        sourceAndChips: `Favorites · ${label}`,
        position: "4/10",
      }),
    "chip label must not change the counter cell"
  );
}
assert(
  trackSoundChipLabel(["PSG"]) === undefined,
  "PSG-only: no guessed primary chip"
);
assert(trackSoundChipLabel(["PROFILE_A"]) === undefined, "no RBF inference");
assert(
  trackSoundChipLabel(["YM2612", "YM2612", "PSG"]) === "YM2612",
  "dedup and display-only PSG exclusion"
);
assert(trackSoundChipLabel(undefined) === undefined, "legacy metadata absent");

assert(
  MEGAVGM_DELETE_COLOR === "#7F8B96" &&
    MEGAVGM_DELETE_HOVER_COLOR === "#AAB4BD",
  "normal delete controls must use the restrained cool-gray palette"
);

assert(
  displayDirectory(
    "/media/fat/MegaVGMDrive/01_Arcade/After_Burner_II_(Sega_X)/02 Final Take Off.vgm"
  ) === "After Burner II (Sega X)",
  "game directory should be human readable"
);
assert(
  !displayDirectory("/media/fat/MegaVGMDrive/Album/Track.vgm").includes(
    "/media/fat"
  ),
  "presentation must not expose canonical roots"
);
assert(
  trackRowState("B", "A", "B") === "pending",
  "pending selection must be distinct"
);
assert(
  trackRowState("A", "A", "A") === "pending",
  "a same-path reload remains pending until confirmed"
);
assert(
  trackRowState("A", "A", undefined) === "playing",
  "confirmed current track must be playing"
);
assert(
  trackRowState("A", "A", undefined, false) === "idle",
  "inactive playlist context must not claim playback"
);

assert(
  preservePlaybackTab("browse") === "browse" &&
    preservePlaybackTab("playlists") === "playlists",
  "successful playback must not force the Now Playing tab"
);
