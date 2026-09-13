import Box from "@mui/material/Box";
import Button from "@mui/material/Button";
import CircularProgress from "@mui/material/CircularProgress";
import Divider from "@mui/material/Divider";
import IconButton from "@mui/material/IconButton";
import Menu from "@mui/material/Menu";
import MenuItem from "@mui/material/MenuItem";
import MoreHorizIcon from "@mui/icons-material/MoreHoriz";
import Stack from "@mui/material/Stack";
import Tab from "@mui/material/Tab";
import Tabs from "@mui/material/Tabs";
import TextField from "@mui/material/TextField";
import Typography from "@mui/material/Typography";
import ArrowBackIcon from "@mui/icons-material/ArrowBack";
import AudioFileIcon from "@mui/icons-material/AudioFile";
import FolderIcon from "@mui/icons-material/Folder";
import PlayArrowIcon from "@mui/icons-material/PlayArrow";
import StarIcon from "@mui/icons-material/Star";
import StarBorderIcon from "@mui/icons-material/StarBorder";
import PlaylistAddIcon from "@mui/icons-material/PlaylistAdd";
import DeleteIcon from "@mui/icons-material/Delete";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useEffect, useLayoutEffect, useRef, useState } from "react";

import { ControlApi } from "../lib/api";
import { MegaVGMFavoritesResponse } from "../lib/models";
import {
  useMegaVGMBrowse,
  useMegaVGMFavorites,
  useMegaVGMPlaylist,
  useMegaVGMPlaylists,
  useMegaVGMStatus,
} from "../lib/queries";
import {
  browseFavoritePath,
  favoritePathSet,
  setFavoriteOptimistically,
} from "./megavgmFavorites";
import {
  browseEntryDisabled,
  lifecycleControls,
  megaVGMView,
  navigationEnabled,
  playRequestIsCurrent,
  lifecycleRequestSucceeded,
  stopEnabled,
} from "./megavgmView";
import {
  beginPlayOperation,
  PlayOperation,
  PlayOperationEvent,
  playOperationRemaining,
  reducePlayOperation,
} from "./megavgmPlayOperation";
import { repeatCommand, repeatMode } from "./megavgmPlaybackMode";
import MegaVGMPlayerControls from "./MegaVGMPlayerControls";
import { useMegaVGMScroll } from "./useMegaVGMScroll";
import {
  emptyTransportDisplay,
  observeTransport,
  invalidateTransport,
} from "./megavgmTransportDisplay";
import {
  displayDirectory,
  playbackContextDetails,
  MEGAVGM_DELETE_COLOR,
  MEGAVGM_DELETE_HOVER_COLOR,
  trackRowState,
} from "./megavgmPresentation";

interface PlayIntent {
  requestId: number;
  path: string;
  baselineSession?: number;
  baselineIndex?: number;
  baselineTransportEpoch?: string;
  baselineSwitchGeneration?: string;
  requestedAtMs: number;
}

interface PlaylistPlayIntent extends PlayIntent {
  playlist: string;
  index: number;
}

interface FavoriteIntent {
  path: string;
  favorite: boolean;
}

export type MegaVGMTab = "browse" | "playlists";

interface MegaVGMPlayerProps {
  initialTab?: MegaVGMTab;
  initialBrowsePath?: string;
}

function displayState(state: string | undefined): string {
  if (!state) {
    return "—";
  }
  return state.charAt(0) + state.slice(1).toLowerCase();
}

const colors = {
  background: "#10151C",
  surface: "#18212B",
  text: "#E8EEF4",
  secondary: "#9AA9B7",
  accent: "#49C6D8",
  playing: "#77DDE8",
  favorite: "#D9A441",
};

const pageSx = {
  height: "calc(100dvh - var(--megavgm-content-top, 56px))",
  display: "flex",
  flexDirection: "column",
  overflow: "hidden",
  width: "100%",
  boxSizing: "border-box",
  overflowX: "hidden",
  bgcolor: colors.background,
  color: colors.text,
  "& .MuiTypography-colorTextSecondary": { color: colors.secondary },
  "& .MuiDivider-root": { borderColor: "rgba(119, 221, 232, 0.16)" },
  "& .MuiTabs-root": { minHeight: 44 },
  "& .MuiTabs-indicator": { backgroundColor: colors.accent, height: 2 },
  "& .MuiTab-root": {
    color: colors.secondary,
    minWidth: 0,
    minHeight: 44,
    px: { xs: 0.5, sm: 2 },
    fontSize: { xs: "0.75rem", sm: "0.875rem" },
    textTransform: "none",
  },
  "& .MuiTab-root.Mui-selected": { color: colors.accent },
  "& .MuiButton-contained": {
    bgcolor: colors.accent,
    color: colors.background,
    boxShadow: "none",
    "&:hover": { bgcolor: colors.playing, boxShadow: "none" },
  },
  "& .MuiButton-outlined": {
    color: colors.text,
    borderColor: "rgba(73, 198, 216, 0.4)",
  },
  "& .MuiButton-outlined:focus:not(:focus-visible)": {
    outline: "none",
    borderColor: "rgba(73, 198, 216, 0.4) !important",
  },
  "& .MuiButton-outlined:focus-visible": {
    borderColor: `${colors.accent} !important`,
  },
  "& .MuiButton-outlined.Mui-focusVisible": {
    borderColor: `${colors.accent} !important`,
  },
  "& .MuiButton-text": { color: colors.accent },
  "& .MuiOutlinedInput-root": {
    bgcolor: colors.surface,
    color: colors.text,
    caretColor: colors.accent,
    "&.Mui-focused .MuiOutlinedInput-notchedOutline": {
      borderColor: colors.accent,
    },
  },
  "& .MuiInputLabel-root": { color: colors.secondary },
  "& .MuiFormLabel-root.MuiInputLabel-root.Mui-focused": {
    // MUI's generated FormLabel focus rule is injected after this route sx.
    // Keep the override route-scoped while ensuring no theme-primary purple.
    color: `${colors.accent} !important`,
  },
  "& .MegaVGM-playerControl:focus:not(:focus-visible)": { outline: "none" },
  "& .MegaVGM-playerControl:focus-visible": {
    outline: `2px solid ${colors.accent}`,
    outlineOffset: 2,
  },
  // Keep keyboard focus visible without leaving Safari's purple touch focus
  // treatment behind on rows and controls.
  "& .MuiButtonBase-root": { WebkitTapHighlightColor: "transparent" },
  "& .MuiButtonBase-root:focus:not(:focus-visible)": { outline: "none" },
  "& .MuiButtonBase-root:focus-visible": {
    outline: `2px solid ${colors.accent}`,
    outlineOffset: 2,
  },
};

const trackTitleSx = {
  overflow: "hidden",
  textOverflow: "ellipsis",
  whiteSpace: "nowrap",
  display: "block",
  minWidth: 0,
};

// Directory navigation uses MUI's outlined-primary Button. Keep its retained
// iOS pointer/focus states independent of Remote's purple application primary.
const browseOutlinedRowSx = {
  color: `${colors.text} !important`,
  borderColor: "rgba(73, 198, 216, 0.4)",
  WebkitTapHighlightColor: "transparent",
  "&:hover, &:active, &:focus:not(:focus-visible)": {
    color: `${colors.text} !important`,
    borderColor: "rgba(73, 198, 216, 0.4) !important",
    outline: "none",
  },
  "&:focus-visible, &.Mui-focusVisible": {
    color: `${colors.text} !important`,
    borderColor: `${colors.accent} !important`,
    outline: `2px solid ${colors.accent} !important`,
    outlineOffset: 2,
  },
};

export default function MegaVGMPlayer({
  initialTab = "browse",
  initialBrowsePath = "",
}: MegaVGMPlayerProps = {}) {
  const api = new ControlApi();
  const queryClient = useQueryClient();
  const status = useMegaVGMStatus();
  const transportDisplayRef = useRef(emptyTransportDisplay());
  transportDisplayRef.current = observeTransport(
    transportDisplayRef.current,
    status.data
  );
  const transportDisplay = transportDisplayRef.current;
  const switchingPath = transportDisplay.switching
    ? transportDisplay.receipt?.path
    : undefined;
  const pendingLabel = (path: string) =>
    status.data?.state === "PREPARING" && status.data.path === path
      ? "Preparing SID…"
      : switchingPath === path
      ? "Switching…"
      : "Loading…";
  const shellRef = useRef<HTMLDivElement>(null);
  const contentRef = useRef<HTMLDivElement>(null);
  const [optionsAnchor, setOptionsAnchor] = useState<HTMLElement | null>(null);
  useLayoutEffect(() => {
    // Standalone viewport sizing/scroll ownership is entirely CSS-driven.
    if (window.matchMedia?.("(display-mode: standalone)").matches) return;
    const measure = () => {
      const shell = shellRef.current;
      if (shell)
        shell.style.setProperty(
          "--megavgm-content-top",
          Math.max(0, shell.getBoundingClientRect().top + window.scrollY) + "px"
        );
    };
    measure();
    // Entering from a document-scrolled Remote page must not displace the
    // viewport shell. Tab/folder navigation uses only the content scroll ref.
    window.scrollTo({ top: 0, behavior: "auto" });
    window.addEventListener("resize", measure);
    return () => window.removeEventListener("resize", measure);
  }, []);
  const [tab, setTab] = useState<MegaVGMTab>(initialTab);
  const [browsePath, setBrowsePath] = useState(initialBrowsePath);
  const [queuedPlay, setQueuedPlay] = useState<PlayIntent>();
  const [playOperation, setPlayOperation] = useState<PlayOperation>();
  const operationRef = useRef<PlayOperation>();
  const statusRef = useRef(status.data);
  statusRef.current = status.data;
  const playTarget =
    playOperation?.disposition === "pending" ? playOperation : undefined;
  const [playMessage, setPlayMessage] = useState<string>();
  const playRequestSequence = useRef(0);
  const latestPlayRequestId = useRef(0);
  const updatePlayOperation = (event: PlayOperationEvent) => {
    const current = operationRef.current;
    if (!current) return;
    const updated = reducePlayOperation(current, event);
    if (updated === current) return;
    operationRef.current = updated; // synchronous guard against late callbacks
    setPlayOperation(updated);
    setPlayMessage(updated.message);
    if (
      current.disposition === "pending" &&
      updated.disposition !== "pending"
    ) {
      console.info("MegaVGM Play UI receipt retired", {
        requestId: updated.requestId,
        disposition: updated.disposition,
        selectedSession: updated.selectedSession,
        selectedPlayingObserved: updated.selectedPlayingObserved,
      });
    }
  };
  const beginPlay = (
    request: PlayIntent,
    playlist?: string,
    index?: number
  ) => {
    transportDisplayRef.current = invalidateTransport(
      transportDisplayRef.current
    );
    updatePlayOperation({ type: "supersede" });
    const operation = beginPlayOperation({
      ...request,
      path: request.path.startsWith("/media/fat/MegaVGMDrive/")
        ? request.path
        : browseFavoritePath(request.path),
      expectedPlaylist: playlist,
      expectedPlaylistIndex: index,
    });
    operationRef.current = operation;
    setPlayOperation(operation);
    setPlayMessage(undefined);
  };
  const settlePlay = (request: PlayIntent, path?: string, error?: string) => {
    if (!playRequestIsCurrent(request.requestId, latestPlayRequestId.current))
      return;
    // A query can have arrived before React's status effect / HTTP callback.
    updatePlayOperation({ type: "observe", status: statusRef.current });
    updatePlayOperation(
      path !== undefined
        ? {
            type: "accept",
            requestId: request.requestId,
            atMs: performance.now(),
            path,
          }
        : { type: "fail", requestId: request.requestId, message: error! }
    );
  };
  const browse = useMegaVGMBrowse(browsePath, tab === "browse");
  const favorites = useMegaVGMFavorites();
  const playlists = useMegaVGMPlaylists();
  const [selectedPlaylist, setSelectedPlaylist] = useState("Favorites");
  const selectedPlaylistData = useMegaVGMPlaylist(
    selectedPlaylist,
    tab === "playlists"
  );
  const rememberScroll = useMegaVGMScroll(
    tab === "browse" ? `browse:${browsePath}` : `playlist:${selectedPlaylist}`,
    tab === "browse" ? !browse.isLoading : !selectedPlaylistData.isLoading,
    contentRef
  );
  const selectTab = (value: MegaVGMTab) => {
    rememberScroll();
    setTab(value);
  };
  const selectFolder = (path: string) => {
    rememberScroll();
    setBrowsePath(path);
  };
  const [newPlaylistName, setNewPlaylistName] = useState("");
  const [renamePlaylistName, setRenamePlaylistName] = useState("");
  const [playlistChooserPath, setPlaylistChooserPath] = useState<string>();
  const [playlistMessage, setPlaylistMessage] = useState<string>();
  const refresh = () =>
    queryClient.invalidateQueries({ queryKey: ["megavgm", "status"] });
  const exit = useMutation({
    mutationFn: () => api.exitMegaVGM(),
    onSuccess: refresh,
  });
  const previous = useMutation({
    mutationFn: () => api.previousMegaVGMTrack(),
  });
  const next = useMutation({ mutationFn: () => api.nextMegaVGMTrack() });
  const stop = useMutation({
    mutationFn: () => api.stopMegaVGMTrack(),
    onSuccess: refresh,
    onError: () => setPlayMessage("Playback could not be stopped."),
  });
  const [modeMessage, setModeMessage] = useState<string>();
  const repeatMutation = useMutation({
    mutationFn: (mode: "off" | "one" | "all") => api.setMegaVGMRepeat(mode),
    onSuccess: () => {
      setModeMessage(undefined);
      refresh();
    },
    onError: () => setModeMessage("Repeat mode update failed."),
  });
  const shuffleMutation = useMutation({
    mutationFn: (enabled: boolean) => api.setMegaVGMShuffle(enabled),
    onSuccess: () => {
      setModeMessage(undefined);
      refresh();
    },
    onError: () => setModeMessage("Shuffle mode update failed."),
  });
  const [favoriteMessage, setFavoriteMessage] = useState<string>();
  const favoriteMutation = useMutation({
    mutationFn: (intent: FavoriteIntent) =>
      intent.favorite
        ? api.addMegaVGMFavorite(intent.path)
        : api.removeMegaVGMFavorite(intent.path),
    onMutate: async (intent) => {
      await queryClient.cancelQueries({ queryKey: ["megavgm", "favorites"] });
      const previous =
        queryClient.getQueryData<MegaVGMFavoritesResponse>([
          "megavgm",
          "favorites",
        ]) ?? setFavoriteOptimistically(undefined, intent.path, false);
      queryClient.setQueryData<MegaVGMFavoritesResponse>(
        ["megavgm", "favorites"],
        setFavoriteOptimistically(previous, intent.path, intent.favorite)
      );
      setFavoriteMessage(undefined);
      return { previous };
    },
    onError: (_error, _intent, context) => {
      if (context) {
        queryClient.setQueryData(["megavgm", "favorites"], context.previous);
      }
      setFavoriteMessage("Favorite update failed.");
    },
    onSettled: () => {
      void queryClient.invalidateQueries({
        queryKey: ["megavgm", "favorites"],
      });
      void queryClient.invalidateQueries({
        queryKey: ["megavgm", "playlists"],
      });
      void queryClient.invalidateQueries({
        queryKey: ["megavgm", "playlist", "Favorites"],
      });
    },
  });
  const play = useMutation({
    mutationFn: (request: PlayIntent) => api.playMegaVGM(request.path),
    onSuccess: (response, request) => {
      settlePlay(request, response.path);
      refresh();
    },
    onError: (_error, request) => {
      settlePlay(request, undefined, "The selected VGM could not be started.");
    },
  });
  const playlistPlay = useMutation({
    mutationFn: (request: PlaylistPlayIntent) =>
      api.playMegaVGMPlaylist(request.playlist, request.index),
    onSuccess: (response, request) => {
      const acceptedAtMs = performance.now();
      console.info("MegaVGM playlist Play accepted", {
        requestId: request.requestId,
        playlist: request.playlist,
        index: request.index,
        path: request.path,
        requestToAcceptedMs: acceptedAtMs - request.requestedAtMs,
      });
      settlePlay(request, response.path);
      refresh();
    },
    onError: (_error, request) => {
      settlePlay(
        request,
        undefined,
        "The playlist selection could not be started."
      );
    },
  });
  const refreshPlaylistQueries = () => {
    void queryClient.invalidateQueries({ queryKey: ["megavgm", "playlists"] });
    void queryClient.invalidateQueries({ queryKey: ["megavgm", "playlist"] });
    void queryClient.invalidateQueries({ queryKey: ["megavgm", "favorites"] });
  };
  const createPlaylist = useMutation({
    mutationFn: async (input: { name: string; addPath?: string }) => {
      await api.createMegaVGMPlaylist(input.name);
      if (input.addPath) {
        await api.addMegaVGMPlaylistTrack(input.name, input.addPath);
      }
      return input;
    },
    onSuccess: (input) => {
      setSelectedPlaylist(input.name);
      setNewPlaylistName("");
      setPlaylistChooserPath(undefined);
      setPlaylistMessage(undefined);
      refreshPlaylistQueries();
    },
    onError: () => setPlaylistMessage("Playlist creation failed."),
  });
  const renamePlaylist = useMutation({
    mutationFn: (input: { name: string; newName: string }) =>
      api.renameMegaVGMPlaylist(input.name, input.newName),
    onSuccess: (response) => {
      setSelectedPlaylist(response.name);
      setRenamePlaylistName("");
      setPlaylistMessage(undefined);
      refreshPlaylistQueries();
    },
    onError: () => setPlaylistMessage("Playlist rename failed."),
  });
  const deletePlaylist = useMutation({
    mutationFn: (name: string) => api.deleteMegaVGMPlaylist(name),
    onSuccess: () => {
      setSelectedPlaylist("Favorites");
      setPlaylistMessage(undefined);
      refreshPlaylistQueries();
    },
    onError: () => setPlaylistMessage("Playlist delete failed."),
  });
  const addPlaylistTrack = useMutation({
    mutationFn: (input: { name: string; path: string }) =>
      api.addMegaVGMPlaylistTrack(input.name, input.path),
    onSuccess: () => {
      setPlaylistChooserPath(undefined);
      setPlaylistMessage("Added to playlist.");
      refreshPlaylistQueries();
    },
    onError: () => setPlaylistMessage("Could not add this track."),
  });
  const removePlaylistTrack = useMutation({
    mutationFn: (input: { name: string; path: string }) =>
      api.removeMegaVGMPlaylistTrack(input.name, input.path),
    onSuccess: () => {
      setPlaylistMessage(undefined);
      refreshPlaylistQueries();
    },
    onError: () => setPlaylistMessage("Could not remove this track."),
  });

  useEffect(() => {
    updatePlayOperation({ type: "observe", status: status.data });
  }, [status.data]);

  useEffect(() => {
    if (exit.isError && lifecycleRequestSucceeded(status.data, "exit")) {
      exit.reset();
    }
  }, [status.data, exit.isError]);

  useEffect(() => {
    if (!play.isLoading && queuedPlay) {
      setQueuedPlay(undefined);
      if (
        playRequestIsCurrent(queuedPlay.requestId, latestPlayRequestId.current)
      ) {
        play.mutate(queuedPlay);
      }
    }
  }, [play.isLoading, queuedPlay]);

  useEffect(() => {
    if (!playTarget) return;
    const requestId = playTarget.requestId;
    const timer = window.setTimeout(() => {
      if (!playRequestIsCurrent(requestId, latestPlayRequestId.current)) return;
      updatePlayOperation({ type: "observe", status: statusRef.current });
      updatePlayOperation({
        type: "expire",
        requestId,
        atMs: performance.now(),
      });
    }, playOperationRemaining(playTarget, performance.now()));
    return () => window.clearTimeout(timer);
  }, [playTarget]);

  const clearTransientPlay = (message?: string) => {
    transportDisplayRef.current = invalidateTransport(
      transportDisplayRef.current
    );
    latestPlayRequestId.current = ++playRequestSequence.current;
    setQueuedPlay(undefined);
    updatePlayOperation({ type: "supersede" });
    setPlayMessage(message);
  };

  const refreshStatus = () => {
    clearTransientPlay();
    void status.refetch();
    void queryClient.invalidateQueries({ queryKey: ["megavgm", "browse"] });
    void queryClient.invalidateQueries({ queryKey: ["megavgm", "favorites"] });
    void queryClient.invalidateQueries({ queryKey: ["megavgm", "playlists"] });
    void queryClient.invalidateQueries({ queryKey: ["megavgm", "playlist"] });
  };

  const view = megaVGMView(status.data);
  const lifecycle = lifecycleControls(
    view,
    playlistPlay.isLoading,
    exit.isLoading
  );
  const reconnecting = status.isError;
  const mutationError =
    exit.isError && !lifecycleRequestSucceeded(status.data, "exit");
  const favoritedPaths = favoritePathSet(favorites.data);
  const favoritesStartEntry = favorites.data?.entries[0];

  const toggleFavorite = (path: string) => {
    if (!path || favoriteMutation.isLoading) {
      return;
    }
    favoriteMutation.mutate({
      path,
      favorite: !favoritedPaths.has(path),
    });
  };

  const requestPlay = (path: string) => {
    const requestId = ++playRequestSequence.current;
    const requestedAtMs = performance.now();
    const request: PlayIntent = {
      requestId,
      path,
      requestedAtMs,
      baselineSession:
        status.data?.mode === "MEGAVGM" ? status.data.session : undefined,
      baselineIndex:
        status.data?.mode === "MEGAVGM" ? status.data.index : undefined,
      baselineTransportEpoch:
        status.data?.mode === "MEGAVGM"
          ? status.data.transport?.epoch
          : undefined,
      baselineSwitchGeneration:
        status.data?.mode === "MEGAVGM"
          ? status.data.transport?.switchGeneration
          : undefined,
    };
    latestPlayRequestId.current = requestId;
    beginPlay(request);
    if (play.isLoading) {
      setQueuedPlay(request);
    } else {
      play.reset();
      play.mutate(request);
    }
  };

  const requestPlaylistPlay = (
    playlist: string,
    index: number,
    path: string
  ) => {
    const requestId = ++playRequestSequence.current;
    const request: PlaylistPlayIntent = {
      requestId,
      playlist,
      index,
      path,
      requestedAtMs: performance.now(),
      baselineSession:
        status.data?.mode === "MEGAVGM" ? status.data.session : undefined,
      baselineIndex:
        status.data?.mode === "MEGAVGM" ? status.data.index : undefined,
      baselineTransportEpoch:
        status.data?.mode === "MEGAVGM"
          ? status.data.transport?.epoch
          : undefined,
      baselineSwitchGeneration:
        status.data?.mode === "MEGAVGM"
          ? status.data.transport?.switchGeneration
          : undefined,
    };
    console.info("MegaVGM playlist Play requested", {
      requestId,
      playlist,
      index,
      path,
      requestedAtMs: request.requestedAtMs,
    });
    latestPlayRequestId.current = requestId;
    setQueuedPlay(undefined);
    beginPlay(request, playlist, index);
    playlistPlay.reset();
    playlistPlay.mutate(request);
  };

  const selectEntry = (name: string, type: "file" | "directory") => {
    const relative = browse.data?.path ? `${browse.data.path}/${name}` : name;
    if (type === "directory") {
      selectFolder(relative);
      return;
    }
    requestPlay(relative);
  };

  const browsePanel = (
    <Stack spacing={1}>
      <Box>
        <Typography variant="overline" color="text.secondary">
          Browse music
        </Typography>
        <Typography variant="h6" sx={trackTitleSx}>
          {browse.data?.path
            ? displayDirectory(browse.data.path)
            : "Music Library"}
        </Typography>
      </Box>
      {browse.data?.path && (
        <Button
          className="MegaVGM-browseOutlinedRow"
          variant="outlined"
          startIcon={<ArrowBackIcon />}
          onClick={() => selectFolder(browse.data?.parent || "")}
          sx={browseOutlinedRowSx}
        >
          Parent folder
        </Button>
      )}
      {browse.isLoading && <Typography>Loading music…</Typography>}
      {browse.isError && (
        <Typography color="error">This music folder is unavailable.</Typography>
      )}
      {(browse.data?.entries ?? []).map((entry) => {
        const relative = browse.data?.path
          ? `${browse.data.path}/${entry.name}`
          : entry.name;
        if (entry.type === "directory") {
          return (
            <Button
              key={`directory:${entry.name}`}
              className="MegaVGM-browseOutlinedRow"
              variant="outlined"
              startIcon={<FolderIcon />}
              onClick={() => selectEntry(entry.name, entry.type)}
              sx={{
                ...browseOutlinedRowSx,
                minHeight: 44,
                justifyContent: "flex-start",
                textTransform: "none",
                bgcolor: colors.surface,
                overflow: "hidden",
                textOverflow: "ellipsis",
                whiteSpace: "nowrap",
              }}
            >
              {entry.name}
            </Button>
          );
        }
        const canonicalPath = browseFavoritePath(relative);
        const isFavorite = favoritedPaths.has(canonicalPath);
        const selectedPending =
          playTarget?.path === relative || playTarget?.path === canonicalPath;
        const rowState = trackRowState(
          canonicalPath,
          status.data?.controllerRunning && status.data.state === "PLAYING"
            ? status.data.path
            : undefined,
          selectedPending || switchingPath === canonicalPath
            ? canonicalPath
            : undefined
        );
        return (
          <Box
            key={`file:${entry.name}`}
            data-track-state={rowState}
            sx={{
              bgcolor:
                rowState === "playing"
                  ? "rgba(119, 221, 232, 0.13)"
                  : colors.surface,
              border: "1px solid",
              borderColor:
                rowState === "pending"
                  ? "rgba(232, 238, 244, 0.35)"
                  : rowState === "playing"
                  ? "rgba(119, 221, 232, 0.55)"
                  : "rgba(154, 169, 183, 0.12)",
              borderRadius: 1.5,
              overflow: "hidden",
            }}
          >
            <Stack direction="row" spacing={0.5} alignItems="stretch">
              <Button
                variant="text"
                startIcon={
                  rowState === "pending" ? (
                    <CircularProgress size={18} color="inherit" />
                  ) : rowState === "playing" ? (
                    <PlayArrowIcon />
                  ) : (
                    <AudioFileIcon />
                  )
                }
                disabled={
                  browseEntryDisabled("file", relative, playTarget?.path) ||
                  browseEntryDisabled("file", canonicalPath, playTarget?.path)
                }
                onClick={() => selectEntry(entry.name, entry.type)}
                sx={{
                  flex: 1,
                  minWidth: 0,
                  minHeight: 44,
                  py: 0.25,
                  justifyContent: "flex-start",
                  textTransform: "none",
                  color: rowState === "playing" ? colors.playing : colors.text,
                  overflow: "hidden",
                }}
              >
                <Box
                  component="span"
                  textAlign="left"
                  minWidth={0}
                  width="100%"
                >
                  <Box component="span" sx={trackTitleSx}>
                    {entry.name.replace(/\.(?:vgm|mvgmsid|sid)$/, "")}
                  </Box>
                  {rowState === "pending" && (
                    <Box
                      component="span"
                      display="block"
                      color={colors.secondary}
                      fontSize="0.6875rem"
                      lineHeight={1.1}
                    >
                      {pendingLabel(canonicalPath)}
                    </Box>
                  )}
                </Box>
              </Button>
              <IconButton
                aria-label={isFavorite ? "Remove favorite" : "Add favorite"}
                disabled={favoriteMutation.isLoading}
                onClick={() => toggleFavorite(canonicalPath)}
                sx={{
                  minWidth: 44,
                  minHeight: 44,
                  color: isFavorite ? colors.favorite : colors.secondary,
                }}
              >
                {isFavorite ? <StarIcon /> : <StarBorderIcon />}
              </IconButton>
              <IconButton
                aria-label="Add to playlist"
                onClick={() => setPlaylistChooserPath(canonicalPath)}
                sx={{ minWidth: 44, minHeight: 44, color: colors.secondary }}
              >
                <PlaylistAddIcon />
              </IconButton>
            </Stack>
            {playlistChooserPath === canonicalPath && (
              <Stack spacing={0.5} sx={{ mt: 1, ml: 1 }}>
                <Typography variant="caption">Add to playlist…</Typography>
                {(playlists.data?.playlists ?? []).map((playlist) => (
                  <Button
                    key={playlist.name}
                    size="small"
                    variant="outlined"
                    disabled={addPlaylistTrack.isLoading}
                    onClick={() =>
                      addPlaylistTrack.mutate({
                        name: playlist.name,
                        path: canonicalPath,
                      })
                    }
                  >
                    {playlist.name}
                  </Button>
                ))}
                <TextField
                  size="small"
                  label="New playlist"
                  value={newPlaylistName}
                  onChange={(event) => setNewPlaylistName(event.target.value)}
                />
                <Button
                  size="small"
                  disabled={!newPlaylistName.trim() || createPlaylist.isLoading}
                  onClick={() =>
                    createPlaylist.mutate({
                      name: newPlaylistName.trim(),
                      addPath: canonicalPath,
                    })
                  }
                >
                  Create and add
                </Button>
                <Button
                  size="small"
                  onClick={() => setPlaylistChooserPath(undefined)}
                >
                  Cancel
                </Button>
              </Stack>
            )}
          </Box>
        );
      })}
    </Stack>
  );

  const playlistChoices = [...(playlists.data?.playlists ?? [])].sort(
    (left, right) => {
      if (left.name === "Favorites") return -1;
      if (right.name === "Favorites") return 1;
      return 0;
    }
  );

  const playlistsPanel = (
    <Stack spacing={1}>
      <Typography variant="h6">Playlists</Typography>
      {playlists.isLoading && <Typography>Loading playlists…</Typography>}
      {playlists.isError && (
        <Typography color="error">Playlist storage is unavailable.</Typography>
      )}
      <Stack direction="row" gap={0.75} flexWrap="wrap">
        {playlistChoices.map((playlist) => (
          <Button
            key={playlist.name}
            variant={
              selectedPlaylist === playlist.name ? "contained" : "outlined"
            }
            onClick={() => {
              rememberScroll();
              setSelectedPlaylist(playlist.name);
              setRenamePlaylistName("");
            }}
            sx={{ minHeight: 44, whiteSpace: "nowrap" }}
          >
            {playlist.name} ({playlist.count})
          </Button>
        ))}
      </Stack>
      <Stack direction={{ xs: "column", sm: "row" }} spacing={1}>
        <TextField
          size="small"
          label="New playlist"
          value={newPlaylistName}
          onChange={(event) => setNewPlaylistName(event.target.value)}
          sx={{ flex: 1 }}
        />
        <Button
          variant="outlined"
          disabled={!newPlaylistName.trim() || createPlaylist.isLoading}
          onClick={() =>
            createPlaylist.mutate({ name: newPlaylistName.trim() })
          }
        >
          Create
        </Button>
      </Stack>
      <Divider />
      <Box>
        <Typography variant="h6" sx={trackTitleSx}>
          {selectedPlaylist}
        </Typography>
        {status.data?.context === "PLAYLIST" &&
          status.data.playlist === selectedPlaylist && (
            <Typography variant="caption" color={colors.playing}>
              Playing track {status.data.index} of {status.data.count}
            </Typography>
          )}
      </Box>
      {selectedPlaylistData.data && !selectedPlaylistData.data.reserved && (
        <Stack direction={{ xs: "column", sm: "row" }} spacing={1}>
          <TextField
            size="small"
            label="Rename playlist"
            value={renamePlaylistName}
            onChange={(event) => setRenamePlaylistName(event.target.value)}
            sx={{ flex: 1 }}
          />
          <Button
            disabled={!renamePlaylistName.trim() || renamePlaylist.isLoading}
            onClick={() =>
              renamePlaylist.mutate({
                name: selectedPlaylist,
                newName: renamePlaylistName.trim(),
              })
            }
          >
            Rename
          </Button>
          <Button
            startIcon={<DeleteIcon />}
            disabled={deletePlaylist.isLoading}
            onClick={() => deletePlaylist.mutate(selectedPlaylist)}
            sx={{
              color: MEGAVGM_DELETE_COLOR,
              "&:hover": { color: MEGAVGM_DELETE_HOVER_COLOR },
            }}
          >
            Delete
          </Button>
        </Stack>
      )}
      <Button
        variant="contained"
        disabled={
          (selectedPlaylistData.data?.entries.length ?? 0) === 0 ||
          playlistPlay.isLoading
        }
        onClick={() => {
          const first = selectedPlaylistData.data?.entries[0];
          if (first) requestPlaylistPlay(selectedPlaylist, 0, first.path);
        }}
      >
        Play All
      </Button>
      {selectedPlaylistData.isLoading && (
        <Typography>Loading tracks…</Typography>
      )}
      {!selectedPlaylistData.isLoading &&
        (selectedPlaylistData.data?.entries.length ?? 0) === 0 && (
          <Typography color="text.secondary">
            This playlist is empty. Add a VGM from Browse.
          </Typography>
        )}
      {(selectedPlaylistData.data?.entries ?? []).map((entry, index) => {
        const selectedPending = playTarget?.path === entry.path;
        const activePlaylist =
          status.data?.controllerRunning &&
          status.data.state === "PLAYING" &&
          status.data.context === "PLAYLIST" &&
          status.data.playlist === selectedPlaylist;
        const rowState = trackRowState(
          entry.path,
          status.data?.path,
          selectedPending || switchingPath === entry.path
            ? entry.path
            : undefined,
          activePlaylist
        );
        return (
          <Stack
            key={entry.path}
            direction="row"
            spacing={0.5}
            alignItems="stretch"
            data-track-state={rowState}
            sx={{
              bgcolor:
                rowState === "playing"
                  ? "rgba(119, 221, 232, 0.13)"
                  : colors.surface,
              border: "1px solid",
              borderColor:
                rowState === "pending"
                  ? "rgba(232, 238, 244, 0.35)"
                  : rowState === "playing"
                  ? "rgba(119, 221, 232, 0.55)"
                  : "rgba(154, 169, 183, 0.12)",
              borderRadius: 1.5,
              overflow: "hidden",
              opacity: entry.available ? 1 : 0.55,
            }}
          >
            <Button
              variant="text"
              startIcon={
                rowState === "pending" ? (
                  <CircularProgress size={18} color="inherit" />
                ) : rowState === "playing" ? (
                  <PlayArrowIcon />
                ) : (
                  <AudioFileIcon />
                )
              }
              disabled={!entry.available || selectedPending}
              onClick={() =>
                requestPlaylistPlay(selectedPlaylist, index, entry.path)
              }
              sx={{
                flex: 1,
                minWidth: 0,
                minHeight: 44,
                py: 0.25,
                justifyContent: "flex-start",
                textTransform: "none",
                color: rowState === "playing" ? colors.playing : colors.text,
                overflow: "hidden",
              }}
            >
              <Box component="span" textAlign="left" minWidth={0} width="100%">
                <Box component="span" sx={trackTitleSx}>
                  {entry.title}
                </Box>
                <Box
                  component="span"
                  display="block"
                  color={
                    rowState === "playing" ? colors.playing : "text.secondary"
                  }
                  sx={trackTitleSx}
                  fontSize="0.6875rem"
                  lineHeight={1.1}
                >
                  {rowState === "pending"
                    ? `${pendingLabel(entry.path)} · `
                    : ""}
                  {displayDirectory(entry.directory || undefined)}
                  {!entry.available ? " — Unavailable" : ""}
                </Box>
              </Box>
            </Button>
            <IconButton
              aria-label="Remove from playlist"
              disabled={
                removePlaylistTrack.isLoading || favoriteMutation.isLoading
              }
              onClick={() =>
                selectedPlaylist === "Favorites"
                  ? toggleFavorite(entry.path)
                  : removePlaylistTrack.mutate({
                      name: selectedPlaylist,
                      path: entry.path,
                    })
              }
              sx={{
                minWidth: 44,
                minHeight: 44,
                color: MEGAVGM_DELETE_COLOR,
                "&:hover": { color: MEGAVGM_DELETE_HOVER_COLOR },
              }}
            >
              <DeleteIcon />
            </IconButton>
          </Stack>
        );
      })}
    </Stack>
  );

  const controlsAvailable =
    !!status.data?.controllerRunning &&
    !["stock", "unavailable", "starting", "restoring", "failure"].includes(
      view
    ) &&
    !exit.isLoading;
  const controlsEnabled =
    controlsAvailable &&
    navigationEnabled(
      status.data,
      previous.isLoading || next.isLoading || exit.isLoading
    );
  const stopControlEnabled =
    controlsAvailable && stopEnabled(status.data, stop.isLoading);
  const controllerRepeat = repeatMode(status.data);
  const controllerShuffle = status.data?.shuffle ?? false;
  const playerControls = (
    <MegaVGMPlayerControls
      navigationDisabled={!controlsEnabled}
      stopDisabled={!stopControlEnabled}
      repeat={controllerRepeat}
      repeatDisabled={!controlsAvailable || repeatMutation.isLoading}
      shuffle={controllerShuffle}
      shuffleDisabled={!controlsAvailable || shuffleMutation.isLoading}
      onPrevious={() => {
        clearTransientPlay();
        previous.mutate();
      }}
      onStop={() => {
        clearTransientPlay();
        stop.mutate();
      }}
      onNext={() => {
        clearTransientPlay();
        next.mutate();
      }}
      onRepeat={(mode) => repeatMutation.mutate(repeatCommand(mode))}
      onShuffle={(enabled) => shuffleMutation.mutate(enabled)}
    />
  );

  const notice =
    status.isLoading && !status.data
      ? "Connecting to MegaVGMPlayer…"
      : view === "unavailable"
      ? "Reconnecting to MegaVGMPlayer…"
      : view === "starting"
      ? "Starting MegaVGMPlayer…"
      : view === "restoring" || exit.isLoading
      ? "Closing MegaVGMPlayer…"
      : view === "failure"
      ? "MegaVGMPlayer needs attention."
      : undefined;
  const playbackDetails = status.data?.controllerRunning
    ? playbackContextDetails({
        ...status.data,
        transport: status.data.transport ? transportDisplay.receipt : undefined,
      })
    : undefined;

  return (
    <Box ref={shellRef} sx={pageSx} data-testid="player-shell">
      <Box
        ref={contentRef}
        data-testid="music-content"
        role="region"
        aria-label={tab === "browse" ? "Browse music" : "Playlist tracks"}
        sx={{
          flex: "1 1 0",
          minHeight: 0,
          overflowY: "auto",
          overflowX: "hidden",
          overscrollBehaviorY: "contain",
          p: 2,
          scrollbarGutter: "stable",
        }}
      >
        <Stack spacing={2} sx={{ maxWidth: 900, mx: "auto" }}>
          {notice ? (
            <Typography role="status">{notice}</Typography>
          ) : tab === "browse" ? (
            browsePanel
          ) : (
            playlistsPanel
          )}
          {reconnecting && (
            <Typography color="text.secondary">
              Connection interrupted; reconnecting…
            </Typography>
          )}
          {modeMessage && <Typography color="error">{modeMessage}</Typography>}
          {playMessage && (
            <Typography color="text.secondary">{playMessage}</Typography>
          )}
          {transportDisplay.failed && (
            <Typography color="error">Playback could not switch.</Typography>
          )}
          {favoriteMessage && (
            <Typography color="error">{favoriteMessage}</Typography>
          )}
          {mutationError && (
            <Typography color="error">
              MegaVGMPlayer could not complete the request.
            </Typography>
          )}
        </Stack>
      </Box>

      <Box
        component="section"
        aria-label="Now playing"
        data-testid="mini-player"
        sx={{
          flexShrink: 0,
          bgcolor: colors.surface,
          px: 2,
          pt: 1,
          pb: 0.5,
          borderTop: "1px solid rgba(119,221,232,0.12)",
        }}
      >
        <Box sx={{ maxWidth: 600, mx: "auto", minWidth: 0 }}>
          <Stack direction="row" alignItems="center">
            <Box sx={{ flex: 1, minWidth: 0 }}>
              <Typography
                title={status.data?.title}
                sx={{ ...trackTitleSx, fontWeight: 600, fontSize: "0.95rem" }}
              >
                {status.data?.controllerRunning
                  ? status.data.title || "—"
                  : "Choose your music"}
              </Typography>
            </Box>
            {status.data?.path && status.data.controllerRunning && (
              <IconButton
                aria-label={
                  favoritedPaths.has(status.data.path)
                    ? "Remove current favorite"
                    : "Add current favorite"
                }
                disabled={favoriteMutation.isLoading}
                onClick={() => toggleFavorite(status.data?.path || "")}
                sx={{
                  width: 44,
                  height: 44,
                  color: favoritedPaths.has(status.data.path)
                    ? colors.favorite
                    : colors.secondary,
                }}
              >
                {favoritedPaths.has(status.data.path) ? (
                  <StarIcon />
                ) : (
                  <StarBorderIcon />
                )}
              </IconButton>
            )}
            <IconButton
              aria-label="Player options"
              aria-haspopup="menu"
              aria-expanded={!!optionsAnchor}
              onClick={(event) => setOptionsAnchor(event.currentTarget)}
              sx={{ width: 44, height: 44, color: colors.secondary }}
            >
              <MoreHorizIcon />
            </IconButton>
          </Stack>

          <Box
            data-testid="playback-context"
            sx={{
              display: "flex",
              alignItems: "baseline",
              gap: 1,
              minWidth: 0,
              pb: 0.25,
              color: colors.secondary,
              fontSize: "0.75rem",
            }}
          >
            <Typography
              component="span"
              data-testid="playback-source-chips"
              title={playbackDetails?.sourceAndChips}
              sx={{
                flex: "1 1 auto",
                minWidth: 0,
                overflow: "hidden",
                textOverflow: "ellipsis",
                whiteSpace: "nowrap",
                color: "inherit",
                fontSize: "inherit",
              }}
            >
              {playbackDetails?.sourceAndChips || "Browse or choose a playlist"}
            </Typography>
            {playbackDetails?.position && (
              <Typography
                component="span"
                data-testid="playback-position"
                sx={{
                  flex: "0 0 auto",
                  whiteSpace: "nowrap",
                  color: "inherit",
                  fontSize: "inherit",
                  fontVariantNumeric: "tabular-nums",
                }}
              >
                {playbackDetails.position}
              </Typography>
            )}
          </Box>

          {/* No timing/progress UI until the authoritative API provides values. */}
          <Stack
            direction="row"
            justifyContent="center"
            sx={{ color: colors.secondary, fontSize: "0.65rem" }}
          >
            <span role="status">
              {transportDisplay.switching
                ? "Switching…"
                : status.data?.state === "PREPARING"
                ? "Preparing SID…"
                : playTarget || status.data?.state === "LOADING"
                ? "Loading…"
                : displayState(status.data?.state)}
            </span>
          </Stack>
          {view === "stock" && (
            <Button
              fullWidth
              size="small"
              disabled={
                !lifecycle.startEnabled ||
                !favoritesStartEntry?.available ||
                playlistPlay.isLoading
              }
              onClick={() => {
                if (favoritesStartEntry)
                  requestPlaylistPlay("Favorites", 0, favoritesStartEntry.path);
              }}
            >
              {playlistPlay.isLoading
                ? "Starting…"
                : "Start Favorites playlist"}
            </Button>
          )}
          {playerControls}
        </Box>
      </Box>

      <Tabs
        component="nav"
        aria-label="Music navigation"
        value={tab}
        onChange={(_, value) => selectTab(value)}
        variant="fullWidth"
        sx={{
          flexShrink: 0,
          bgcolor: colors.surface,
          borderTop: "1px solid rgba(119,221,232,0.08)",
          pb: "env(safe-area-inset-bottom)",
          "& .MuiTabs-indicator": { top: 0 },
          "& .MuiTab-root.Mui-selected": {
            color: "#40C5D8",
            bgcolor: "rgba(64,197,216,0.10)",
          },
        }}
      >
        <Tab value="browse" label="Browse" />
        <Tab value="playlists" label="Playlists" />
      </Tabs>
      <Menu
        anchorEl={optionsAnchor}
        open={!!optionsAnchor}
        onClose={() => setOptionsAnchor(null)}
        MenuListProps={{ "aria-label": "Player options" }}
        PaperProps={{ sx: { bgcolor: colors.surface, color: colors.text } }}
      >
        <MenuItem
          sx={{ minHeight: 44 }}
          onClick={() => {
            setOptionsAnchor(null);
            refreshStatus();
          }}
        >
          Refresh status
        </MenuItem>
        <MenuItem
          sx={{ minHeight: 44 }}
          disabled={!lifecycle.exitEnabled}
          onClick={() => {
            setOptionsAnchor(null);
            clearTransientPlay();
            exit.mutate();
          }}
        >
          Exit MegaVGMPlayer
        </MenuItem>
      </Menu>
    </Box>
  );
}
