import {
  browseFavoritePath,
  favoritePathSet,
  setFavoriteOptimistically,
} from "./megavgmFavorites";
import { MegaVGMFavoritesResponse } from "../lib/models";

function assert(condition: boolean, message: string): void {
  if (!condition) {
    throw new Error(message);
  }
}

const first = "/media/fat/MegaVGMDrive/Album/01 First.vgm";
const second = "/media/fat/MegaVGMDrive/Other/02 Second.vgm";
let favorites: MegaVGMFavoritesResponse | undefined;

favorites = setFavoriteOptimistically(favorites, first, true);
assert(favoritePathSet(favorites).has(first), "Browse ☆ must become ★");
favorites = setFavoriteOptimistically(favorites, first, true);
assert(
  favorites.entries.length === 1,
  "duplicate optimistic add must be idempotent"
);
favorites = setFavoriteOptimistically(favorites, second, true);
assert(
  favorites.entries[0].path === first && favorites.entries[1].path === second,
  "optimistic Favorites must preserve insertion order"
);
favorites = setFavoriteOptimistically(favorites, first, false);
assert(!favoritePathSet(favorites).has(first), "Browse ★ must become ☆");
favorites = setFavoriteOptimistically(favorites, first, false);
assert(favorites.entries.length === 1, "duplicate remove must be idempotent");
assert(
  browseFavoritePath("Album/01 First.vgm") === first,
  "Browse identity must use canonical MegaVGMDrive root"
);

for (let index = 0; index < 100; index += 1) {
  const path = `/media/fat/MegaVGMDrive/Stress/${String(index).padStart(
    3,
    "0"
  )}.vgm`;
  favorites = setFavoriteOptimistically(favorites, path, true);
  if (index % 2 === 0) {
    favorites = setFavoriteOptimistically(favorites, path, false);
  }
}
assert(
  favorites.entries.length === 51,
  `rapid optimistic mutations corrupted entries: ${favorites.entries.length}`
);

const unavailable: MegaVGMFavoritesResponse = {
  version: 1,
  playlist: "Favorites",
  entries: [
    {
      path: first,
      title: "01 First",
      filename: "01 First.vgm",
      directory: "Album",
      available: false,
    },
  ],
};
assert(
  unavailable.entries[0].available === false &&
    favoritePathSet(unavailable).has(first),
  "unavailable Favorite must remain represented and favorited"
);
