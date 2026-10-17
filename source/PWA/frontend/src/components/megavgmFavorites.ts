import { MegaVGMFavoriteEntry, MegaVGMFavoritesResponse } from "../lib/models";

export const MEGAVGM_DRIVE_ROOT = "/media/fat/MegaVGMDrive";

export function browseFavoritePath(relativePath: string): string {
  return `${MEGAVGM_DRIVE_ROOT}/${relativePath.replace(/^\/+/, "")}`;
}

export function favoritePathSet(
  favorites: MegaVGMFavoritesResponse | undefined
): Set<string> {
  return new Set((favorites?.entries ?? []).map((entry) => entry.path));
}

function optimisticFavoriteEntry(path: string): MegaVGMFavoriteEntry {
  const filename = path.replace(/^.*\//, "");
  const parent = path.slice(0, Math.max(0, path.length - filename.length - 1));
  const directory = parent.startsWith(`${MEGAVGM_DRIVE_ROOT}/`)
    ? parent.slice(MEGAVGM_DRIVE_ROOT.length + 1)
    : "";
  return {
    path,
    filename,
    title: filename.replace(/\.(?:vgm|mvgmsid|sid|nsf|nsfe)$/, ""),
    directory,
    available: true,
  };
}

export function setFavoriteOptimistically(
  favorites: MegaVGMFavoritesResponse | undefined,
  path: string,
  favorite: boolean
): MegaVGMFavoritesResponse {
  const current: MegaVGMFavoritesResponse = favorites ?? {
    version: 1,
    playlist: "Favorites",
    entries: [],
  };
  const withoutPath = current.entries.filter((entry) => entry.path !== path);
  return {
    ...current,
    entries: favorite
      ? [...withoutPath, optimisticFavoriteEntry(path)]
      : withoutPath,
  };
}
