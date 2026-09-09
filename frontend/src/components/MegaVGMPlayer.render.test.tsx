import React from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";

import type {
  MegaVGMBrowseResponse,
  MegaVGMFavoritesResponse,
  MegaVGMPlaylistResponse,
  MegaVGMPlaylistsResponse,
  MegaVGMStatus,
} from "../lib/models";

type MegaVGMTab = "browse" | "playlists";

function assert(condition: boolean, message: string): void {
  if (!condition) {
    throw new Error(message);
  }
}

Object.defineProperty(globalThis, "localStorage", {
  value: { getItem: () => null, setItem: () => undefined },
});
Object.defineProperty(globalThis, "window", {
  value: { location: { protocol: "http:", host: "mister:8182" } },
});

const playingPath = "/media/fat/MegaVGMDrive/Album/01 First.vgm";
const status: MegaVGMStatus = {
  mode: "MEGAVGM",
  main: "MODIFIED",
  supervisorController: "RUNNING",
  controllerRunning: true,
  state: "PLAYING",
  index: 1,
  count: 2,
  path: playingPath,
  title: "01 First",
  session: 12,
  loopCount: 1,
  context: "PLAYLIST",
  playlist: "Favorites",
  repeat: "ONE",
  shuffle: true,
  traversal: "SHUFFLE",
};
const playlists: MegaVGMPlaylistsResponse = {
  version: 1,
  playlists: [
    { name: "Sega Mix", reserved: false, count: 0, availableCount: 0 },
    { name: "Favorites", reserved: true, count: 2, availableCount: 1 },
  ],
};
const favorites: MegaVGMFavoritesResponse = {
  version: 1,
  playlist: "Favorites",
  entries: [
    {
      path: playingPath,
      title: "01 First",
      filename: "01 First.vgm",
      directory: "Album",
      available: true,
    },
    {
      path: "/media/fat/MegaVGMDrive/Missing/99 Deleted.vgm",
      title: "99 Deleted",
      filename: "99 Deleted.vgm",
      directory: "Missing",
      available: false,
    },
  ],
};
const favoritePlaylist: MegaVGMPlaylistResponse = {
  version: 1,
  name: "Favorites",
  reserved: true,
  entries: favorites.entries,
};
const browse: MegaVGMBrowseResponse = {
  path: "",
  parent: "",
  entries: [
    { name: "Album", type: "directory" },
    {
      name: "A_Very_Long_Game_Directory_Name_For_A_Narrow_Smartphone",
      type: "directory",
    },
    { name: "03 Root.vgm", type: "file" },
  ],
};
const albumBrowse: MegaVGMBrowseResponse = {
  path: "Album",
  parent: "",
  entries: [
    { name: "01 First.vgm", type: "file" },
    {
      name: "02 A Very Long Track Name That Must Remain Usable On A Narrow Smartphone Display.vgm",
      type: "file",
    },
  ],
};

async function main() {
  const { default: MegaVGMPlayer } = await import("./MegaVGMPlayer");
  const originalConsoleError = console.error;
  console.error = () => undefined;
  try {
    function render(
      tab: MegaVGMTab,
      browsePath = "",
      statusOverride: MegaVGMStatus = status
    ): string {
      const client = new QueryClient();
      client.setQueryData(["megavgm", "status"], statusOverride);
      client.setQueryData(["megavgm", "favorites"], favorites);
      client.setQueryData(["megavgm", "playlists"], playlists);
      client.setQueryData(
        ["megavgm", "playlist", "Favorites"],
        favoritePlaylist
      );
      client.setQueryData(["megavgm", "browse", ""], browse);
      client.setQueryData(["megavgm", "browse", "Album"], albumBrowse);
      return renderToStaticMarkup(
        <QueryClientProvider client={client}>
          <MegaVGMPlayer initialTab={tab} initialBrowsePath={browsePath} />
        </QueryClientProvider>
      );
    }

    const now = render("playlists");
    assert(
      !now.includes("—:—") && !now.includes('data-testid="playback-progress"'),
      "time placeholders/progress must not render without authoritative data"
    );
    assert(
      !now.includes('value="now"') &&
        now.includes("Browse") &&
        now.includes("Playlists"),
      "only two bottom tabs must render"
    );
    assert(
      now.includes("01 First") && now.includes("Favorite"),
      "Now Playing star missing"
    );
    assert(
      now.includes('data-testid="playback-source-chips"') &&
        now.includes('data-testid="playback-position"') &&
        now.includes("Favorites") &&
        now.includes(">1/2<") &&
        now.includes("font-variant-numeric:tabular-nums") &&
        now.includes("white-space:nowrap") &&
        now.includes("text-overflow:ellipsis"),
      "Now Playing playlist context missing"
    );
    assert(
      now.includes('aria-label="Player controls"') &&
        now.includes('aria-label="Repeat"') &&
        now.includes('aria-label="Shuffle"') &&
        !now.includes("Repeat One") &&
        !now.includes("Repeat All") &&
        !now.includes("Repeat Off") &&
        !now.includes("Shuffle On") &&
        !now.includes("Shuffle Off"),
      "compact controller modes missing or text labels remain"
    );
    assert(
      !now.includes("/media/fat/") && !now.includes("Playback session"),
      "Now Playing still exposes internal diagnostics"
    );
    assert(
      now.includes("#10151C") && now.includes("#49C6D8"),
      "MegaVGM navy/cyan theme missing"
    );
    assert(
      now.includes('aria-label="Previous track"') &&
        now.includes('aria-label="Stop"') &&
        now.includes('aria-label="Next track"') &&
        !now.includes(">Previous<") &&
        !now.includes(">Next<") &&
        !now.includes(">Stop<") &&
        !now.includes("Pause"),
      "icon-only Previous / Stop / Next controls missing"
    );
    const stoppedNow = render("playlists", "", { ...status, state: "STOPPED" });
    assert(
      stoppedNow.includes("Stopped") &&
        stoppedNow.includes('aria-label="Stop"') &&
        stoppedNow.includes("disabled"),
      "STOPPED transport presentation missing"
    );
    const stockNow = render("playlists", "", {
      ...status,
      mode: "STOCK",
      main: "STOCK",
      supervisorController: "STOPPED",
      controllerRunning: false,
      state: undefined,
    });
    assert(
      stockNow.includes("Start Favorites playlist") &&
        !stockNow.includes("Start default playlist"),
      "cold-start action must launch the existing Favorites playlist"
    );

    const rootBrowseHTML = render("browse");
    assert(rootBrowseHTML.includes("03 Root"), "Browse VGM row missing");
    assert(
      rootBrowseHTML.includes('aria-label="Add favorite"'),
      "Browse ☆ toggle missing"
    );
    assert(rootBrowseHTML.includes("Album"), "folder navigation missing");
    assert(
      rootBrowseHTML.includes("A_Very_Long_Game_Directory_Name") &&
        rootBrowseHTML.includes("text-overflow:ellipsis"),
      "long mobile directory presentation regressed"
    );
    assert(
      rootBrowseHTML.includes('aria-label="Add to playlist"'),
      "Browse Add to playlist control missing"
    );
    assert(
      rootBrowseHTML.includes('aria-label="Player controls"') &&
        rootBrowseHTML.includes('aria-label="Previous track"'),
      "shared controls missing from Browse"
    );
    const browseHTML = render("browse", "Album");
    assert(
      browseHTML.includes('data-track-state="playing"') &&
        browseHTML.includes('data-testid="PlayArrowIcon"'),
      "current Browse row is not visibly marked"
    );
    assert(
      browseHTML.includes("text-overflow:ellipsis") &&
        browseHTML.includes("A Very Long Track Name"),
      "long mobile track presentation regressed"
    );
    assert(
      !browseHTML.includes("/media/fat/") &&
        !browseHTML.includes("overflow-x:auto"),
      "Browse exposes paths or requires horizontal scrolling"
    );

    const favoritesHTML = render("playlists");
    assert(
      favoritesHTML.includes('data-track-state="playing"') &&
        favoritesHTML.includes("Album") &&
        favoritesHTML.includes('data-testid="PlayArrowIcon"'),
      "current Favorite not marked playing"
    );
    assert(
      favoritesHTML.includes("99 Deleted"),
      "unavailable Favorite was hidden"
    );
    assert(
      favoritesHTML.includes("Unavailable"),
      "unavailable Favorite was not labelled"
    );
    assert(
      favoritesHTML.includes('aria-label="Remove from playlist"'),
      "Favorites remove control missing"
    );
    assert(
      favoritesHTML.includes("min-width:44px") &&
        favoritesHTML.includes("min-height:44px"),
      "mobile Favorite touch target regressed"
    );
    assert(
      favoritesHTML.includes("padding-top:2px") &&
        favoritesHTML.includes("padding-bottom:2px"),
      "compact track-row padding missing"
    );
    assert(
      favoritesHTML.includes("Play All") &&
        favoritesHTML.includes("New playlist") &&
        favoritesHTML.includes("Sega Mix"),
      "playlist controls missing"
    );
    assert(
      favoritesHTML.indexOf("Favorites (2)") <
        favoritesHTML.indexOf("Sega Mix (0)"),
      "Favorites must remain pinned before user playlists"
    );
    assert(
      favoritesHTML.includes('aria-label="Player controls"') &&
        favoritesHTML.includes('aria-label="Next track"'),
      "shared controls missing from Playlists"
    );
    assert(
      now.includes("min-width:44px") &&
        now.includes("min-height:44px") &&
        now.includes("height:52px") &&
        now.includes('data-testid="mini-player"') &&
        now.includes("max-width:380px") &&
        now.includes(":focus-visible") &&
        now.includes("-webkit-tap-highlight-color:transparent"),
      "mobile sizing or scoped focus-visible styling regressed"
    );
  } finally {
    console.error = originalConsoleError;
  }
}

void main();
