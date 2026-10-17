import axios from "axios";
import {
  MegaVGMLifecycleResponse,
  MegaVGMBrowseResponse,
  MegaVGMFavoriteMutationResponse,
  MegaVGMFavoritesResponse,
  MegaVGMPlayResponse,
  MegaVGMPlaylistMutationResponse,
  MegaVGMPlaylistPlayResponse,
  MegaVGMPlaylistResponse,
  MegaVGMPlaylistsResponse,
  MegaVGMStatus,
} from "./models";

function isMegaVGMBrowseResponse(
  value: unknown
): value is MegaVGMBrowseResponse {
  if (!value || typeof value !== "object") {
    return false;
  }
  const response = value as Partial<MegaVGMBrowseResponse>;
  return (
    typeof response.path === "string" &&
    typeof response.parent === "string" &&
    Array.isArray(response.entries) &&
    response.entries.every(
      (entry) =>
        !!entry &&
        typeof entry.name === "string" &&
        (entry.type === "file" || entry.type === "directory")
    )
  );
}

function isMegaVGMFavoritesResponse(
  value: unknown
): value is MegaVGMFavoritesResponse {
  if (!value || typeof value !== "object") {
    return false;
  }
  const response = value as Partial<MegaVGMFavoritesResponse>;
  return (
    response.version === 1 &&
    response.playlist === "Favorites" &&
    Array.isArray(response.entries) &&
    response.entries.every(
      (entry) =>
        !!entry &&
        typeof entry.path === "string" &&
        typeof entry.title === "string" &&
        typeof entry.filename === "string" &&
        typeof entry.directory === "string" &&
        typeof entry.available === "boolean"
    )
  );
}

function isMegaVGMPlaylistEntry(value: unknown): boolean {
  if (!value || typeof value !== "object") return false;
  const entry = value as Record<string, unknown>;
  return (
    typeof entry.path === "string" &&
    typeof entry.title === "string" &&
    typeof entry.filename === "string" &&
    typeof entry.directory === "string" &&
    typeof entry.available === "boolean"
  );
}

function isMegaVGMPlaylistsResponse(
  value: unknown
): value is MegaVGMPlaylistsResponse {
  if (!value || typeof value !== "object") return false;
  const response = value as Partial<MegaVGMPlaylistsResponse>;
  return (
    response.version === 1 &&
    Array.isArray(response.playlists) &&
    response.playlists.every(
      (playlist) =>
        !!playlist &&
        typeof playlist.name === "string" &&
        typeof playlist.reserved === "boolean" &&
        typeof playlist.count === "number" &&
        typeof playlist.availableCount === "number"
    )
  );
}

function isMegaVGMPlaylistResponse(
  value: unknown
): value is MegaVGMPlaylistResponse {
  if (!value || typeof value !== "object") return false;
  const response = value as Partial<MegaVGMPlaylistResponse>;
  return (
    response.version === 1 &&
    typeof response.name === "string" &&
    typeof response.reserved === "boolean" &&
    Array.isArray(response.entries) &&
    response.entries.every(isMegaVGMPlaylistEntry)
  );
}

export class ControlApi {
  constructor() {
    axios.defaults.baseURL = window.location.origin + "/api";
  }

  async megaVGMStatus(): Promise<MegaVGMStatus> {
    const clientPollStartedMs = performance.now();
    const response = await axios.get<MegaVGMStatus>(`/megavgm/status`);
    return {
      ...response.data,
      clientPollStartedMs,
      clientPollReceivedMs: performance.now(),
    };
  }

  async startMegaVGM(path: string): Promise<MegaVGMLifecycleResponse> {
    return (
      await axios.post<MegaVGMLifecycleResponse>(`/megavgm/start`, { path })
    ).data;
  }

  async exitMegaVGM(): Promise<MegaVGMLifecycleResponse> {
    return (await axios.post<MegaVGMLifecycleResponse>(`/megavgm/exit`)).data;
  }

  async nextMegaVGMTrack(): Promise<void> {
    await axios.post(`/megavgm/next`);
  }

  async previousMegaVGMTrack(): Promise<void> {
    await axios.post(`/megavgm/prev`);
  }

  async stopMegaVGMTrack(): Promise<void> {
    await axios.post(`/megavgm/stop`);
  }

  async setMegaVGMRepeat(mode: "off" | "one" | "all"): Promise<void> {
    await axios.post(`/megavgm/repeat`, { mode });
  }

  async setMegaVGMShuffle(enabled: boolean): Promise<void> {
    await axios.post(`/megavgm/shuffle`, { enabled });
  }

  async browseMegaVGM(path: string): Promise<MegaVGMBrowseResponse> {
    const response = (
      await axios.get<unknown>(`/megavgm/browse`, { params: { path } })
    ).data;
    if (!isMegaVGMBrowseResponse(response)) {
      throw new Error("invalid MegaVGM browse response");
    }
    return response;
  }

  async playMegaVGM(path: string): Promise<MegaVGMPlayResponse> {
    return (await axios.post<MegaVGMPlayResponse>(`/megavgm/play`, { path }))
      .data;
  }

  async megaVGMFavorites(): Promise<MegaVGMFavoritesResponse> {
    const response = (await axios.get<unknown>(`/megavgm/favorites`)).data;
    if (!isMegaVGMFavoritesResponse(response)) {
      throw new Error("invalid MegaVGM Favorites response");
    }
    return response;
  }

  async addMegaVGMFavorite(
    path: string
  ): Promise<MegaVGMFavoriteMutationResponse> {
    return (
      await axios.post<MegaVGMFavoriteMutationResponse>(`/megavgm/favorites`, {
        path,
      })
    ).data;
  }

  async removeMegaVGMFavorite(
    path: string
  ): Promise<MegaVGMFavoriteMutationResponse> {
    return (
      await axios.delete<MegaVGMFavoriteMutationResponse>(
        `/megavgm/favorites`,
        { data: { path } }
      )
    ).data;
  }

  async megaVGMPlaylists(): Promise<MegaVGMPlaylistsResponse> {
    const response = (await axios.get<unknown>(`/megavgm/playlists`)).data;
    if (!isMegaVGMPlaylistsResponse(response)) {
      throw new Error("invalid MegaVGM playlists response");
    }
    return response;
  }

  async megaVGMPlaylist(name: string): Promise<MegaVGMPlaylistResponse> {
    const response = (
      await axios.get<unknown>(`/megavgm/playlists/${encodeURIComponent(name)}`)
    ).data;
    if (!isMegaVGMPlaylistResponse(response)) {
      throw new Error("invalid MegaVGM playlist response");
    }
    return response;
  }

  async createMegaVGMPlaylist(
    name: string
  ): Promise<MegaVGMPlaylistMutationResponse> {
    return (
      await axios.post<MegaVGMPlaylistMutationResponse>(`/megavgm/playlists`, {
        name,
      })
    ).data;
  }

  async renameMegaVGMPlaylist(
    name: string,
    newName: string
  ): Promise<MegaVGMPlaylistMutationResponse> {
    return (
      await axios.patch<MegaVGMPlaylistMutationResponse>(
        `/megavgm/playlists/${encodeURIComponent(name)}`,
        { name: newName }
      )
    ).data;
  }

  async deleteMegaVGMPlaylist(
    name: string
  ): Promise<MegaVGMPlaylistMutationResponse> {
    return (
      await axios.delete<MegaVGMPlaylistMutationResponse>(
        `/megavgm/playlists/${encodeURIComponent(name)}`
      )
    ).data;
  }

  async addMegaVGMPlaylistTrack(
    name: string,
    path: string
  ): Promise<MegaVGMPlaylistMutationResponse> {
    return (
      await axios.post<MegaVGMPlaylistMutationResponse>(
        `/megavgm/playlists/${encodeURIComponent(name)}/tracks`,
        { path }
      )
    ).data;
  }

  async removeMegaVGMPlaylistTrack(
    name: string,
    path: string
  ): Promise<MegaVGMPlaylistMutationResponse> {
    return (
      await axios.delete<MegaVGMPlaylistMutationResponse>(
        `/megavgm/playlists/${encodeURIComponent(name)}/tracks`,
        { data: { path } }
      )
    ).data;
  }

  async playMegaVGMPlaylist(
    name: string,
    index?: number
  ): Promise<MegaVGMPlaylistPlayResponse> {
    return (
      await axios.post<MegaVGMPlaylistPlayResponse>(
        `/megavgm/playlists/${encodeURIComponent(name)}/play`,
        index === undefined ? {} : { index }
      )
    ).data;
  }

}
