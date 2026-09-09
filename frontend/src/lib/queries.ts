import { useQuery } from "@tanstack/react-query";
import { ControlApi } from "./api";
const api = new ControlApi();

export const useMegaVGMStatus = () =>
  useQuery({
    queryKey: ["megavgm", "status"],
    queryFn: api.megaVGMStatus,
    refetchInterval: 500,
    refetchIntervalInBackground: false,
    retry: 1,
  });

export const useMegaVGMBrowse = (path: string, enabled = true) =>
  useQuery({
    queryKey: ["megavgm", "browse", path],
    queryFn: () => api.browseMegaVGM(path),
    staleTime: 2000,
    enabled,
  });

export const useMegaVGMFavorites = () =>
  useQuery({
    queryKey: ["megavgm", "favorites"],
    queryFn: api.megaVGMFavorites,
    staleTime: 2000,
  });

export const useMegaVGMPlaylists = () =>
  useQuery({
    queryKey: ["megavgm", "playlists"],
    queryFn: api.megaVGMPlaylists,
    staleTime: 2000,
  });

export const useMegaVGMPlaylist = (name: string, enabled = true) =>
  useQuery({
    queryKey: ["megavgm", "playlist", name],
    queryFn: () => api.megaVGMPlaylist(name),
    staleTime: 1000,
    enabled: enabled && name.length > 0,
  });

