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
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/gorilla/mux"
)

type PlaylistSummary struct {
	Name           string `json:"name"`
	Reserved       bool   `json:"reserved"`
	Count          int    `json:"count"`
	AvailableCount int    `json:"availableCount"`
}

type PlaylistsResponse struct {
	Version   int               `json:"version"`
	Playlists []PlaylistSummary `json:"playlists"`
}

type PlaylistResponse struct {
	Version  int             `json:"version"`
	Name     string          `json:"name"`
	Reserved bool            `json:"reserved"`
	Entries  []FavoriteEntry `json:"entries"`
}

type playlistNameRequest struct {
	Name string `json:"name"`
}
type playlistTrackRequest struct {
	Path string `json:"path"`
}
type playlistPlayRequest struct {
	Index *int   `json:"index,omitempty"`
	Path  string `json:"path,omitempty"`
}
type playlistMutationResponse struct {
	Accepted bool   `json:"accepted"`
	Name     string `json:"name"`
}
type playlistPlayResponse struct {
	Accepted bool   `json:"accepted"`
	Mode     string `json:"mode"`
	Playlist string `json:"playlist"`
	Path     string `json:"path"`
	Index    int    `json:"index"`
	Count    int    `json:"count"`
}

type playlistHandoffTrace struct {
	Timestamp      string   `json:"timestamp"`
	Event          string   `json:"event"`
	Method         string   `json:"method,omitempty"`
	RequestPath    string   `json:"request_path,omitempty"`
	Query          string   `json:"query,omitempty"`
	RequestBody    string   `json:"request_body,omitempty"`
	Handler        string   `json:"handler,omitempty"`
	Context        string   `json:"context,omitempty"`
	SupervisorMode string   `json:"supervisor_mode"`
	Playlist       string   `json:"playlist"`
	PlaylistCount  int      `json:"playlist_count"`
	SelectedIndex  int      `json:"selected_index"`
	Selected       string   `json:"selected"`
	Directory      string   `json:"directory,omitempty"`
	SnapshotPath   string   `json:"snapshot_path"`
	Executable     string   `json:"executable"`
	Argv           []string `json:"argv"`
	ElapsedMS      int64    `json:"elapsed_ms,omitempty"`
	Deadline       string   `json:"deadline,omitempty"`
	HTTPStatus     int      `json:"http_status,omitempty"`
	Result         string   `json:"result,omitempty"`
	StatusState    string   `json:"status_state,omitempty"`
	StatusContext  string   `json:"status_context,omitempty"`
	StatusPlaylist string   `json:"status_playlist,omitempty"`
	StatusPath     string   `json:"status_path,omitempty"`
	StatusIndex    uint64   `json:"status_index,omitempty"`
	StatusCount    uint64   `json:"status_count,omitempty"`
	StatusSession  uint32   `json:"status_session,omitempty"`
	Mismatched     []string `json:"mismatched_fields,omitempty"`
	StatusError    string   `json:"status_error,omitempty"`
	ErrorCode      string   `json:"error_code,omitempty"`
	OperationID    uint64   `json:"operation_id,omitempty"`
	Phase          string   `json:"phase,omitempty"`
}

func mustJSON(value interface{}) string {
	data, err := json.Marshal(value)
	if err != nil {
		return ""
	}
	return string(data)
}

func (a *Adapter) appendPlaylistHandoffTrace(trace playlistHandoffTrace) {
	a.playTraceMu.Lock()
	defer a.playTraceMu.Unlock()
	trace.Timestamp = time.Now().UTC().Format(time.RFC3339Nano)
	data, err := json.Marshal(trace)
	if err != nil {
		return
	}
	file, err := os.OpenFile(a.config.HandoffTracePath,
		os.O_WRONLY|os.O_CREATE|os.O_APPEND, 0600)
	if err != nil {
		return
	}
	_, _ = file.Write(append(data, '\n'))
	_ = file.Close()
}

func decodeJSONBody(request *http.Request, destination interface{}) error {
	body, err := io.ReadAll(io.LimitReader(request.Body, MaximumBodySize+1))
	if err != nil {
		return err
	}
	if len(body) > MaximumBodySize {
		return errors.New("request exceeds size limit")
	}
	decoder := json.NewDecoder(strings.NewReader(string(body)))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(destination); err != nil {
		return err
	}
	var extra interface{}
	if err := decoder.Decode(&extra); !errors.Is(err, io.EOF) {
		return errors.New("trailing JSON value")
	}
	return nil
}

func playlistName(request *http.Request) (string, bool) {
	name := mux.Vars(request)["name"]
	return name, validPlaylistName(name)
}

func playlistResponse(document favoritesDocument, name, root string) (PlaylistResponse, bool) {
	paths, exists := document.Playlists[name]
	if !exists {
		return PlaylistResponse{}, false
	}
	entries := make([]FavoriteEntry, 0, len(paths))
	for _, path := range paths {
		entries = append(entries, favoriteEntry(path, root))
	}
	return PlaylistResponse{Version: document.Version, Name: name,
		Reserved: name == favoritesPlaylistName, Entries: entries}, true
}

func (a *Adapter) HandlePlaylists(w http.ResponseWriter, _ *http.Request) {
	document, err := a.favorites.document()
	if err != nil {
		writeAPIError(w, 500, "playlists_storage_unavailable")
		return
	}
	names := make([]string, 0, len(document.Playlists)-1)
	for name := range document.Playlists {
		if name != favoritesPlaylistName {
			names = append(names, name)
		}
	}
	sort.Strings(names)
	names = append([]string{favoritesPlaylistName}, names...)
	response := PlaylistsResponse{Version: document.Version, Playlists: make([]PlaylistSummary, 0, len(names))}
	for _, name := range names {
		paths := document.Playlists[name]
		available := 0
		for _, path := range paths {
			if favoriteAvailable(path, a.config.ApprovedRoot) {
				available++
			}
		}
		response.Playlists = append(response.Playlists, PlaylistSummary{Name: name,
			Reserved: name == favoritesPlaylistName, Count: len(paths), AvailableCount: available})
	}
	writeJSON(w, 200, response)
}

func (a *Adapter) HandleCreatePlaylist(w http.ResponseWriter, r *http.Request) {
	var input playlistNameRequest
	if decodeJSONBody(r, &input) != nil || !validPlaylistName(input.Name) || input.Name == favoritesPlaylistName {
		writeAPIError(w, 400, "invalid_playlist_name")
		return
	}
	err := a.favorites.createPlaylist(input.Name)
	if errors.Is(err, errPlaylistExists) {
		writeAPIError(w, 409, "playlist_exists")
		return
	}
	if err != nil {
		writeAPIError(w, 500, "playlists_write_failed")
		return
	}
	writeJSON(w, 201, playlistMutationResponse{Accepted: true, Name: input.Name})
}

func (a *Adapter) HandlePlaylist(w http.ResponseWriter, r *http.Request) {
	name, valid := playlistName(r)
	if !valid {
		writeAPIError(w, 400, "invalid_playlist_name")
		return
	}
	document, err := a.favorites.document()
	if err != nil {
		writeAPIError(w, 500, "playlists_storage_unavailable")
		return
	}
	response, exists := playlistResponse(document, name, a.config.ApprovedRoot)
	if !exists {
		writeAPIError(w, 404, "playlist_not_found")
		return
	}
	writeJSON(w, 200, response)
}

func (a *Adapter) HandleRenamePlaylist(w http.ResponseWriter, r *http.Request) {
	name, valid := playlistName(r)
	var input playlistNameRequest
	if !valid || decodeJSONBody(r, &input) != nil || !validPlaylistName(input.Name) {
		writeAPIError(w, 400, "invalid_playlist_name")
		return
	}
	err := a.favorites.renamePlaylist(name, input.Name)
	switch {
	case errors.Is(err, errReservedPlaylist):
		writeAPIError(w, 409, "reserved_playlist")
	case errors.Is(err, errPlaylistMissing):
		writeAPIError(w, 404, "playlist_not_found")
	case errors.Is(err, errPlaylistExists):
		writeAPIError(w, 409, "playlist_exists")
	case err != nil:
		writeAPIError(w, 500, "playlists_write_failed")
	default:
		writeJSON(w, 200, playlistMutationResponse{Accepted: true, Name: input.Name})
	}
}

func (a *Adapter) HandleDeletePlaylist(w http.ResponseWriter, r *http.Request) {
	name, valid := playlistName(r)
	if !valid {
		writeAPIError(w, 400, "invalid_playlist_name")
		return
	}
	err := a.favorites.deletePlaylist(name)
	switch {
	case errors.Is(err, errReservedPlaylist):
		writeAPIError(w, 409, "reserved_playlist")
	case errors.Is(err, errPlaylistMissing):
		writeAPIError(w, 404, "playlist_not_found")
	case err != nil:
		writeAPIError(w, 500, "playlists_write_failed")
	default:
		writeJSON(w, 200, playlistMutationResponse{Accepted: true, Name: name})
	}
}

func (a *Adapter) HandleAddPlaylistTrack(w http.ResponseWriter, r *http.Request) {
	a.handlePlaylistTrack(w, r, true)
}
func (a *Adapter) HandleRemovePlaylistTrack(w http.ResponseWriter, r *http.Request) {
	a.handlePlaylistTrack(w, r, false)
}
func (a *Adapter) handlePlaylistTrack(w http.ResponseWriter, r *http.Request, add bool) {
	name, valid := playlistName(r)
	var input playlistTrackRequest
	if !valid || decodeJSONBody(r, &input) != nil {
		writeAPIError(w, 400, "invalid_request")
		return
	}
	path := ""
	var err error
	if add {
		path, _, err = canonicalVGM(input.Path, a.config.ApprovedRoot)
	} else {
		path, err = favoritePathIdentity(input.Path, a.config.ApprovedRoot)
	}
	if err != nil {
		writeAPIError(w, 400, "invalid_vgm_path")
		return
	}
	if add {
		err = a.favorites.addTrack(name, path)
	} else {
		err = a.favorites.removeTrack(name, path)
	}
	if errors.Is(err, errPlaylistMissing) {
		writeAPIError(w, 404, "playlist_not_found")
		return
	}
	if err != nil {
		writeAPIError(w, 500, "playlists_write_failed")
		return
	}
	writeJSON(w, 200, struct {
		Accepted bool   `json:"accepted"`
		Name     string `json:"name"`
		Path     string `json:"path"`
	}{true, name, path})
}

func writePlaylistSnapshot(directory, name string, paths []string, start int) (string, error) {
	file, err := os.CreateTemp(directory, "megavgm_playlist.snapshot-")
	if err != nil {
		return "", err
	}
	path := file.Name()
	remove := true
	defer func() {
		if remove {
			_ = os.Remove(path)
		}
	}()
	if err := file.Chmod(0600); err != nil {
		_ = file.Close()
		return "", err
	}
	writer := bufio.NewWriter(file)
	if _, err = fmt.Fprintf(writer, "MEGAVGM_PLAYLIST_V1\nNAME %s\nSTART %d\nCOUNT %d\n", name, start, len(paths)); err == nil {
		for _, item := range paths {
			_, err = fmt.Fprintf(writer, "PATH %s\n", item)
			if err != nil {
				break
			}
		}
	}
	if err == nil {
		err = writer.Flush()
	}
	if err == nil {
		err = file.Sync()
	}
	closeErr := file.Close()
	if err == nil {
		err = closeErr
	}
	if err != nil {
		return "", err
	}
	remove = false
	return path, nil
}

func (a *Adapter) waitForPlayingPlaylist(ctx context.Context, selected,
	name string, index, count int) bool {
	return a.waitForPlayingPlaylistOperation(ctx, selected, name, index, count, 0,
		time.Now(), false, 0)
}

func (a *Adapter) waitForPlayingPlaylistOperation(ctx context.Context, selected,
	name string, index, count int, operationID uint64, requestStarted time.Time,
	requireNewSession bool, baselineSession uint32) bool {
	deadline := ""
	if value, ok := ctx.Deadline(); ok {
		deadline = value.UTC().Format(time.RFC3339Nano)
	}
	lastObservation := ""
	ticker := time.NewTicker(50 * time.Millisecond)
	defer ticker.Stop()
	for {
		status := playlistStatus{}
		statusErr := ""
		file, err := os.Open(a.config.StatusPath)
		if err == nil {
			var parseErr error
			status, parseErr = ParseStatus(file)
			_ = file.Close()
			if parseErr != nil {
				statusErr = parseErr.Error()
			}
		} else {
			statusErr = err.Error()
		}
		mismatched := make([]string, 0, 6)
		if statusErr != "" {
			mismatched = append(mismatched, "status")
		} else {
			if status.State != "PLAYING" {
				mismatched = append(mismatched, "state")
			}
			if status.Context != "PLAYLIST" {
				mismatched = append(mismatched, "context")
			}
			if status.Playlist != name {
				mismatched = append(mismatched, "playlist")
			}
			if status.Index != uint64(index+1) {
				mismatched = append(mismatched, "index")
			}
			if status.Count != uint64(count) {
				mismatched = append(mismatched, "count")
			}
			if !sameCanonicalPath(status.Path, selected) {
				mismatched = append(mismatched, "path")
			}
			if requireNewSession && status.Session == baselineSession {
				mismatched = append(mismatched, "session")
			}
		}
		observation := fmt.Sprintf("%s|%s|%s|%s|%d|%d|%d|%s|%s",
			status.State, status.Context, status.Playlist, status.Path,
			status.Index, status.Count, status.Session,
			strings.Join(mismatched, ","), statusErr)
		if observation != lastObservation {
			lastObservation = observation
			a.appendPlaylistHandoffTrace(playlistHandoffTrace{
				Event: "playlist_status_observation", Playlist: name,
				PlaylistCount: count, SelectedIndex: index, Selected: selected,
				ElapsedMS: time.Since(requestStarted).Milliseconds(), Deadline: deadline,
				StatusState: status.State, StatusContext: status.Context,
				StatusPlaylist: status.Playlist, StatusPath: status.Path,
				StatusIndex: status.Index, StatusCount: status.Count,
				StatusSession: status.Session, Mismatched: mismatched,
				StatusError: statusErr, OperationID: operationID, Phase: "convergence",
			})
		}
		if len(mismatched) == 0 {
			a.appendPlaylistHandoffTrace(playlistHandoffTrace{
				Event: "playlist_status_converged", Playlist: name,
				PlaylistCount: count, SelectedIndex: index, Selected: selected,
				ElapsedMS: time.Since(requestStarted).Milliseconds(), Deadline: deadline,
				Result: "success", StatusState: status.State,
				StatusContext: status.Context, StatusPlaylist: status.Playlist,
				StatusPath: status.Path, StatusIndex: status.Index,
				StatusCount: status.Count, StatusSession: status.Session,
				OperationID: operationID, Phase: "convergence",
			})
			return true
		}
		select {
		case <-ctx.Done():
			a.appendPlaylistHandoffTrace(playlistHandoffTrace{
				Event: "playlist_status_timeout", Playlist: name,
				PlaylistCount: count, SelectedIndex: index, Selected: selected,
				ElapsedMS: time.Since(requestStarted).Milliseconds(), Deadline: deadline,
				Result: ctx.Err().Error(), StatusState: status.State,
				StatusContext: status.Context, StatusPlaylist: status.Playlist,
				StatusPath: status.Path, StatusIndex: status.Index,
				StatusCount: status.Count, StatusSession: status.Session,
				Mismatched: mismatched, StatusError: statusErr,
				OperationID: operationID, Phase: "convergence",
			})
			return false
		case <-ticker.C:
		}
	}
}

func (a *Adapter) beginPlaylistOperation() uint64 {
	a.playlistConvergenceMu.Lock()
	defer a.playlistConvergenceMu.Unlock()
	if a.playlistConvergenceCancel != nil {
		a.playlistConvergenceCancel()
		a.playlistConvergenceCancel = nil
	}
	a.playlistConvergenceID++
	return a.playlistConvergenceID
}

func (a *Adapter) startPlaylistConvergenceMonitor(operationID uint64,
	requestStarted time.Time, selected, name string, index, count int,
	requireNewSession bool, baselineSession uint32) {
	a.appendPlaylistHandoffTrace(playlistHandoffTrace{
		Event: "background_monitor_start", Playlist: name,
		PlaylistCount: count, SelectedIndex: index, Selected: selected,
		OperationID: operationID,
		ElapsedMS:   time.Since(requestStarted).Milliseconds(),
	})
	a.playlistConvergenceMu.Lock()
	if a.playlistConvergenceID != operationID {
		a.playlistConvergenceMu.Unlock()
		a.appendPlaylistHandoffTrace(playlistHandoffTrace{
			Event: "playlist_status_monitor_complete", Playlist: name,
			PlaylistCount: count, SelectedIndex: index, Selected: selected,
			OperationID: operationID, Result: "superseded_before_monitor",
			ElapsedMS: time.Since(requestStarted).Milliseconds(),
		})
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), a.config.StartTimeout)
	a.playlistConvergenceCancel = cancel
	a.playlistConvergenceMu.Unlock()

	go func() {
		converged := a.waitForPlayingPlaylistOperation(ctx, selected, name,
			index, count, operationID, requestStarted, requireNewSession,
			baselineSession)
		a.playlistConvergenceMu.Lock()
		current := a.playlistConvergenceID == operationID
		if current {
			a.playlistConvergenceCancel = nil
		}
		a.playlistConvergenceMu.Unlock()
		result := "superseded"
		if current && converged {
			result = "converged"
		} else if current {
			result = "timeout"
		}
		a.appendPlaylistHandoffTrace(playlistHandoffTrace{
			Event: "playlist_status_monitor_complete", Playlist: name,
			PlaylistCount: count, SelectedIndex: index, Selected: selected,
			OperationID: operationID, Result: result,
			ElapsedMS: time.Since(requestStarted).Milliseconds(),
		})
		cancel()
	}()
}

func (a *Adapter) tracePlaylistStatusDuringDispatch(ctx context.Context,
	operationID uint64, requestStarted time.Time, selected, name string,
	index, count int) {
	lastObservation := ""
	ticker := time.NewTicker(50 * time.Millisecond)
	defer ticker.Stop()
	for {
		status := playlistStatus{}
		statusErr := ""
		file, err := os.Open(a.config.StatusPath)
		if err == nil {
			var parseErr error
			status, parseErr = ParseStatus(file)
			_ = file.Close()
			if parseErr != nil {
				statusErr = parseErr.Error()
			}
		} else {
			statusErr = err.Error()
		}
		observation := fmt.Sprintf("%s|%s|%s|%s|%d|%d|%d|%s",
			status.State, status.Context, status.Playlist, status.Path,
			status.Index, status.Count, status.Session, statusErr)
		if observation != lastObservation {
			lastObservation = observation
			a.appendPlaylistHandoffTrace(playlistHandoffTrace{
				Event: "playlist_status_observation", Playlist: name,
				PlaylistCount: count, SelectedIndex: index, Selected: selected,
				ElapsedMS:   time.Since(requestStarted).Milliseconds(),
				StatusState: status.State, StatusContext: status.Context,
				StatusPlaylist: status.Playlist, StatusPath: status.Path,
				StatusIndex: status.Index, StatusCount: status.Count,
				StatusSession: status.Session, StatusError: statusErr,
				OperationID: operationID, Phase: "dispatch",
			})
		}
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
	}
}

func (a *Adapter) readControllerPlaylistStatus() (playlistStatus, error) {
	file, err := os.Open(a.config.StatusPath)
	if err != nil {
		return playlistStatus{}, err
	}
	defer file.Close()
	return ParseStatus(file)
}

func acceptsWarmPlaylistState(state string) bool {
	return state == "PLAYING" || state == "STOPPED"
}

type supervisorCommandResult struct {
	output []byte
	err    error
}

func (a *Adapter) dispatchSupervisorUntilActive(ctx context.Context,
	directory string, args ...string) error {
	commandDone := make(chan supervisorCommandResult, 1)
	runner := a.run
	if a.startSupervisor != nil {
		runner = a.startSupervisor
	}
	go func() {
		output, err := runner(ctx, a.config.SupervisorPath, args...)
		commandDone <- supervisorCommandResult{output: output, err: err}
	}()
	ticker := time.NewTicker(50 * time.Millisecond)
	defer ticker.Stop()
	sawStarting := false
	for {
		status, statusErr := a.readSupervisorStatus()
		if statusErr == nil {
			if status.Mode == "STARTING" {
				sawStarting = true
			}
			if status.Mode == "MEGAVGM" && status.Main == "MODIFIED" &&
				status.Controller == "RUNNING" &&
				sameCanonicalPath(status.Playlist, directory) {
				return nil
			}
			if status.Mode == "FAILURE" || (sawStarting && status.Mode == "STOCK") {
				detail := strings.TrimSpace(status.Detail)
				if detail == "" {
					detail = "supervisor did not enter MegaVGM mode"
				}
				return errors.New(detail)
			}
		}
		select {
		case result := <-commandDone:
			commandDone = nil
			if result.err != nil {
				detail := strings.TrimSpace(string(result.output))
				if detail == "" {
					detail = result.err.Error()
				}
				return errors.New(detail)
			}
		case <-ctx.Done():
			return ctx.Err()
		case <-ticker.C:
		}
	}
}

func (a *Adapter) HandlePlayPlaylist(w http.ResponseWriter, r *http.Request) {
	requestStarted := time.Now()
	operationID := a.beginPlaylistOperation()
	w.Header().Set("X-MegaVGM-Play-Handler", "playlist")
	a.appendPlaylistHandoffTrace(playlistHandoffTrace{
		Event: "playlist_http_arrival", Method: r.Method,
		RequestPath: r.URL.Path, Query: r.URL.RawQuery,
		ElapsedMS: 0, OperationID: operationID,
	})
	a.appendPlaylistHandoffTrace(playlistHandoffTrace{
		Event: "playlist_lock_wait", ElapsedMS: time.Since(requestStarted).Milliseconds(),
		OperationID: operationID,
	})
	a.playlistPlayMu.Lock()
	lockHeld := true
	releasePlaylistLock := func() {
		if !lockHeld {
			return
		}
		a.playlistPlayMu.Unlock()
		lockHeld = false
		a.appendPlaylistHandoffTrace(playlistHandoffTrace{
			Event:       "playlist_lock_released",
			ElapsedMS:   time.Since(requestStarted).Milliseconds(),
			OperationID: operationID,
		})
	}
	defer releasePlaylistLock()
	a.appendPlaylistHandoffTrace(playlistHandoffTrace{
		Event:       "playlist_lock_acquired",
		ElapsedMS:   time.Since(requestStarted).Milliseconds(),
		OperationID: operationID,
	})
	name, valid := playlistName(r)
	var input playlistPlayRequest
	if !valid || decodeJSONBody(r, &input) != nil {
		writeAPIError(w, 400, "invalid_request")
		return
	}
	document, err := a.favorites.document()
	if err != nil {
		writeAPIError(w, 500, "playlists_storage_unavailable")
		return
	}
	stored, exists := document.Playlists[name]
	if !exists {
		writeAPIError(w, 404, "playlist_not_found")
		return
	}
	if len(stored) == 0 {
		writeAPIError(w, 409, "playlist_empty")
		return
	}
	paths := make([]string, len(stored))
	for index, path := range stored {
		canonical, _, canonicalErr := canonicalVGM(path, a.config.ApprovedRoot)
		if canonicalErr != nil {
			writeAPIError(w, 409, "playlist_contains_unavailable_tracks")
			return
		}
		paths[index] = canonical
	}
	start := 0
	if input.Index != nil {
		start = *input.Index
	}
	if input.Path != "" {
		identity, identityErr := favoritePathIdentity(input.Path, a.config.ApprovedRoot)
		if identityErr != nil {
			writeAPIError(w, 400, "invalid_vgm_path")
			return
		}
		found := -1
		for index, path := range paths {
			if path == identity {
				found = index
				break
			}
		}
		if found < 0 || (input.Index != nil && start != found) {
			writeAPIError(w, 400, "track_not_in_playlist")
			return
		}
		start = found
	}
	if start < 0 || start >= len(paths) {
		writeAPIError(w, 400, "invalid_start_index")
		return
	}
	selected := paths[start]
	snapshotPath, err := writePlaylistSnapshot(a.config.SnapshotDirectory, name, paths, start)
	if err != nil {
		writeAPIError(w, 500, "playlist_snapshot_failed")
		return
	}
	cleanupSnapshot := true
	defer func() {
		if cleanupSnapshot {
			_ = os.Remove(snapshotPath)
		}
	}()

	supervisor, err := a.readSupervisorStatus()
	if err != nil {
		writeAPIError(w, 503, "supervisor_status_unavailable")
		return
	}
	a.appendPlaylistHandoffTrace(playlistHandoffTrace{
		Event: "remote_http", Method: r.Method, RequestPath: r.URL.Path,
		Query: r.URL.RawQuery, Handler: "HandlePlayPlaylist", Context: "PLAYLIST",
		SupervisorMode: supervisor.Mode, Playlist: name,
		PlaylistCount: len(paths), SelectedIndex: start, Selected: selected,
		Directory: filepath.Dir(selected), RequestBody: mustJSON(input),
		OperationID: operationID,
	})
	if supervisor.Mode == "STOCK" {
		if !isExecutable(a.config.SupervisorPath) {
			writeAPIError(w, 503, "supervisor_unavailable")
			return
		}
		ctx, cancel := context.WithTimeout(r.Context(), a.config.StartTimeout)
		defer cancel()
		a.appendPlaylistHandoffTrace(playlistHandoffTrace{
			Event: "cold_playlist_play", SupervisorMode: supervisor.Mode,
			Playlist: name, PlaylistCount: len(paths), SelectedIndex: start,
			Selected: selected, SnapshotPath: snapshotPath,
			Executable: a.config.SupervisorPath,
			Argv: []string{a.config.SupervisorPath, "enter",
				"--playlist-snapshot", snapshotPath, filepath.Dir(selected)},
			OperationID: operationID,
		})
		dispatchTraceCtx, stopDispatchTrace := context.WithCancel(context.Background())
		go a.tracePlaylistStatusDuringDispatch(dispatchTraceCtx, operationID,
			requestStarted, selected, name, start, len(paths))
		a.appendPlaylistHandoffTrace(playlistHandoffTrace{
			Event: "supervisor_exec_start", Playlist: name,
			PlaylistCount: len(paths), SelectedIndex: start, Selected: selected,
			ElapsedMS:   time.Since(requestStarted).Milliseconds(),
			OperationID: operationID,
		})
		runErr := a.dispatchSupervisorUntilActive(ctx, filepath.Dir(selected),
			"enter", "--playlist-snapshot", snapshotPath, filepath.Dir(selected))
		stopDispatchTrace()
		a.appendPlaylistHandoffTrace(playlistHandoffTrace{
			Event: "supervisor_acceptance_seen", SupervisorMode: supervisor.Mode,
			Playlist: name, PlaylistCount: len(paths), SelectedIndex: start,
			Selected: selected, ElapsedMS: time.Since(requestStarted).Milliseconds(),
			Result: func() string {
				if runErr != nil {
					return runErr.Error()
				}
				return "success"
			}(), OperationID: operationID,
		})
		if runErr != nil {
			if resourceCapacityOutput([]byte(runErr.Error())) {
				writeAPIError(w, http.StatusConflict, "resource_capacity_exceeded")
				return
			}
			a.appendPlaylistHandoffTrace(playlistHandoffTrace{
				Event: "playlist_http_response", Playlist: name,
				PlaylistCount: len(paths), SelectedIndex: start, Selected: selected,
				ElapsedMS: time.Since(requestStarted).Milliseconds(), HTTPStatus: 502,
				Result: "supervisor_start_failed",
			})
			writeAPIError(w, 502, "supervisor_start_failed")
			return
		}
		// The controller consumed and now owns this exact immutable snapshot in
		// memory. The deferred cleanup remains as a harmless stale-file guard.
		// Do not send a second PLAYLIST command across its initial PLAYING
		// command-discard boundary.
		writeJSON(w, http.StatusAccepted, playlistPlayResponse{
			true, "MEGAVGM", name, selected, start, len(paths)})
		a.appendPlaylistHandoffTrace(playlistHandoffTrace{
			Event: "http_202_sent", Playlist: name,
			PlaylistCount: len(paths), SelectedIndex: start, Selected: selected,
			ElapsedMS:  time.Since(requestStarted).Milliseconds(),
			HTTPStatus: http.StatusAccepted, Result: "accepted",
			OperationID: operationID,
		})
		releasePlaylistLock()
		a.startPlaylistConvergenceMonitor(operationID, requestStarted,
			selected, name, start, len(paths), false, 0)
		return
	} else if supervisor.Mode != "MEGAVGM" || supervisor.Main != "MODIFIED" || supervisor.Controller != "RUNNING" {
		writeAPIError(w, 409, "supervisor_busy")
		return
	}
	requireNewSession := false
	var baselineSession uint32
	if supervisor.Mode == "MEGAVGM" {
		controllerStatus, statusErr := a.readControllerPlaylistStatus()
		if statusErr != nil || !acceptsWarmPlaylistState(controllerStatus.State) {
			statusError := ""
			if statusErr != nil {
				statusError = statusErr.Error()
			}
			a.appendPlaylistHandoffTrace(playlistHandoffTrace{
				Event: "playlist_http_response", Playlist: name,
				PlaylistCount: len(paths), SelectedIndex: start, Selected: selected,
				ElapsedMS:  time.Since(requestStarted).Milliseconds(),
				HTTPStatus: http.StatusConflict, Result: "rejected",
				StatusState:    controllerStatus.State,
				StatusContext:  controllerStatus.Context,
				StatusPlaylist: controllerStatus.Playlist,
				StatusPath:     controllerStatus.Path,
				StatusIndex:    controllerStatus.Index,
				StatusCount:    controllerStatus.Count,
				StatusSession:  controllerStatus.Session,
				StatusError:    statusError, ErrorCode: "controller_not_playing",
				OperationID: operationID, Phase: "warm_admission",
			})
			writeAPIError(w, http.StatusConflict, "controller_not_playing")
			return
		}
		requireNewSession = controllerStatus.State == "PLAYING" &&
			controllerStatus.Context == "PLAYLIST" &&
			controllerStatus.Playlist == name &&
			controllerStatus.Index == uint64(start+1) &&
			controllerStatus.Count == uint64(len(paths)) &&
			sameCanonicalPath(controllerStatus.Path, selected)
		baselineSession = controllerStatus.Session
	}
	if running, fifoErr := isFIFO(a.config.CommandPath); fifoErr != nil || !running || !isExecutable(a.config.CtlPath) {
		writeAPIError(w, 503, "controller_unavailable")
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), a.config.CtlTimeout)
	defer cancel()
	dispatchTraceCtx, stopDispatchTrace := context.WithCancel(context.Background())
	go a.tracePlaylistStatusDuringDispatch(dispatchTraceCtx, operationID,
		requestStarted, selected, name, start, len(paths))
	if _, err := a.run(ctx, a.config.CtlPath, "playlist", snapshotPath); err != nil {
		stopDispatchTrace()
		writeAPIError(w, 502, "control_failed")
		return
	}
	stopDispatchTrace()
	cleanupSnapshot = false // controller consumes the immutable file.
	a.appendPlaylistHandoffTrace(playlistHandoffTrace{
		Event: "warm_controller_return", Playlist: name,
		PlaylistCount: len(paths), SelectedIndex: start, Selected: selected,
		ElapsedMS: time.Since(requestStarted).Milliseconds(), Result: "success",
		OperationID: operationID,
	})
	writeJSON(w, http.StatusAccepted, playlistPlayResponse{true, "MEGAVGM", name, selected, start, len(paths)})
	a.appendPlaylistHandoffTrace(playlistHandoffTrace{
		Event: "http_202_sent", Playlist: name,
		PlaylistCount: len(paths), SelectedIndex: start, Selected: selected,
		ElapsedMS:  time.Since(requestStarted).Milliseconds(),
		HTTPStatus: http.StatusAccepted, Result: "accepted",
		OperationID: operationID,
	})
	releasePlaylistLock()
	a.startPlaylistConvergenceMonitor(operationID, requestStarted,
		selected, name, start, len(paths), requireNewSession, baselineSession)
}
