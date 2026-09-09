package megavgm

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
	"unicode"
)

const (
	DefaultStatusPath           = "/tmp/megavgm_playlist.status"
	DefaultCommandPath          = "/tmp/megavgm_playlist.cmd"
	DefaultCtlPath              = "/media/fat/Scripts/megavgm_ctl"
	DefaultSupervisorStatusPath = "/tmp/megavgm_supervisor.status"
	DefaultSupervisorPath       = "/media/fat/MegaVGMPlayer/megavgm_supervisor"
	DefaultApprovedRoot         = "/media/fat/MegaVGMDrive"
	DefaultFavoritesPath        = "/media/fat/Scripts/.config/megavgm/playlists.json"
	DefaultSnapshotDirectory    = "/tmp"
	DefaultHandoffTracePath     = "/tmp/megavgm_remote_playlist_handoff.log"
	DefaultPlaylistPath         = "/media/fat/MegaVGMDrive/01_Arcade/Galaxy_Force_II_(Sega_Y)"

	MaximumStatusSize   = 64 * 1024
	MaximumBodySize     = 8 * 1024
	MaximumPathLength   = 4096
	MaximumPlayPath     = 4090 // PLAY plus command framing must fit Linux PIPE_BUF.
	DefaultCtlTimeout   = 750 * time.Millisecond
	DefaultStartTimeout = 30 * time.Second
	DefaultExitTimeout  = 32 * time.Second
)

var validStates = map[string]bool{
	"IDLE": true, "LOADING": true, "PLAYING": true, "ENDED": true,
	"FATAL": true, "NEXT": true, "PREV": true, "SUSPENDED": true,
	"PLAY": true, "STOPPED": true, "COMPLETE": true,
}

var validSupervisorModes = map[string]bool{
	"STARTING": true, "MEGAVGM": true, "SHUTTING_DOWN": true,
	"FAILURE": true, "STOCK": true,
}

var validSupervisorMains = map[string]bool{
	"STOCK": true, "STOPPED": true, "MODIFIED": true,
	"UNKNOWN": true, "RESTORE_FAILED": true,
}

var validSupervisorControllers = map[string]bool{
	"STOPPED": true, "RUNNING": true, "UNKNOWN": true,
}

var supervisorStatusKeys = map[string]bool{
	"mode": true, "main": true, "controller": true, "rbf": true,
	"playlist": true, "stock_sha256": true, "modified_sha256": true,
	"controller_pid": true, "controller_exec": true, "controller_exit": true,
	"controller_stderr": true, "controller_trace": true, "main_load_file": true,
	"megavgm_status_at_controller_launch": true, "playlist_command_seen": true,
	"playlist_status_seen": true, "active_main_sha256": true,
	"active_rbf_argv": true, "detail": true,
	"switch_epoch": true, "switch_generation": true, "switch_state": true,
	"current_profile": true, "required_profile": true, "switch_domain": true,
	"switch_baseline": true, "switch_changed": true, "switch_path": true,
}

type Status struct {
	SoundChips            []string         `json:"soundChips,omitempty"`
	Transport             *TransportStatus `json:"transport,omitempty"`
	Mode                  string           `json:"mode"`
	Main                  string           `json:"main"`
	SupervisorController  string           `json:"supervisorController"`
	SupervisorPlaylist    string           `json:"supervisorPlaylist,omitempty"`
	Detail                string           `json:"detail,omitempty"`
	ControllerRunning     bool             `json:"controllerRunning"`
	State                 string           `json:"state,omitempty"`
	Index                 uint64           `json:"index,omitempty"`
	Count                 uint64           `json:"count,omitempty"`
	Path                  string           `json:"path,omitempty"`
	Title                 string           `json:"title,omitempty"`
	Session               uint32           `json:"session,omitempty"`
	LoopCount             uint16           `json:"loopCount,omitempty"`
	Context               string           `json:"context,omitempty"`
	Playlist              string           `json:"playlist,omitempty"`
	Repeat                string           `json:"repeat,omitempty"`
	Shuffle               bool             `json:"shuffle"`
	Traversal             string           `json:"traversal,omitempty"`
	StatusFileMtimeUnixMs int64            `json:"statusFileMtimeUnixMs,omitempty"`
	StatusReadUnixMs      int64            `json:"statusReadUnixMs,omitempty"`
}

type playlistStatus struct {
	SoundChips []string
	State      string
	Index      uint64
	Count      uint64
	Path       string
	Title      string
	Session    uint32
	LoopCount  uint16
	Context    string
	Playlist   string
	Repeat     string
	Shuffle    bool
	Traversal  string
}

type SupervisorStatus struct {
	Transport  *TransportStatus
	Mode       string
	Main       string
	Controller string
	Playlist   string
	Detail     string
}

type Config struct {
	StatusPath           string
	CommandPath          string
	CtlPath              string
	SupervisorStatusPath string
	SupervisorPath       string
	ApprovedRoot         string
	FavoritesPath        string
	SnapshotDirectory    string
	HandoffTracePath     string
	DefaultPlaylistPath  string
	CtlTimeout           time.Duration
	StartTimeout         time.Duration
	ExitTimeout          time.Duration
}

type commandRunner func(context.Context, string, ...string) ([]byte, error)

func runCommandWithoutOutputPipe(ctx context.Context, path string,
	args ...string) ([]byte, error) {
	// Leave stdout/stderr nil so os/exec connects them directly to /dev/null.
	// A long-lived descendant therefore cannot hold a Go capture pipe open.
	err := exec.CommandContext(ctx, path, args...).Run()
	return nil, err
}

type Adapter struct {
	config                    Config
	run                       commandRunner
	startSupervisor           commandRunner
	favorites                 *favoritesStore
	playlistPlayMu            sync.Mutex
	playTraceMu               sync.Mutex
	playlistConvergenceMu     sync.Mutex
	playlistConvergenceID     uint64
	playlistConvergenceCancel context.CancelFunc
}

func DefaultConfig() Config {
	return Config{
		StatusPath: DefaultStatusPath, CommandPath: DefaultCommandPath,
		CtlPath: DefaultCtlPath, SupervisorStatusPath: DefaultSupervisorStatusPath,
		SupervisorPath: DefaultSupervisorPath, ApprovedRoot: DefaultApprovedRoot,
		FavoritesPath:       DefaultFavoritesPath,
		SnapshotDirectory:   DefaultSnapshotDirectory,
		HandoffTracePath:    DefaultHandoffTracePath,
		DefaultPlaylistPath: DefaultPlaylistPath, CtlTimeout: DefaultCtlTimeout,
		StartTimeout: DefaultStartTimeout, ExitTimeout: DefaultExitTimeout,
	}
}

func NewAdapter(config Config) *Adapter {
	adapter := newAdapter(config, func(ctx context.Context, path string, args ...string) ([]byte, error) {
		return exec.CommandContext(ctx, path, args...).CombinedOutput()
	})
	adapter.startSupervisor = runCommandWithoutOutputPipe
	return adapter
}

func newAdapter(config Config, runner commandRunner) *Adapter {
	if config.CtlTimeout <= 0 {
		config.CtlTimeout = DefaultCtlTimeout
	}
	if config.StartTimeout <= 0 {
		config.StartTimeout = DefaultStartTimeout
	}
	if config.ExitTimeout <= 0 {
		config.ExitTimeout = DefaultExitTimeout
	}
	if config.FavoritesPath == "" {
		config.FavoritesPath = DefaultFavoritesPath
	}
	if config.SnapshotDirectory == "" {
		config.SnapshotDirectory = DefaultSnapshotDirectory
	}
	if config.HandoffTracePath == "" {
		config.HandoffTracePath = DefaultHandoffTracePath
	}
	return &Adapter{
		config:    config,
		run:       runner,
		favorites: newFavoritesStore(config.FavoritesPath, config.ApprovedRoot),
	}
}

func readKeyValues(reader io.Reader, allowed map[string]bool, ignoreUnknown bool) (map[string]string, error) {
	limited := io.LimitReader(reader, MaximumStatusSize+1)
	content, err := io.ReadAll(limited)
	if err != nil {
		return nil, fmt.Errorf("read status: %w", err)
	}
	if len(content) > MaximumStatusSize {
		return nil, errors.New("status exceeds size limit")
	}
	if len(content) == 0 {
		return nil, errors.New("empty status")
	}

	values := make(map[string]string)
	scanner := bufio.NewScanner(strings.NewReader(string(content)))
	for scanner.Scan() {
		line := scanner.Text()
		if line == "" {
			return nil, errors.New("empty status line")
		}
		key, value, found := strings.Cut(line, "=")
		if !found || key == "" {
			return nil, errors.New("malformed status line")
		}
		if !allowed[key] {
			if ignoreUnknown {
				continue
			}
			return nil, fmt.Errorf("unknown status key: %s", key)
		}
		if _, exists := values[key]; exists {
			return nil, fmt.Errorf("duplicate status key: %s", key)
		}
		values[key] = value
	}
	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("scan status: %w", err)
	}
	return values, nil
}

func ParseStatus(reader io.Reader) (playlistStatus, error) {
	allowed := map[string]bool{
		"state": true, "index": true, "count": true, "path": true,
		"session": true, "loop_count": true,
		"context": true, "playlist": true,
		"repeat": true, "shuffle": true, "traversal": true,
		"sound_chips": true,
	}
	values, err := readKeyValues(reader, allowed, false)
	if err != nil {
		return playlistStatus{}, err
	}
	for _, key := range []string{"state", "index", "count", "path", "session", "loop_count"} {
		if values[key] == "" {
			return playlistStatus{}, fmt.Errorf("missing status key: %s", key)
		}
	}
	if !validStates[values["state"]] {
		return playlistStatus{}, errors.New("invalid state")
	}
	if len(values["path"]) > MaximumPathLength || hasControl(values["path"]) {
		return playlistStatus{}, errors.New("invalid path")
	}
	index, err := parseUnsigned(values["index"], 64)
	if err != nil || index == 0 {
		return playlistStatus{}, errors.New("invalid index")
	}
	count, err := parseUnsigned(values["count"], 64)
	if err != nil || count == 0 || index > count {
		return playlistStatus{}, errors.New("invalid count")
	}
	session, err := parseUnsigned(values["session"], 32)
	if err != nil {
		return playlistStatus{}, errors.New("invalid session")
	}
	loopCount, err := parseUnsigned(values["loop_count"], 16)
	if err != nil {
		return playlistStatus{}, errors.New("invalid loop_count")
	}
	context := values["context"]
	playlist := values["playlist"]
	if context == "" {
		context = "DIRECTORY"
	}
	if context != "DIRECTORY" && context != "PLAYLIST" {
		return playlistStatus{}, errors.New("invalid context")
	}
	if context == "PLAYLIST" {
		if !validPlaylistName(playlist) {
			return playlistStatus{}, errors.New("invalid playlist")
		}
	} else if playlist != "" {
		return playlistStatus{}, errors.New("directory context has playlist")
	}
	repeat := values["repeat"]
	if repeat == "" {
		repeat = "OFF"
	}
	if repeat != "OFF" && repeat != "ONE" && repeat != "ALL" {
		return playlistStatus{}, errors.New("invalid repeat")
	}
	shuffle := false
	if values["shuffle"] != "" {
		if values["shuffle"] != "0" && values["shuffle"] != "1" {
			return playlistStatus{}, errors.New("invalid shuffle")
		}
		shuffle = values["shuffle"] == "1"
	}
	traversal := values["traversal"]
	if traversal == "" {
		if shuffle {
			traversal = "SHUFFLE"
		} else {
			traversal = "ORDERED"
		}
	}
	if traversal != "ORDERED" && traversal != "SHUFFLE" ||
		(traversal == "SHUFFLE") != shuffle {
		return playlistStatus{}, errors.New("invalid traversal")
	}
	title := strings.TrimSuffix(filepath.Base(values["path"]), ".vgm")
	return playlistStatus{
		SoundChips: parseSoundChips(values["sound_chips"]),
		State:      values["state"], Index: index, Count: count, Path: values["path"],
		Title: title, Session: uint32(session), LoopCount: uint16(loopCount),
		Context: context, Playlist: playlist,
		Repeat: repeat, Shuffle: shuffle, Traversal: traversal,
	}, nil
}

func ParseSupervisorStatus(reader io.Reader) (SupervisorStatus, error) {
	values, err := readKeyValues(reader, supervisorStatusKeys, true)
	if err != nil {
		return SupervisorStatus{}, err
	}
	for _, key := range []string{"mode", "main", "controller", "playlist", "detail"} {
		if _, ok := values[key]; !ok {
			return SupervisorStatus{}, fmt.Errorf("missing supervisor status key: %s", key)
		}
	}
	if !validSupervisorModes[values["mode"]] ||
		!validSupervisorMains[values["main"]] ||
		!validSupervisorControllers[values["controller"]] {
		return SupervisorStatus{}, errors.New("invalid supervisor state")
	}
	if len(values["playlist"]) > MaximumPathLength || hasControl(values["playlist"]) || hasControl(values["detail"]) {
		return SupervisorStatus{}, errors.New("invalid supervisor value")
	}
	transport, err := parseTransportStatus(values)
	if err != nil {
		return SupervisorStatus{}, err
	}
	return SupervisorStatus{
		Transport: transport,
		Mode:      values["mode"], Main: values["main"], Controller: values["controller"],
		Playlist: values["playlist"], Detail: values["detail"],
	}, nil
}

func parseUnsigned(value string, bits int) (uint64, error) {
	if value == "" || strings.TrimSpace(value) != value {
		return 0, errors.New("invalid integer")
	}
	return strconv.ParseUint(value, 10, bits)
}

func hasControl(value string) bool {
	return strings.IndexFunc(value, unicode.IsControl) >= 0
}

func isFIFO(path string) (bool, error) {
	info, err := os.Lstat(path)
	if errors.Is(err, os.ErrNotExist) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	return info.Mode()&os.ModeNamedPipe != 0, nil
}

func isExecutable(path string) bool {
	info, err := os.Stat(path)
	return err == nil && info.Mode().IsRegular() && info.Mode().Perm()&0111 != 0
}

func (a *Adapter) readSupervisorStatus() (SupervisorStatus, error) {
	file, err := os.Open(a.config.SupervisorStatusPath)
	if errors.Is(err, os.ErrNotExist) {
		// A fresh stock boot has no /tmp Supervisor record yet. Only classify that
		// state as STOCK when no playlist command endpoint suggests an active or
		// orphaned controller; the Supervisor's own lock remains the final guard.
		if _, commandErr := os.Lstat(a.config.CommandPath); errors.Is(commandErr, os.ErrNotExist) {
			return SupervisorStatus{Mode: "STOCK", Main: "STOCK", Controller: "STOPPED"}, nil
		}
		return SupervisorStatus{}, err
	}
	if err != nil {
		return SupervisorStatus{}, err
	}
	defer file.Close()
	return ParseSupervisorStatus(file)
}

func writeJSON(w http.ResponseWriter, status int, value interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}

func writeAPIError(w http.ResponseWriter, status int, code string) {
	writeJSON(w, status, struct {
		Error string `json:"error"`
	}{Error: code})
}

func (a *Adapter) HandleStatus(w http.ResponseWriter, _ *http.Request) {
	supervisor, err := a.readSupervisorStatus()
	if errors.Is(err, os.ErrNotExist) {
		writeAPIError(w, http.StatusServiceUnavailable, "supervisor_status_unavailable")
		return
	}
	if err != nil {
		writeAPIError(w, http.StatusInternalServerError, "invalid_supervisor_status")
		return
	}
	status := Status{
		Transport: supervisor.Transport,
		Mode:      supervisor.Mode, Main: supervisor.Main,
		SupervisorController: supervisor.Controller,
		SupervisorPlaylist:   supervisor.Playlist, Detail: supervisor.Detail,
	}
	if supervisor.Mode != "MEGAVGM" {
		writeJSON(w, http.StatusOK, status)
		return
	}

	running, err := isFIFO(a.config.CommandPath)
	if err != nil {
		writeAPIError(w, http.StatusInternalServerError, "controller_check_failed")
		return
	}
	if !running || supervisor.Controller != "RUNNING" {
		writeJSON(w, http.StatusOK, status)
		return
	}
	file, err := os.Open(a.config.StatusPath)
	if errors.Is(err, os.ErrNotExist) {
		writeAPIError(w, http.StatusServiceUnavailable, "status_unavailable")
		return
	}
	if err != nil {
		writeAPIError(w, http.StatusInternalServerError, "status_read_failed")
		return
	}
	defer file.Close()
	fileInfo, statErr := file.Stat()
	playlist, err := ParseStatus(file)
	if err != nil {
		writeAPIError(w, http.StatusInternalServerError, "invalid_status")
		return
	}
	status.ControllerRunning = true
	status.State, status.Index, status.Count = playlist.State, playlist.Index, playlist.Count
	status.Path, status.Title = playlist.Path, playlist.Title
	status.SoundChips = playlist.SoundChips
	status.Session, status.LoopCount = playlist.Session, playlist.LoopCount
	status.Context, status.Playlist = playlist.Context, playlist.Playlist
	status.Repeat, status.Shuffle, status.Traversal =
		playlist.Repeat, playlist.Shuffle, playlist.Traversal
	if statErr == nil {
		status.StatusFileMtimeUnixMs = fileInfo.ModTime().UnixMilli()
	}
	status.StatusReadUnixMs = time.Now().UnixMilli()
	writeJSON(w, http.StatusOK, status)
}

type startRequest struct {
	Path string `json:"path"`
}

type lifecycleResponse struct {
	Accepted bool   `json:"accepted"`
	Result   string `json:"result"`
	Mode     string `json:"mode"`
}

type BrowseEntry struct {
	Name string `json:"name"`
	Type string `json:"type"`
}

type BrowseResponse struct {
	Path    string        `json:"path"`
	Parent  string        `json:"parent"`
	Entries []BrowseEntry `json:"entries"`
}

type playResponse struct {
	Accepted bool   `json:"accepted"`
	Mode     string `json:"mode"`
	Path     string `json:"path"`
}

func decodeStartRequest(request *http.Request) (startRequest, error) {
	body, err := io.ReadAll(io.LimitReader(request.Body, MaximumBodySize+1))
	if err != nil {
		return startRequest{}, err
	}
	if len(body) > MaximumBodySize {
		return startRequest{}, errors.New("request exceeds size limit")
	}
	decoder := json.NewDecoder(strings.NewReader(string(body)))
	decoder.DisallowUnknownFields()
	var input startRequest
	if err := decoder.Decode(&input); err != nil {
		return input, err
	}
	var extra interface{}
	if err := decoder.Decode(&extra); !errors.Is(err, io.EOF) {
		return input, errors.New("trailing JSON value")
	}
	return input, nil
}

func canonicalDirectory(path, root string) (string, error) {
	if path == "" || len(path) > MaximumPathLength || !filepath.IsAbs(path) || hasControl(path) {
		return "", errors.New("invalid path")
	}
	canonicalRoot, err := filepath.EvalSymlinks(root)
	if err != nil {
		return "", errors.New("approved root unavailable")
	}
	canonicalPath, err := filepath.EvalSymlinks(path)
	if err != nil {
		return "", errors.New("playlist directory unavailable")
	}
	info, err := os.Stat(canonicalPath)
	if err != nil || !info.IsDir() {
		return "", errors.New("playlist path is not a directory")
	}
	relative, err := filepath.Rel(canonicalRoot, canonicalPath)
	if err != nil || relative == ".." || strings.HasPrefix(relative, ".."+string(filepath.Separator)) {
		return "", errors.New("playlist path is outside approved root")
	}
	return canonicalPath, nil
}

func pathHasDotDot(path string) bool {
	for _, component := range strings.Split(filepath.ToSlash(path), "/") {
		if component == ".." {
			return true
		}
	}
	return false
}

func withinRoot(root, path string) bool {
	relative, err := filepath.Rel(root, path)
	return err == nil && relative != ".." &&
		!strings.HasPrefix(relative, ".."+string(filepath.Separator))
}

func canonicalBrowseDirectory(path, root string) (string, string, error) {
	if len(path) > MaximumPathLength || hasControl(path) || pathHasDotDot(path) {
		return "", "", errors.New("invalid browse path")
	}
	canonicalRoot, err := filepath.EvalSymlinks(root)
	if err != nil {
		return "", "", errors.New("approved root unavailable")
	}
	candidate := path
	if candidate == "" {
		candidate = canonicalRoot
	} else if !filepath.IsAbs(candidate) {
		candidate = filepath.Join(canonicalRoot, filepath.FromSlash(candidate))
	}
	canonicalPath, err := filepath.EvalSymlinks(candidate)
	if err != nil {
		return "", "", errors.New("browse directory unavailable")
	}
	if !withinRoot(canonicalRoot, canonicalPath) {
		return "", "", errors.New("browse path outside approved root")
	}
	info, err := os.Stat(canonicalPath)
	if err != nil || !info.IsDir() {
		return "", "", errors.New("browse path is not a directory")
	}
	relative, err := filepath.Rel(canonicalRoot, canonicalPath)
	if err != nil {
		return "", "", errors.New("browse relative path failed")
	}
	if relative == "." {
		relative = ""
	}
	return canonicalPath, filepath.ToSlash(relative), nil
}

func canonicalVGM(path, root string) (string, string, error) {
	if path == "" || len(path) > MaximumPlayPath || hasControl(path) ||
		pathHasDotDot(path) {
		return "", "", errors.New("invalid VGM path")
	}
	canonicalRoot, err := filepath.EvalSymlinks(root)
	if err != nil {
		return "", "", errors.New("approved root unavailable")
	}
	candidate := path
	if !filepath.IsAbs(candidate) {
		candidate = filepath.Join(canonicalRoot, filepath.FromSlash(candidate))
	}
	if info, err := os.Lstat(candidate); err != nil ||
		info.Mode()&os.ModeSymlink != 0 {
		return "", "", errors.New("VGM path unavailable")
	}
	canonicalPath, err := filepath.EvalSymlinks(candidate)
	if err != nil || !withinRoot(canonicalRoot, canonicalPath) {
		return "", "", errors.New("VGM path outside approved root")
	}
	info, err := os.Stat(canonicalPath)
	if err != nil || !info.Mode().IsRegular() ||
		!strings.HasSuffix(filepath.Base(canonicalPath), ".vgm") {
		return "", "", errors.New("path is not a regular .vgm file")
	}
	return canonicalPath, filepath.Dir(canonicalPath), nil
}

func (a *Adapter) HandleBrowse(w http.ResponseWriter, r *http.Request) {
	directory, relative, err := canonicalBrowseDirectory(
		r.URL.Query().Get("path"), a.config.ApprovedRoot)
	if err != nil {
		writeAPIError(w, http.StatusBadRequest, "invalid_browse_path")
		return
	}
	contents, err := os.ReadDir(directory)
	if err != nil {
		writeAPIError(w, http.StatusNotFound, "browse_directory_unavailable")
		return
	}
	entries := make([]BrowseEntry, 0, len(contents))
	for _, entry := range contents {
		if strings.HasPrefix(entry.Name(), ".") ||
			entry.Type()&os.ModeSymlink != 0 {
			continue
		}
		info, infoErr := entry.Info()
		if infoErr != nil {
			continue
		}
		if info.IsDir() {
			entries = append(entries, BrowseEntry{Name: entry.Name(), Type: "directory"})
		} else if info.Mode().IsRegular() && strings.HasSuffix(entry.Name(), ".vgm") {
			entries = append(entries, BrowseEntry{Name: entry.Name(), Type: "file"})
		}
	}
	sort.Slice(entries, func(i, j int) bool { return entries[i].Name < entries[j].Name })
	parent := ""
	if relative != "" {
		parent = filepath.ToSlash(filepath.Dir(relative))
		if parent == "." {
			parent = ""
		}
	}
	writeJSON(w, http.StatusOK, BrowseResponse{
		Path: relative, Parent: parent, Entries: entries,
	})
}

func sameCanonicalPath(left, right string) bool {
	if left == "" || right == "" {
		return false
	}
	a, errA := filepath.EvalSymlinks(left)
	b, errB := filepath.EvalSymlinks(right)
	return errA == nil && errB == nil && a == b
}

func (a *Adapter) waitForSupervisorStatus(ctx context.Context,
	matches func(SupervisorStatus) bool) (SupervisorStatus, error) {
	ticker := time.NewTicker(50 * time.Millisecond)
	defer ticker.Stop()
	var last SupervisorStatus
	var lastErr error
	for {
		last, lastErr = a.readSupervisorStatus()
		if lastErr == nil && matches(last) {
			return last, nil
		}
		select {
		case <-ctx.Done():
			if lastErr != nil {
				return last, lastErr
			}
			return last, ctx.Err()
		case <-ticker.C:
		}
	}
}

func (a *Adapter) HandleStart(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("X-MegaVGM-Play-Handler", "directory-start")
	input, err := decodeStartRequest(r)
	if err != nil {
		writeAPIError(w, http.StatusBadRequest, "invalid_request")
		return
	}
	playlist, err := canonicalDirectory(input.Path, a.config.ApprovedRoot)
	if err != nil {
		writeAPIError(w, http.StatusBadRequest, "invalid_playlist_path")
		return
	}
	status, err := a.readSupervisorStatus()
	if errors.Is(err, os.ErrNotExist) {
		writeAPIError(w, http.StatusServiceUnavailable, "supervisor_status_unavailable")
		return
	}
	if err != nil {
		writeAPIError(w, http.StatusInternalServerError, "invalid_supervisor_status")
		return
	}
	a.appendPlaylistHandoffTrace(playlistHandoffTrace{
		Event: "remote_http", Method: r.Method, RequestPath: r.URL.Path,
		Query: r.URL.RawQuery, Handler: "HandleStart", Context: "PARENT_FOLDER",
		SupervisorMode: status.Mode, Directory: playlist,
		RequestBody: mustJSON(startRequest{Path: input.Path}),
	})
	if status.Mode == "MEGAVGM" {
		if status.Main == "MODIFIED" && status.Controller == "RUNNING" && sameCanonicalPath(status.Playlist, playlist) {
			writeJSON(w, http.StatusOK, lifecycleResponse{true, "ALREADY_ACTIVE", "MEGAVGM"})
			return
		}
		writeAPIError(w, http.StatusConflict, "megavgm_already_active")
		return
	}
	if status.Mode != "STOCK" {
		writeAPIError(w, http.StatusConflict, "supervisor_busy")
		return
	}
	if !isExecutable(a.config.SupervisorPath) {
		writeAPIError(w, http.StatusServiceUnavailable, "supervisor_unavailable")
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), a.config.StartTimeout)
	defer cancel()
	_, runErr := a.run(ctx, a.config.SupervisorPath, "enter", playlist)
	after, statusErr := a.readSupervisorStatus()
	active := func(status SupervisorStatus) bool {
		return status.Mode == "MEGAVGM" && status.Main == "MODIFIED" &&
			status.Controller == "RUNNING" &&
			sameCanonicalPath(status.Playlist, playlist)
	}
	if runErr == nil && (statusErr != nil || !active(after)) {
		after, statusErr = a.waitForSupervisorStatus(ctx, active)
	}
	if statusErr == nil && active(after) {
		writeJSON(w, http.StatusOK, lifecycleResponse{true, "MEGAVGM_MODE_ACTIVE", "MEGAVGM"})
		return
	}
	if errors.Is(ctx.Err(), context.DeadlineExceeded) {
		writeAPIError(w, http.StatusGatewayTimeout, "supervisor_start_timeout")
		return
	}
	if runErr != nil {
		writeAPIError(w, http.StatusBadGateway, "supervisor_start_failed")
		return
	}
	if statusErr != nil {
		writeAPIError(w, http.StatusBadGateway, "supervisor_status_not_confirmed")
		return
	}
	writeAPIError(w, http.StatusBadGateway, "supervisor_start_not_active")
}

func (a *Adapter) HandleExit(w http.ResponseWriter, r *http.Request) {
	status, err := a.readSupervisorStatus()
	if errors.Is(err, os.ErrNotExist) {
		writeAPIError(w, http.StatusServiceUnavailable, "supervisor_status_unavailable")
		return
	}
	if err != nil {
		writeAPIError(w, http.StatusInternalServerError, "invalid_supervisor_status")
		return
	}
	if status.Mode == "STOCK" {
		writeJSON(w, http.StatusOK, lifecycleResponse{true, "ALREADY_STOPPED", "STOCK"})
		return
	}
	if status.Mode == "SHUTTING_DOWN" {
		writeJSON(w, http.StatusAccepted, lifecycleResponse{true, "RESTORE_IN_PROGRESS", "SHUTTING_DOWN"})
		return
	}
	if !isExecutable(a.config.SupervisorPath) {
		writeAPIError(w, http.StatusServiceUnavailable, "supervisor_unavailable")
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), a.config.ExitTimeout)
	defer cancel()
	output, runErr := a.run(ctx, a.config.SupervisorPath, "exit")
	after, statusErr := a.readSupervisorStatus()
	if statusErr == nil {
		if after.Mode == "STOCK" {
			writeJSON(w, http.StatusOK, lifecycleResponse{true, "STOCK_MISTER_RESTORED", "STOCK"})
			return
		}
		if after.Mode == "SHUTTING_DOWN" {
			writeJSON(w, http.StatusAccepted, lifecycleResponse{true, "RESTORE_IN_PROGRESS", "SHUTTING_DOWN"})
			return
		}
	}
	if strings.Contains(string(output), "RESTORE_IN_PROGRESS") {
		writeJSON(w, http.StatusAccepted, lifecycleResponse{true, "RESTORE_IN_PROGRESS", "SHUTTING_DOWN"})
		return
	}
	if errors.Is(ctx.Err(), context.DeadlineExceeded) {
		writeAPIError(w, http.StatusGatewayTimeout, "supervisor_exit_timeout")
		return
	}
	if runErr != nil {
		writeAPIError(w, http.StatusBadGateway, "supervisor_exit_failed")
		return
	}
	writeAPIError(w, http.StatusBadGateway, "stock_restore_not_confirmed")
}

func (a *Adapter) HandleNext(w http.ResponseWriter, r *http.Request) {
	a.handleNavigation(w, r, "next")
}

func (a *Adapter) HandlePrevious(w http.ResponseWriter, r *http.Request) {
	a.handleNavigation(w, r, "prev")
}

// HandleStop delegates transport ownership to the playlist controller. It does
// not exit MegaVGM mode or address Main/FPGA directly.
func (a *Adapter) HandleStop(w http.ResponseWriter, r *http.Request) {
	a.handleNavigation(w, r, "stop")
}

type repeatRequest struct {
	Mode string `json:"mode"`
}

type shuffleRequest struct {
	Enabled *bool `json:"enabled"`
}

func decodeStrictJSON(request *http.Request, target interface{}) error {
	body, err := io.ReadAll(io.LimitReader(request.Body, MaximumBodySize+1))
	if err != nil {
		return err
	}
	if len(body) > MaximumBodySize {
		return errors.New("request exceeds size limit")
	}
	decoder := json.NewDecoder(strings.NewReader(string(body)))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(target); err != nil {
		return err
	}
	var extra interface{}
	if err := decoder.Decode(&extra); !errors.Is(err, io.EOF) {
		return errors.New("trailing JSON value")
	}
	return nil
}

func (a *Adapter) HandleRepeat(w http.ResponseWriter, r *http.Request) {
	var input repeatRequest
	if err := decodeStrictJSON(r, &input); err != nil ||
		(input.Mode != "off" && input.Mode != "one" && input.Mode != "all") {
		writeAPIError(w, http.StatusBadRequest, "invalid_repeat_mode")
		return
	}
	a.handleMode(w, r, "repeat", input.Mode)
}

func (a *Adapter) HandleShuffle(w http.ResponseWriter, r *http.Request) {
	var input shuffleRequest
	if err := decodeStrictJSON(r, &input); err != nil || input.Enabled == nil {
		writeAPIError(w, http.StatusBadRequest, "invalid_shuffle_mode")
		return
	}
	value := "off"
	if *input.Enabled {
		value = "on"
	}
	a.handleMode(w, r, "shuffle", value)
}

func (a *Adapter) handleMode(w http.ResponseWriter, r *http.Request,
	action, value string) {
	status, err := a.readSupervisorStatus()
	if err != nil || status.Mode != "MEGAVGM" || status.Controller != "RUNNING" {
		writeAPIError(w, http.StatusServiceUnavailable, "controller_unavailable")
		return
	}
	running, err := isFIFO(a.config.CommandPath)
	if err != nil || !running || !isExecutable(a.config.CtlPath) {
		writeAPIError(w, http.StatusServiceUnavailable, "controller_unavailable")
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), a.config.CtlTimeout)
	defer cancel()
	if _, err := a.run(ctx, a.config.CtlPath, action, value); err != nil {
		if errors.Is(ctx.Err(), context.DeadlineExceeded) {
			writeAPIError(w, http.StatusGatewayTimeout, "control_timeout")
		} else {
			writeAPIError(w, http.StatusBadGateway, "control_failed")
		}
		return
	}
	writeJSON(w, http.StatusAccepted, struct {
		Accepted bool   `json:"accepted"`
		Action   string `json:"action"`
		Value    string `json:"value"`
	}{Accepted: true, Action: action, Value: value})
}

func (a *Adapter) HandlePlay(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("X-MegaVGM-Play-Handler", "generic-file")
	input, err := decodeStartRequest(r)
	if err != nil {
		writeAPIError(w, http.StatusBadRequest, "invalid_request")
		return
	}
	selected, directory, err := canonicalVGM(input.Path, a.config.ApprovedRoot)
	if err != nil {
		writeAPIError(w, http.StatusBadRequest, "invalid_vgm_path")
		return
	}
	status, err := a.readSupervisorStatus()
	if err != nil {
		writeAPIError(w, http.StatusServiceUnavailable, "supervisor_status_unavailable")
		return
	}
	a.appendPlaylistHandoffTrace(playlistHandoffTrace{
		Event: "remote_http", Method: r.Method, RequestPath: r.URL.Path,
		Query: r.URL.RawQuery, Handler: "HandlePlay", Context: "PARENT_FOLDER",
		SupervisorMode: status.Mode, Selected: selected,
		Directory: directory, RequestBody: mustJSON(startRequest{Path: input.Path}),
	})
	if status.Mode == "STOCK" {
		if !isExecutable(a.config.SupervisorPath) {
			writeAPIError(w, http.StatusServiceUnavailable, "supervisor_unavailable")
			return
		}
		ctx, cancel := context.WithTimeout(r.Context(), a.config.StartTimeout)
		defer cancel()
		_, runErr := a.run(ctx, a.config.SupervisorPath, "enter",
			"--start-file", selected, directory)
		after, statusErr := a.readSupervisorStatus()
		active := func(status SupervisorStatus) bool {
			return status.Mode == "MEGAVGM" && status.Main == "MODIFIED" &&
				status.Controller == "RUNNING" &&
				sameCanonicalPath(status.Playlist, directory)
		}
		if runErr == nil && (statusErr != nil || !active(after)) {
			after, statusErr = a.waitForSupervisorStatus(ctx, active)
		}
		if statusErr == nil && active(after) {
			writeJSON(w, http.StatusAccepted,
				playResponse{Accepted: true, Mode: "MEGAVGM", Path: selected})
			return
		}
		if errors.Is(ctx.Err(), context.DeadlineExceeded) {
			writeAPIError(w, http.StatusGatewayTimeout, "supervisor_start_timeout")
		} else if runErr != nil {
			writeAPIError(w, http.StatusBadGateway, "supervisor_start_failed")
		} else {
			writeAPIError(w, http.StatusBadGateway, "supervisor_start_not_active")
		}
		return
	}
	if status.Mode != "MEGAVGM" || status.Main != "MODIFIED" ||
		status.Controller != "RUNNING" {
		writeAPIError(w, http.StatusConflict, "supervisor_busy")
		return
	}
	running, err := isFIFO(a.config.CommandPath)
	if err != nil || !running || !isExecutable(a.config.CtlPath) {
		writeAPIError(w, http.StatusServiceUnavailable, "controller_unavailable")
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), a.config.CtlTimeout)
	defer cancel()
	if _, err := a.run(ctx, a.config.CtlPath, "play", selected); err != nil {
		if errors.Is(ctx.Err(), context.DeadlineExceeded) {
			writeAPIError(w, http.StatusGatewayTimeout, "control_timeout")
		} else {
			writeAPIError(w, http.StatusBadGateway, "control_failed")
		}
		return
	}
	writeJSON(w, http.StatusAccepted,
		playResponse{Accepted: true, Mode: "MEGAVGM", Path: selected})
}

func (a *Adapter) handleNavigation(w http.ResponseWriter, r *http.Request, action string) {
	status, err := a.readSupervisorStatus()
	if err != nil || status.Mode != "MEGAVGM" || status.Controller != "RUNNING" {
		writeAPIError(w, http.StatusServiceUnavailable, "controller_unavailable")
		return
	}
	running, err := isFIFO(a.config.CommandPath)
	if err != nil || !running {
		writeAPIError(w, http.StatusServiceUnavailable, "controller_unavailable")
		return
	}
	if !isExecutable(a.config.CtlPath) {
		writeAPIError(w, http.StatusServiceUnavailable, "control_client_unavailable")
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), a.config.CtlTimeout)
	defer cancel()
	if _, err := a.run(ctx, a.config.CtlPath, action); err != nil {
		if errors.Is(ctx.Err(), context.DeadlineExceeded) {
			writeAPIError(w, http.StatusGatewayTimeout, "control_timeout")
			return
		}
		writeAPIError(w, http.StatusBadGateway, "control_failed")
		return
	}
	writeJSON(w, http.StatusAccepted, struct {
		Accepted bool `json:"accepted"`
	}{Accepted: true})
}
