import axios from "axios";

import { ControlApi } from "./api";

async function main() {
  Object.defineProperty(globalThis, "localStorage", {
    value: { getItem: () => null, setItem: () => undefined },
  });
  Object.defineProperty(globalThis, "window", {
    value: { location: { protocol: "http:", host: "mister:8182" } },
  });
  const calls: Array<{ method: string; path: string; body?: unknown }> = [];
  const originalPost = axios.post;
  const originalGet = axios.get;
  const originalDelete = axios.delete;
  const originalPatch = axios.patch;
  axios.post = (async (path: string, body?: unknown) => {
    calls.push({ method: "POST", path, body });
    return { data: { accepted: true, mode: "MEGAVGM" } };
  }) as typeof axios.post;
  axios.get = (async (path: string, config?: unknown) => {
    calls.push({ method: "GET", path, body: config });
    if (path === "/megavgm/favorites") {
      return {
        data: { version: 1, playlist: "Favorites", entries: [] },
      };
    }
    if (path === "/megavgm/playlists") {
      return {
        data: {
          version: 1,
          playlists: [
            { name: "Favorites", reserved: true, count: 0, availableCount: 0 },
          ],
        },
      };
    }
    if (path === "/megavgm/playlists/Favorites") {
      return {
        data: { version: 1, name: "Favorites", reserved: true, entries: [] },
      };
    }
    return { data: { path: "", parent: "", entries: [] } };
  }) as typeof axios.get;
  axios.delete = (async (path: string, config?: unknown) => {
    calls.push({ method: "DELETE", path, body: config });
    return { data: { path: "test.vgm", favorite: false } };
  }) as typeof axios.delete;
  axios.patch = (async (path: string, body?: unknown) => {
    calls.push({ method: "PATCH", path, body });
    return { data: { accepted: true, name: "Renamed" } };
  }) as typeof axios.patch;

  try {
    const api = new ControlApi();
    const playlist =
      "/media/fat/MegaVGMDrive/01_Arcade/Galaxy_Force_II_(Sega_Y)";
    await api.startMegaVGM(playlist);
    await api.browseMegaVGM("01_Arcade");
    await api.megaVGMFavorites();
    await api.addMegaVGMFavorite(`${playlist}/03 Scene Select.vgm`);
    await api.removeMegaVGMFavorite(`${playlist}/03 Scene Select.vgm`);
    await api.playMegaVGM(`${playlist}/03 Scene Select.vgm`);
    await api.megaVGMPlaylists();
    await api.megaVGMPlaylist("Favorites");
    await api.createMegaVGMPlaylist("Sega Mix");
    await api.renameMegaVGMPlaylist("Sega Mix", "Renamed");
    await api.addMegaVGMPlaylistTrack(
      "Renamed",
      `${playlist}/03 Scene Select.vgm`
    );
    await api.removeMegaVGMPlaylistTrack(
      "Renamed",
      `${playlist}/03 Scene Select.vgm`
    );
    await api.playMegaVGMPlaylist("Favorites", 0);
    await api.deleteMegaVGMPlaylist("Renamed");
    await api.nextMegaVGMTrack();
    await api.previousMegaVGMTrack();
    await api.stopMegaVGMTrack();
    await api.exitMegaVGM();

    const want = [
      "/megavgm/start",
      "/megavgm/browse",
      "/megavgm/favorites",
      "/megavgm/favorites",
      "/megavgm/favorites",
      "/megavgm/play",
      "/megavgm/playlists",
      "/megavgm/playlists/Favorites",
      "/megavgm/playlists",
      "/megavgm/playlists/Sega%20Mix",
      "/megavgm/playlists/Renamed/tracks",
      "/megavgm/playlists/Renamed/tracks",
      "/megavgm/playlists/Favorites/play",
      "/megavgm/playlists/Renamed",
      "/megavgm/next",
      "/megavgm/prev",
      "/megavgm/stop",
      "/megavgm/exit",
    ];
    if (calls.map((call) => call.path).join("|") !== want.join("|")) {
      throw new Error(`unexpected API calls: ${JSON.stringify(calls)}`);
    }
    const startBody = calls[0].body as { path?: string };
    if (startBody.path !== playlist) {
      throw new Error(`unexpected Start path: ${JSON.stringify(startBody)}`);
    }
    const browseConfig = calls[1].body as { params?: { path?: string } };
    if (browseConfig.params?.path !== "01_Arcade") {
      throw new Error(
        `unexpected Browse path: ${JSON.stringify(browseConfig)}`
      );
    }
    const addBody = calls[3].body as { path?: string };
    if (addBody.path !== `${playlist}/03 Scene Select.vgm`) {
      throw new Error(`unexpected Favorite add: ${JSON.stringify(addBody)}`);
    }
    const removeConfig = calls[4].body as { data?: { path?: string } };
    if (removeConfig.data?.path !== `${playlist}/03 Scene Select.vgm`) {
      throw new Error(
        `unexpected Favorite remove: ${JSON.stringify(removeConfig)}`
      );
    }
    const playBody = calls[5].body as { path?: string };
    if (playBody.path !== `${playlist}/03 Scene Select.vgm`) {
      throw new Error(`unexpected Play path: ${JSON.stringify(playBody)}`);
    }

    axios.get = (async () => ({
      data: {
        mode: "STOCK",
        main: "STOCK",
        supervisorController: "STOPPED",
        controllerRunning: false,
      },
    })) as typeof axios.get;
    const sampledStatus = await api.megaVGMStatus();
    if (
      typeof sampledStatus.clientPollStartedMs !== "number" ||
      typeof sampledStatus.clientPollReceivedMs !== "number" ||
      sampledStatus.clientPollReceivedMs < sampledStatus.clientPollStartedMs
    ) {
      throw new Error(
        `missing client poll timing: ${JSON.stringify(sampledStatus)}`
      );
    }

    axios.get = (async () => ({ data: "<!DOCTYPE html>" })) as typeof axios.get;
    let invalidBrowseRejected = false;
    try {
      await api.browseMegaVGM("");
    } catch {
      invalidBrowseRejected = true;
    }
    if (!invalidBrowseRejected) {
      throw new Error("invalid Browse response must be rejected");
    }
    let invalidFavoritesRejected = false;
    try {
      await api.megaVGMFavorites();
    } catch {
      invalidFavoritesRejected = true;
    }
    if (!invalidFavoritesRejected) {
      throw new Error("invalid Favorites response must be rejected");
    }
  } finally {
    axios.post = originalPost;
    axios.get = originalGet;
    axios.delete = originalDelete;
    axios.patch = originalPatch;
  }
}

void main();
