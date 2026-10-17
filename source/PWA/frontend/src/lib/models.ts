export interface System {
  id: string;
  name: string;
  category: string;
}

export interface Game {
  name: string;
  system: System;
  path: string;
}

export interface IndexedSystems {
  systems: {
    id: string;
    name: string;
  }[];
}

export interface SearchResults {
  data: Game[];
  total: number;
  pageSize: number;
  page: number;
}

export interface Screenshot {
  filename: string;
  path: string;
  core: string;
  modified: string;
  game: string;
}

export interface Wallpaper {
  filename: string;
  name: string;
  width: number;
  height: number;
  active: boolean;
}

export interface AllWallpapers {
  active: string;
  backgroundMode: number;
  wallpapers: Wallpaper[];
}

export interface MusicServiceStatus {
  running: boolean;
  playing: boolean;
  playback: string;
  playlist: string;
  track: string;
}

export interface MegaVGMStatus {
  soundChips?: string[]; // Host classifier evidence for this atomic path/session.
  sid?: {
    formatVersion: 1 | 2;
    model: "6581" | "8580";
    timing: "PAL" | "NTSC";
    subtune: number;
    captureLimited: boolean;
    sourceSha256?: string;
  };
  transport?: MegaVGMTransportStatus;
  mode: "STOCK" | "STARTING" | "MEGAVGM" | "SHUTTING_DOWN" | "FAILURE";
  main: "STOCK" | "STOPPED" | "MODIFIED" | "UNKNOWN" | "RESTORE_FAILED";
  supervisorController: "STOPPED" | "RUNNING" | "UNKNOWN";
  supervisorPlaylist?: string;
  detail?: string;
  controllerRunning: boolean;
  state?: string;
  index?: number;
  count?: number;
  path?: string;
  title?: string;
  session?: number;
  loopCount?: number;
  elapsedMs?: number;
  plannedDurationKind?: "UNKNOWN" | "FINITE" | "INFINITE";
  plannedDurationMs?: number;
  durationSource?: string;
  context?: "DIRECTORY" | "PLAYLIST";
  playlist?: string;
  repeat?: "OFF" | "ONE" | "ALL";
  shuffle?: boolean;
  traversal?: "ORDERED" | "SHUFFLE";
  statusFileMtimeUnixMs?: number;
  statusReadUnixMs?: number;
  clientPollStartedMs?: number;
  clientPollReceivedMs?: number;
}

export interface MegaVGMTransportStatus {
  epoch: string;
  switchGeneration: string;
  switchState:
    | "IDLE"
    | "PARKED"
    | "FADING"
    | "SWITCHING"
    | "READY"
    | "PLAYING"
    | "ENDED"
    | "STOPPED"
    | "FAILED";
  currentProfile: "PROFILE_A" | "PROFILE_B" | "PROFILE_C" | "PROFILE_D" | "PROFILE_E" | "PROFILE_F";
  requiredProfile:
    | "PROFILE_A"
    | "PROFILE_B"
    | "PROFILE_C"
    | "PROFILE_D" | "PROFILE_E" | "PROFILE_F"
    | "UNKNOWN";
  domain: string;
  baseline: number;
  profileChanged: boolean;
  path: string;
}

export interface MegaVGMLifecycleResponse {
  accepted: boolean;
  result:
    | "MEGAVGM_MODE_ACTIVE"
    | "ALREADY_ACTIVE"
    | "STOCK_MISTER_RESTORED"
    | "RESTORE_IN_PROGRESS"
    | "ALREADY_STOPPED";
  mode: MegaVGMStatus["mode"];
}

export interface MegaVGMBrowseEntry {
  name: string;
  type: "file" | "directory";
}

export interface MegaVGMBrowseResponse {
  path: string;
  parent: string;
  entries: MegaVGMBrowseEntry[];
}

export interface MegaVGMPlayResponse {
  accepted: boolean;
  mode: MegaVGMStatus["mode"];
  path: string;
}

export interface MegaVGMFavoriteEntry {
  path: string;
  title: string;
  filename: string;
  directory: string;
  available: boolean;
}

export interface MegaVGMFavoritesResponse {
  version: 1;
  playlist: "Favorites";
  entries: MegaVGMFavoriteEntry[];
}

export interface MegaVGMFavoriteMutationResponse {
  path: string;
  favorite: boolean;
}

export interface MegaVGMPlaylistSummary {
  name: string;
  reserved: boolean;
  count: number;
  availableCount: number;
}

export interface MegaVGMPlaylistsResponse {
  version: 1;
  playlists: MegaVGMPlaylistSummary[];
}

export interface MegaVGMPlaylistResponse {
  version: 1;
  name: string;
  reserved: boolean;
  entries: MegaVGMFavoriteEntry[];
}

export interface MegaVGMPlaylistMutationResponse {
  accepted: boolean;
  name: string;
  path?: string;
}

export interface MegaVGMPlaylistPlayResponse {
  accepted: boolean;
  mode: MegaVGMStatus["mode"];
  playlist: string;
  path: string;
  index: number;
  count: number;
}

export interface SearchServiceStatus {
  ready: boolean;
  indexing: boolean;
  totalSteps: number;
  currentStep: number;
  currentDesc: string;
}

export interface MenuItem {
  name: string;
  namesTxt?: string;
  path: string;
  parent: string;
  filename: string;
  extension: string;
  next?: string;
  type: "folder" | "rbf" | "mra" | "mgl" | "zip";
  modified: string;
  version?: string;
  size: number;
  inZip: boolean;
  system?: System;
}

export interface ViewMenu {
  up?: string;
  items: MenuItem[];
}

export type KeyboardCodes =
  | "up"
  | "down"
  | "left"
  | "right"
  | "volume_up"
  | "volume_down"
  | "volume_mute"
  | "menu"
  | "back"
  | "confirm"
  | "cancel"
  | "osd"
  | "screenshot"
  | "raw_screenshot"
  | "pair_bluetooth"
  | "change_background"
  | "core_select"
  | "user"
  | "reset"
  | "toggle_core_dates"
  | "console"
  | "exit_console"
  | "computer_osd";

export interface CreateLauncherRequest {
  gamePath: string;
  folder: string;
  name: string;
}

interface IniResponse {
  displayName: string;
  filename: string;
  path: string;
}

export interface ListInisPayload {
  active: number;
  inis: IniResponse[];
}

export interface SysInfoResponse {
  ips: string[];
  hostname: string;
  dns: string;
  version: string;
  updated: string;
  disks: {
    path: string;
    total: number;
    used: number;
    free: number;
    displayName: string;
  }[];
}

export interface PeersResponse {
  peers: {
    hostname: string;
    version: string;
    ip: string;
  }[];
}

export interface Script {
  name: string;
  path: string;
  filename: string;
}

export interface ScriptsResponse {
  canLaunch: boolean;
  scripts: Script[];
}
