package megavgm

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/gorilla/mux"
)

func playlistHTTPRequest(t *testing.T, method, name, body string, handler http.HandlerFunc) *httptest.ResponseRecorder {
	t.Helper()
	request := httptest.NewRequest(method, "/", strings.NewReader(body))
	request = mux.SetURLVars(request, map[string]string{"name": name})
	recorder := httptest.NewRecorder()
	handler(recorder, request)
	return recorder
}

func readHandoffTraces(t *testing.T, adapter *Adapter) []playlistHandoffTrace {
	t.Helper()
	data, err := os.ReadFile(adapter.config.HandoffTracePath)
	if err != nil {
		t.Fatal(err)
	}
	var traces []playlistHandoffTrace
	for _, line := range bytes.Split(bytes.TrimSpace(data), []byte{'\n'}) {
		var trace playlistHandoffTrace
		if err := json.Unmarshal(line, &trace); err != nil {
			t.Fatal(err)
		}
		traces = append(traces, trace)
	}
	return traces
}

func TestPlaylistMigrationAndCRUD(t *testing.T) {
	adapter := newTestAdapter(t, t.TempDir(), nil)
	first := createFavoriteVGM(t, adapter, "Legacy/01 Favorite.vgm")
	document := emptyFavoritesDocument()
	document.Playlists["Favorites"] = []string{first}
	encoded, err := encodeFavoritesDocument(document)
	if err != nil {
		t.Fatal(err)
	}
	if err := atomicReplaceFile(adapter.config.FavoritesPath, encoded); err != nil {
		t.Fatal(err)
	}

	legacy := getFavorites(t, adapter)
	if len(legacy.Entries) != 1 || legacy.Entries[0].Path != first {
		t.Fatalf("legacy Favorites lost: %#v", legacy)
	}
	create := request(t, http.MethodPost, strings.NewReader(`{"name":"Arcade Mix"}`), adapter.HandleCreatePlaylist)
	if create.Code != http.StatusCreated {
		t.Fatalf("create=%d %s", create.Code, create.Body.String())
	}
	assertAPIError(t, request(t, http.MethodPost, strings.NewReader(`{"name":"Arcade Mix"}`), adapter.HandleCreatePlaylist), 409, "playlist_exists")
	assertAPIError(t, playlistHTTPRequest(t, http.MethodDelete, "Favorites", "", adapter.HandleDeletePlaylist), 409, "reserved_playlist")
	assertAPIError(t, playlistHTTPRequest(t, http.MethodPatch, "Favorites", `{"name":"Other"}`, adapter.HandleRenamePlaylist), 409, "reserved_playlist")
	rename := playlistHTTPRequest(t, http.MethodPatch, "Arcade Mix", `{"name":"Sega Mix"}`, adapter.HandleRenamePlaylist)
	if rename.Code != 200 {
		t.Fatalf("rename=%d %s", rename.Code, rename.Body.String())
	}
	deleted := playlistHTTPRequest(t, http.MethodDelete, "Sega Mix", "", adapter.HandleDeletePlaylist)
	if deleted.Code != 200 {
		t.Fatalf("delete=%d %s", deleted.Code, deleted.Body.String())
	}
	if got := getFavorites(t, adapter); len(got.Entries) != 1 || got.Entries[0].Path != first {
		t.Fatal("CRUD changed Favorites")
	}
}

func TestPlaylistTrackOrderDuplicateAndUnavailable(t *testing.T) {
	adapter := newTestAdapter(t, t.TempDir(), nil)
	if recorder := request(t, http.MethodPost, strings.NewReader(`{"name":"Twenty Five"}`), adapter.HandleCreatePlaylist); recorder.Code != 201 {
		t.Fatal(recorder.Body.String())
	}
	paths := make([]string, 25)
	for index := range paths {
		paths[index] = createFavoriteVGM(t, adapter, fmt.Sprintf("Disc%02d/%02d Track.vgm", index%3, index))
		body := fmt.Sprintf(`{"path":%q}`, paths[index])
		for repeat := 0; repeat < 2; repeat++ {
			recorder := playlistHTTPRequest(t, http.MethodPost, "Twenty Five", body, adapter.HandleAddPlaylistTrack)
			if recorder.Code != 200 {
				t.Fatalf("add=%d %s", recorder.Code, recorder.Body.String())
			}
		}
	}
	document, err := adapter.favorites.document()
	if err != nil {
		t.Fatal(err)
	}
	got := document.Playlists["Twenty Five"]
	if len(got) != len(paths) {
		t.Fatalf("count=%d", len(got))
	}
	for index := range paths {
		if got[index] != paths[index] {
			t.Fatalf("order[%d]=%q", index, got[index])
		}
	}
	if err := os.Remove(paths[7]); err != nil {
		t.Fatal(err)
	}
	detail := playlistHTTPRequest(t, http.MethodGet, "Twenty Five", "", adapter.HandlePlaylist)
	var response PlaylistResponse
	decodeResponse(t, detail, &response)
	if response.Entries[7].Available {
		t.Fatal("missing entry was not retained as unavailable")
	}
	remove := playlistHTTPRequest(t, http.MethodDelete, "Twenty Five", fmt.Sprintf(`{"path":%q}`, paths[7]), adapter.HandleRemovePlaylistTrack)
	if remove.Code != 200 {
		t.Fatalf("remove unavailable=%d %s", remove.Code, remove.Body.String())
	}
}

func TestPlaylistPlaySnapshotStartMiddleCrossDirectoryAndEditIsolation(t *testing.T) {
	dir := t.TempDir()
	var invocation []string
	adapter := newTestAdapter(t, dir, func(_ context.Context, command string, args ...string) ([]byte, error) {
		invocation = append([]string{command}, args...)
		return nil, nil
	})
	if recorder := request(t, http.MethodPost, strings.NewReader(`{"name":"Cross Directory"}`), adapter.HandleCreatePlaylist); recorder.Code != 201 {
		t.Fatal(recorder.Body.String())
	}
	paths := []string{
		createFavoriteVGM(t, adapter, "A/01 One.vgm"),
		createFavoriteVGM(t, adapter, "B/02 Two.vgm"),
		createFavoriteVGM(t, adapter, "C/03 Three.vgm"),
	}
	for _, path := range paths {
		body := fmt.Sprintf(`{"path":%q}`, path)
		if recorder := playlistHTTPRequest(t, http.MethodPost, "Cross Directory", body, adapter.HandleAddPlaylistTrack); recorder.Code != 200 {
			t.Fatal(recorder.Body.String())
		}
	}
	writeSupervisor(t, adapter, "MEGAVGM", "MODIFIED", "RUNNING", adapter.config.DefaultPlaylistPath)
	makeFIFO(t, adapter.config.CommandPath)
	writeExecutable(t, adapter.config.CtlPath)
	writeFile(t, adapter.config.StatusPath, strings.Replace(validStatus,
		"path=/media/fat/Music/04 Beyond the Galaxy.vgm", "path="+paths[0], 1), 0644)
	play := playlistHTTPRequest(t, http.MethodPost, "Cross Directory", `{"index":1}`, adapter.HandlePlayPlaylist)
	if play.Code != http.StatusAccepted {
		t.Fatalf("play=%d %s", play.Code, play.Body.String())
	}
	if len(invocation) != 3 || invocation[0] != adapter.config.CtlPath || invocation[1] != "playlist" {
		t.Fatalf("invocation=%#v", invocation)
	}
	snapshotPath := invocation[2]
	snapshot, err := os.ReadFile(snapshotPath)
	if err != nil {
		t.Fatal(err)
	}
	want := "MEGAVGM_PLAYLIST_V1\nNAME Cross Directory\nSTART 1\nCOUNT 3\n"
	for _, path := range paths {
		want += "PATH " + path + "\n"
	}
	if string(snapshot) != want {
		t.Fatalf("snapshot:\n%s\nwant:\n%s", snapshot, want)
	}
	if recorder := playlistHTTPRequest(t, http.MethodDelete, "Cross Directory", fmt.Sprintf(`{"path":%q}`, paths[2]), adapter.HandleRemovePlaylistTrack); recorder.Code != 200 {
		t.Fatal(recorder.Body.String())
	}
	after, err := os.ReadFile(snapshotPath)
	if err != nil || string(after) != want {
		t.Fatal("persistent edit mutated running snapshot")
	}
	_ = os.Remove(snapshotPath)
}

func TestPlaylistPlayRejectsUnavailableDeterministically(t *testing.T) {
	adapter := newTestAdapter(t, t.TempDir(), nil)
	if recorder := request(t, http.MethodPost, strings.NewReader(`{"name":"Broken"}`), adapter.HandleCreatePlaylist); recorder.Code != 201 {
		t.Fatal(recorder.Body.String())
	}
	path := createFavoriteVGM(t, adapter, "Broken/01 Gone.vgm")
	if recorder := playlistHTTPRequest(t, http.MethodPost, "Broken", fmt.Sprintf(`{"path":%q}`, path), adapter.HandleAddPlaylistTrack); recorder.Code != 200 {
		t.Fatal(recorder.Body.String())
	}
	if err := os.Remove(path); err != nil {
		t.Fatal(err)
	}
	writeSupervisor(t, adapter, "MEGAVGM", "MODIFIED", "RUNNING", adapter.config.DefaultPlaylistPath)
	assertAPIError(t, playlistHTTPRequest(t, http.MethodPost, "Broken", `{}`, adapter.HandlePlayPlaylist), 409, "playlist_contains_unavailable_tracks")
}

func TestFavoritesPlayAllFromStockAdoptsInitialSessionWithoutSecondPlayRequest(t *testing.T) {
	dir := t.TempDir()
	var invocations [][]string
	var coldSnapshot string
	adapter := newTestAdapter(t, dir, nil)
	first := createFavoriteVGM(t, adapter, "Favorites/01 First.vgm")
	second := createFavoriteVGM(t, adapter, "Elsewhere/02 Second.vgm")
	for _, path := range []string{first, second} {
		if recorder := favoriteRequest(t, http.MethodPost, path, adapter.HandleAddFavorite); recorder.Code != 200 {
			t.Fatal(recorder.Body.String())
		}
	}
	writeSupervisor(t, adapter, "STOCK", "STOCK", "STOPPED", "")
	writeExecutable(t, adapter.config.SupervisorPath)
	adapter.run = func(_ context.Context, command string, args ...string) ([]byte, error) {
		invocations = append(invocations, append([]string{command}, args...))
		if command == adapter.config.SupervisorPath {
			data, err := os.ReadFile(args[2])
			if err != nil {
				t.Fatal(err)
			}
			coldSnapshot = string(data)
			writeSupervisor(t, adapter, "MEGAVGM", "MODIFIED", "RUNNING", filepath.Dir(first))
			makeFIFO(t, adapter.config.CommandPath)
			writeExecutable(t, adapter.config.CtlPath)
			status := strings.Replace(validStatus,
				"path=/media/fat/Music/04 Beyond the Galaxy.vgm", "path="+first, 1)
			status = strings.Replace(status, "index=4", "index=1", 1)
			status = strings.Replace(status, "count=10", "count=2", 1)
			status += "context=PLAYLIST\nplaylist=Favorites\n"
			writeFile(t, adapter.config.StatusPath, status, 0644)
		}
		return nil, nil
	}
	recorder := playlistHTTPRequest(t, http.MethodPost, "Favorites", `{}`, adapter.HandlePlayPlaylist)
	if recorder.Code != http.StatusAccepted {
		t.Fatalf("play=%d %s", recorder.Code, recorder.Body.String())
	}
	if len(invocations) != 1 {
		t.Fatalf("invocations=%#v", invocations)
	}
	if got := invocations[0]; len(got) != 5 ||
		got[0] != adapter.config.SupervisorPath || got[1] != "enter" ||
		got[2] != "--playlist-snapshot" || got[4] != filepath.Dir(first) {
		t.Fatalf("supervisor invocation=%#v", got)
	} else if !strings.Contains(coldSnapshot,
		"NAME Favorites\nSTART 0\nCOUNT 2\n") {
		t.Fatalf("cold snapshot=%q", coldSnapshot)
	}
}

func TestNamedPlaylistColdStartKeepsFiveTrackSnapshotFromSecond(t *testing.T) {
	var invocation []string
	var coldSnapshot string
	adapter := newTestAdapter(t, t.TempDir(), nil)
	if recorder := request(t, http.MethodPost,
		strings.NewReader(`{"name":"Cold Five"}`),
		adapter.HandleCreatePlaylist); recorder.Code != 201 {
		t.Fatal(recorder.Body.String())
	}
	paths := make([]string, 5)
	for index := range paths {
		paths[index] = createFavoriteVGM(t, adapter,
			fmt.Sprintf("Album%02d/%02d Track.vgm", index, index+1))
		body := fmt.Sprintf(`{"path":%q}`, paths[index])
		if recorder := playlistHTTPRequest(t, http.MethodPost, "Cold Five", body,
			adapter.HandleAddPlaylistTrack); recorder.Code != 200 {
			t.Fatal(recorder.Body.String())
		}
	}
	writeSupervisor(t, adapter, "STOCK", "STOCK", "STOPPED", "")
	writeExecutable(t, adapter.config.SupervisorPath)
	adapter.run = func(_ context.Context, command string,
		args ...string) ([]byte, error) {
		invocation = append([]string{command}, args...)
		data, err := os.ReadFile(args[2])
		if err != nil {
			t.Fatal(err)
		}
		coldSnapshot = string(data)
		writeSupervisor(t, adapter, "MEGAVGM", "MODIFIED", "RUNNING",
			filepath.Dir(paths[1]))
		status := strings.Replace(validStatus,
			"path=/media/fat/Music/04 Beyond the Galaxy.vgm", "path="+paths[1], 1)
		status = strings.Replace(status, "index=4", "index=2", 1)
		status = strings.Replace(status, "count=10", "count=5", 1)
		status += "context=PLAYLIST\nplaylist=Cold Five\n"
		writeFile(t, adapter.config.StatusPath, status, 0644)
		return nil, nil
	}
	recorder := playlistHTTPRequest(t, http.MethodPost, "Cold Five",
		`{"index":1}`, adapter.HandlePlayPlaylist)
	if recorder.Code != http.StatusAccepted {
		t.Fatalf("play=%d %s", recorder.Code, recorder.Body.String())
	}
	if got := recorder.Header().Get("X-MegaVGM-Play-Handler"); got != "playlist" {
		t.Fatalf("handler header=%q", got)
	}
	if len(invocation) != 5 || invocation[2] != "--playlist-snapshot" ||
		invocation[4] != filepath.Dir(paths[1]) {
		t.Fatalf("invocation=%#v", invocation)
	}
	want := "MEGAVGM_PLAYLIST_V1\nNAME Cold Five\nSTART 1\nCOUNT 5\n"
	for _, path := range paths {
		want += "PATH " + path + "\n"
	}
	if coldSnapshot != want {
		t.Fatalf("snapshot:\n%s\nwant:\n%s", coldSnapshot, want)
	}
	traces := readHandoffTraces(t, adapter)
	var httpTrace, trace playlistHandoffTrace
	for _, candidate := range traces {
		switch candidate.Event {
		case "remote_http":
			httpTrace = candidate
		case "cold_playlist_play":
			trace = candidate
		}
	}
	if httpTrace.Event != "remote_http" || httpTrace.Method != http.MethodPost ||
		httpTrace.Handler != "HandlePlayPlaylist" || httpTrace.Context != "PLAYLIST" ||
		httpTrace.RequestBody != `{"index":1}` || httpTrace.Playlist != "Cold Five" ||
		httpTrace.PlaylistCount != 5 || httpTrace.SelectedIndex != 1 ||
		httpTrace.Selected != paths[1] || httpTrace.SupervisorMode != "STOCK" {
		t.Fatalf("HTTP trace=%#v", httpTrace)
	}
	if trace.Event != "cold_playlist_play" || trace.SupervisorMode != "STOCK" ||
		trace.Playlist != "Cold Five" || trace.PlaylistCount != 5 ||
		trace.SelectedIndex != 1 || trace.Selected != paths[1] ||
		len(trace.Argv) != 5 || trace.Argv[2] != "--playlist-snapshot" ||
		trace.Argv[3] != trace.SnapshotPath || trace.Argv[4] != filepath.Dir(paths[1]) {
		t.Fatalf("handoff trace=%#v", trace)
	}
}

func TestPlaylistPlayColdAndWarmProduceIdenticalQueueSemantics(t *testing.T) {
	adapter := newTestAdapter(t, t.TempDir(), nil)
	paths := make([]string, 10)
	for index := range paths {
		paths[index] = createFavoriteVGM(t, adapter,
			fmt.Sprintf("After Burner/%02d Track.vgm", index+1))
		if recorder := favoriteRequest(t, http.MethodPost, paths[index],
			adapter.HandleAddFavorite); recorder.Code != http.StatusOK {
			t.Fatal(recorder.Body.String())
		}
	}
	selected := paths[0]
	wantSnapshot := "MEGAVGM_PLAYLIST_V1\nNAME Favorites\nSTART 0\nCOUNT 10\n"
	for _, path := range paths {
		wantSnapshot += "PATH " + path + "\n"
	}
	writePlaying := func() {
		status := strings.Replace(validStatus,
			"path=/media/fat/Music/04 Beyond the Galaxy.vgm", "path="+selected, 1)
		status = strings.Replace(status, "index=4", "index=1", 1)
		status += "context=PLAYLIST\nplaylist=Favorites\n"
		writeFile(t, adapter.config.StatusPath, status, 0644)
	}

	var coldSnapshot string
	writeSupervisor(t, adapter, "STOCK", "STOCK", "STOPPED", "")
	writeExecutable(t, adapter.config.SupervisorPath)
	adapter.run = func(_ context.Context, command string, args ...string) ([]byte, error) {
		if command != adapter.config.SupervisorPath || len(args) != 4 ||
			args[1] != "--playlist-snapshot" {
			t.Fatalf("cold invocation=%q %#v", command, args)
		}
		data, err := os.ReadFile(args[2])
		if err != nil {
			t.Fatal(err)
		}
		coldSnapshot = string(data)
		writeSupervisor(t, adapter, "MEGAVGM", "MODIFIED", "RUNNING",
			filepath.Dir(selected))
		writePlaying()
		return nil, nil
	}
	if recorder := playlistHTTPRequest(t, http.MethodPost, "Favorites",
		`{"index":0}`, adapter.HandlePlayPlaylist); recorder.Code != http.StatusAccepted {
		t.Fatalf("cold play=%d %s", recorder.Code, recorder.Body.String())
	}

	makeFIFO(t, adapter.config.CommandPath)
	writeExecutable(t, adapter.config.CtlPath)
	writePlaying()
	var warmSnapshot string
	adapter.run = func(_ context.Context, command string, args ...string) ([]byte, error) {
		if command != adapter.config.CtlPath || len(args) != 2 || args[0] != "playlist" {
			t.Fatalf("warm invocation=%q %#v", command, args)
		}
		data, err := os.ReadFile(args[1])
		if err != nil {
			t.Fatal(err)
		}
		warmSnapshot = string(data)
		writePlaying()
		return nil, nil
	}
	if recorder := playlistHTTPRequest(t, http.MethodPost, "Favorites",
		`{"index":0}`, adapter.HandlePlayPlaylist); recorder.Code != http.StatusAccepted {
		t.Fatalf("warm play=%d %s", recorder.Code, recorder.Body.String())
	}

	if coldSnapshot != wantSnapshot || warmSnapshot != wantSnapshot ||
		coldSnapshot != warmSnapshot {
		t.Fatalf("cold/warm snapshots differ\ncold:\n%s\nwarm:\n%s\nwant:\n%s",
			coldSnapshot, warmSnapshot, wantSnapshot)
	}
	file, err := os.Open(adapter.config.StatusPath)
	if err != nil {
		t.Fatal(err)
	}
	status, err := ParseStatus(file)
	_ = file.Close()
	if err != nil || status.Context != "PLAYLIST" || status.Playlist != "Favorites" ||
		status.Count != 10 || status.Index != 1 || !sameCanonicalPath(status.Path, selected) {
		t.Fatalf("final queue status=%#v err=%v", status, err)
	}
}

func TestPlaylistConvergenceTraceIdentifiesLastMismatchedField(t *testing.T) {
	adapter := newTestAdapter(t, t.TempDir(), nil)
	selected := createFavoriteVGM(t, adapter, "Album/01 Selected.vgm")
	status := strings.Replace(validStatus,
		"path=/media/fat/Music/04 Beyond the Galaxy.vgm", "path="+selected, 1)
	status = strings.Replace(status, "index=4", "index=1", 1)
	status = strings.Replace(status, "count=10", "count=9", 1)
	status += "context=PLAYLIST\nplaylist=Favorites\n"
	writeFile(t, adapter.config.StatusPath,
		strings.Replace(status, "state=PLAYING", "state=LOADING", 1), 0644)

	writeErrors := make(chan error, 1)
	go func() {
		time.Sleep(80 * time.Millisecond)
		if err := atomicReplaceFile(adapter.config.StatusPath, []byte(status)); err != nil {
			writeErrors <- err
			return
		}
		time.Sleep(80 * time.Millisecond)
		writeErrors <- atomicReplaceFile(adapter.config.StatusPath,
			[]byte(strings.Replace(status, "count=9", "count=10", 1)))
	}()

	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	if !adapter.waitForPlayingPlaylist(ctx, selected, "Favorites", 0, 10) {
		t.Fatal("expected delayed status convergence")
	}
	if err := <-writeErrors; err != nil {
		t.Fatal(err)
	}

	traces := readHandoffTraces(t, adapter)
	sawPlayingWaitingForCount := false
	sawConverged := false
	for _, trace := range traces {
		if trace.Event == "playlist_status_observation" &&
			trace.StatusState == "PLAYING" &&
			strings.Join(trace.Mismatched, ",") == "count" {
			sawPlayingWaitingForCount = true
		}
		if trace.Event == "playlist_status_converged" &&
			trace.StatusState == "PLAYING" && trace.StatusContext == "PLAYLIST" &&
			trace.StatusPlaylist == "Favorites" && trace.StatusPath == selected &&
			trace.StatusIndex == 1 && trace.StatusCount == 10 &&
			len(trace.Mismatched) == 0 && trace.ElapsedMS >= 100 {
			sawConverged = true
		}
	}
	if !sawPlayingWaitingForCount || !sawConverged {
		t.Fatalf("missing field-level convergence evidence: %#v", traces)
	}
}

func TestPlaylistHTTPAcceptanceDoesNotWaitForStatusConvergence(t *testing.T) {
	adapter := newTestAdapter(t, t.TempDir(), nil)
	adapter.config.StartTimeout = time.Second
	paths := []string{
		createFavoriteVGM(t, adapter, "Album/01 First.vgm"),
		createFavoriteVGM(t, adapter, "Album/02 Second.vgm"),
	}
	for _, path := range paths {
		if recorder := favoriteRequest(t, http.MethodPost, path,
			adapter.HandleAddFavorite); recorder.Code != http.StatusOK {
			t.Fatal(recorder.Body.String())
		}
	}
	writeSupervisor(t, adapter, "STOCK", "STOCK", "STOPPED", "")
	writeExecutable(t, adapter.config.SupervisorPath)
	adapter.run = func(_ context.Context, command string, _ ...string) ([]byte, error) {
		if command == adapter.config.SupervisorPath {
			writeSupervisor(t, adapter, "MEGAVGM", "MODIFIED", "RUNNING",
				filepath.Dir(paths[0]))
		}
		return nil, nil
	}
	started := time.Now()
	first := playlistHTTPRequest(t, http.MethodPost, "Favorites", `{"index":0}`,
		adapter.HandlePlayPlaylist)
	if first.Code != http.StatusAccepted || time.Since(started) >= 200*time.Millisecond {
		t.Fatalf("first response blocked on status: code=%d elapsed=%s body=%s",
			first.Code, time.Since(started), first.Body.String())
	}

	makeFIFO(t, adapter.config.CommandPath)
	writeExecutable(t, adapter.config.CtlPath)
	writeFile(t, adapter.config.StatusPath, validStatus, 0644)
	started = time.Now()
	second := playlistHTTPRequest(t, http.MethodPost, "Favorites", `{"index":1}`,
		adapter.HandlePlayPlaylist)
	if second.Code != http.StatusAccepted || time.Since(started) >= 200*time.Millisecond {
		t.Fatalf("second response blocked behind first monitor: code=%d elapsed=%s body=%s",
			second.Code, time.Since(started), second.Body.String())
	}

	status := strings.Replace(validStatus,
		"path=/media/fat/Music/04 Beyond the Galaxy.vgm", "path="+paths[1], 1)
	status = strings.Replace(status, "index=4", "index=2", 1)
	status = strings.Replace(status, "count=10", "count=2", 1)
	status += "context=PLAYLIST\nplaylist=Favorites\n"
	if err := atomicReplaceFile(adapter.config.StatusPath, []byte(status)); err != nil {
		t.Fatal(err)
	}

	deadline := time.Now().Add(time.Second)
	for time.Now().Before(deadline) {
		traces := readHandoffTraces(t, adapter)
		superseded := false
		converged := false
		for _, trace := range traces {
			if trace.Event == "playlist_status_monitor_complete" &&
				trace.OperationID == 1 && trace.Result == "superseded" {
				superseded = true
			}
			if trace.Event == "playlist_status_monitor_complete" &&
				trace.OperationID == 2 && trace.Result == "converged" {
				converged = true
			}
		}
		if superseded && converged {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatal("new operation did not supersede old convergence monitor")
}

func TestColdSupervisorOutputHeldOpenDoesNotQueueSecondPlaylistRequest(t *testing.T) {
	adapter := newTestAdapter(t, t.TempDir(), nil)
	adapter.config.StartTimeout = time.Second
	paths := []string{
		createFavoriteVGM(t, adapter, "HeldOpen/01 First.vgm"),
		createFavoriteVGM(t, adapter, "HeldOpen/02 Second.vgm"),
	}
	for _, path := range paths {
		if recorder := favoriteRequest(t, http.MethodPost, path,
			adapter.HandleAddFavorite); recorder.Code != http.StatusOK {
			t.Fatal(recorder.Body.String())
		}
	}
	writeSupervisor(t, adapter, "STOCK", "STOCK", "STOPPED", "")
	writeExecutable(t, adapter.config.SupervisorPath)
	makeFIFO(t, adapter.config.CommandPath)
	writeExecutable(t, adapter.config.CtlPath)
	runnerErrors := make(chan error, 2)
	adapter.run = func(ctx context.Context, command string, _ ...string) ([]byte, error) {
		if command != adapter.config.SupervisorPath {
			return nil, nil
		}
		if err := atomicReplaceFile(adapter.config.SupervisorStatusPath,
			[]byte(supervisorStatus("MEGAVGM", "MODIFIED", "RUNNING",
				filepath.Dir(paths[0])))); err != nil {
			runnerErrors <- err
			return nil, err
		}
		partial := strings.Replace(validStatus,
			"path=/media/fat/Music/04 Beyond the Galaxy.vgm", "path="+paths[0], 1)
		partial = strings.Replace(partial, "index=4", "index=1", 1)
		partial = strings.Replace(partial, "count=10", "count=9", 1)
		partial += "context=PLAYLIST\nplaylist=Favorites\n"
		if err := atomicReplaceFile(adapter.config.StatusPath, []byte(partial)); err != nil {
			runnerErrors <- err
			return nil, err
		}
		// Model the real Supervisor CLI: success exists in its internal pipe,
		// but CombinedOutput cannot return while an inherited writer holds EOF
		// open. The context cancellation after HTTP acceptance ends this fixture;
		// without that cancellation it deliberately remains open for 30 seconds.
		select {
		case <-ctx.Done():
			return []byte("MEGAVGM MODE ACTIVE\n"), ctx.Err()
		case <-time.After(30 * time.Second):
			return []byte("MEGAVGM MODE ACTIVE\n"), nil
		}
	}

	type responseTiming struct {
		recorder *httptest.ResponseRecorder
		elapsed  time.Duration
	}
	firstStarted := time.Now()
	firstDone := make(chan responseTiming, 1)
	go func() {
		recorder := playlistHTTPRequest(t, http.MethodPost, "Favorites",
			`{"index":0}`, adapter.HandlePlayPlaylist)
		firstDone <- responseTiming{recorder, time.Since(firstStarted)}
	}()

	time.Sleep(100 * time.Millisecond)
	secondStarted := time.Now()
	second := playlistHTTPRequest(t, http.MethodPost, "Favorites",
		`{"index":1}`, adapter.HandlePlayPlaylist)
	secondElapsed := time.Since(secondStarted)
	first := <-firstDone
	if first.recorder.Code != http.StatusAccepted || first.elapsed >= 200*time.Millisecond {
		t.Fatalf("op1 waited for stdout EOF: code=%d elapsed=%s body=%s",
			first.recorder.Code, first.elapsed, first.recorder.Body.String())
	}
	if second.Code != http.StatusAccepted || secondElapsed >= 200*time.Millisecond {
		t.Fatalf("op2 queued behind op1: code=%d elapsed=%s body=%s",
			second.Code, secondElapsed, second.Body.String())
	}

	exact := strings.Replace(validStatus,
		"path=/media/fat/Music/04 Beyond the Galaxy.vgm", "path="+paths[1], 1)
	exact = strings.Replace(exact, "index=4", "index=2", 1)
	exact = strings.Replace(exact, "count=10", "count=2", 1)
	exact += "context=PLAYLIST\nplaylist=Favorites\n"
	if err := atomicReplaceFile(adapter.config.StatusPath, []byte(exact)); err != nil {
		t.Fatal(err)
	}

	deadline := time.Now().Add(time.Second)
	for time.Now().Before(deadline) {
		traces := readHandoffTraces(t, adapter)
		op1Superseded := false
		op2Converged := false
		op2HandlerStarted := false
		for _, trace := range traces {
			if trace.OperationID == 1 && trace.Event == "playlist_status_monitor_complete" &&
				trace.Result == "superseded" {
				op1Superseded = true
			}
			if trace.OperationID == 2 && trace.Event == "playlist_status_monitor_complete" &&
				trace.Result == "converged" {
				op2Converged = true
			}
			if trace.OperationID == 2 && trace.Event == "remote_http" {
				op2HandlerStarted = true
			}
		}
		if op1Superseded && op2Converged && op2HandlerStarted {
			positions := make(map[string]int)
			for position, trace := range traces {
				if trace.OperationID == 1 {
					positions[trace.Event] = position
				}
			}
			order := []string{
				"playlist_http_arrival", "playlist_lock_wait",
				"playlist_lock_acquired", "supervisor_exec_start",
				"supervisor_acceptance_seen", "http_202_sent",
				"playlist_lock_released", "background_monitor_start",
			}
			previous := -1
			for _, event := range order {
				position, exists := positions[event]
				if !exists || position <= previous {
					t.Fatalf("op1 event order invalid at %s: %#v", event, positions)
				}
				previous = position
			}
			select {
			case err := <-runnerErrors:
				t.Fatal(err)
			default:
			}
			t.Logf("op1 HTTP 202=%s; op2 at +100ms HTTP 202=%s",
				first.elapsed, secondElapsed)
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatal("stale op1 monitor was not superseded by op2")
}

func TestColdThenFourWarmPlaylistRequestsRespondBeforeExactConvergence(t *testing.T) {
	adapter := newTestAdapter(t, t.TempDir(), nil)
	adapter.config.StartTimeout = time.Second
	paths := make([]string, 5)
	for index := range paths {
		paths[index] = createFavoriteVGM(t, adapter,
			fmt.Sprintf("Warmup/%02d Track.vgm", index+1))
		if recorder := favoriteRequest(t, http.MethodPost, paths[index],
			adapter.HandleAddFavorite); recorder.Code != http.StatusOK {
			t.Fatal(recorder.Body.String())
		}
	}
	writeSupervisor(t, adapter, "STOCK", "STOCK", "STOPPED", "")
	writeExecutable(t, adapter.config.SupervisorPath)
	invocation := 0
	adapter.run = func(_ context.Context, command string, _ ...string) ([]byte, error) {
		invocation++
		if command == adapter.config.SupervisorPath {
			time.Sleep(60 * time.Millisecond) // deterministic cold bootstrap work
			writeSupervisor(t, adapter, "MEGAVGM", "MODIFIED", "RUNNING",
				filepath.Dir(paths[0]))
			makeFIFO(t, adapter.config.CommandPath)
			writeExecutable(t, adapter.config.CtlPath)
		} else {
			time.Sleep(5 * time.Millisecond) // warm controller command acceptance
		}
		return nil, nil
	}

	responseTimes := make([]time.Duration, len(paths))
	for index, path := range paths {
		// The controller can already publish PLAYING/current-session while the
		// playlist metadata still reflects the preceding command. That partial
		// truth must not hold the HTTP response open.
		if index > 0 {
			partial := strings.Replace(validStatus,
				"path=/media/fat/Music/04 Beyond the Galaxy.vgm", "path="+paths[index-1], 1)
			partial += "context=PLAYLIST\nplaylist=Favorites\n"
			writeFile(t, adapter.config.StatusPath, partial, 0644)
		}
		started := time.Now()
		recorder := playlistHTTPRequest(t, http.MethodPost, "Favorites",
			fmt.Sprintf(`{"index":%d}`, index), adapter.HandlePlayPlaylist)
		responseTimes[index] = time.Since(started)
		if recorder.Code != http.StatusAccepted {
			t.Fatalf("play %d: code=%d body=%s", index+1,
				recorder.Code, recorder.Body.String())
		}
		limit := 150 * time.Millisecond
		if index > 0 {
			limit = 100 * time.Millisecond
		}
		if responseTimes[index] >= limit {
			t.Fatalf("play %d response waited for convergence: %s",
				index+1, responseTimes[index])
		}

		// Publish the exact owner only after the accepted response. The monitor
		// remains useful diagnostically but cannot serialize the next request.
		exact := strings.Replace(validStatus,
			"path=/media/fat/Music/04 Beyond the Galaxy.vgm", "path="+path, 1)
		exact = strings.Replace(exact, "index=4", fmt.Sprintf("index=%d", index+1), 1)
		exact = strings.Replace(exact, "count=10", "count=5", 1)
		exact += "context=PLAYLIST\nplaylist=Favorites\n"
		writeFile(t, adapter.config.StatusPath, exact, 0644)
		time.Sleep(60 * time.Millisecond)
	}

	if invocation != 5 {
		t.Fatalf("command dispatch count=%d", invocation)
	}
	for index, elapsed := range responseTimes {
		t.Logf("Play #%d command-to-HTTP-202=%s", index+1, elapsed)
	}
	traces := readHandoffTraces(t, adapter)
	convergedLatest := false
	for _, trace := range traces {
		if trace.Event == "playlist_status_monitor_complete" &&
			trace.OperationID == 5 && trace.Result == "converged" {
			convergedLatest = true
		}
	}
	if !convergedLatest {
		t.Fatal("latest of five operations did not converge asynchronously")
	}
}

func TestSevenSecondColdBootstrapDoesNotQueueFollowingWarmPlays(t *testing.T) {
	adapter := newTestAdapter(t, t.TempDir(), nil)
	adapter.config.StartTimeout = 9 * time.Second
	paths := make([]string, 5)
	for index := range paths {
		paths[index] = createFavoriteVGM(t, adapter,
			fmt.Sprintf("SevenSecond/%02d Track.vgm", index+1))
		if recorder := favoriteRequest(t, http.MethodPost, paths[index],
			adapter.HandleAddFavorite); recorder.Code != http.StatusOK {
			t.Fatal(recorder.Body.String())
		}
	}
	writeSupervisor(t, adapter, "STOCK", "STOCK", "STOPPED", "")
	writeExecutable(t, adapter.config.SupervisorPath)
	makeFIFO(t, adapter.config.CommandPath)
	writeExecutable(t, adapter.config.CtlPath)
	acceptancePublished := make(chan time.Time, 1)
	adapter.run = func(ctx context.Context, command string, _ ...string) ([]byte, error) {
		if command != adapter.config.SupervisorPath {
			return nil, nil
		}
		time.Sleep(6 * time.Second)
		loading := strings.Replace(validStatus, "state=PLAYING", "state=LOADING", 1)
		loading = strings.Replace(loading,
			"path=/media/fat/Music/04 Beyond the Galaxy.vgm", "path="+paths[0], 1)
		loading = strings.Replace(loading, "index=4", "index=1", 1)
		loading += "context=PLAYLIST\nplaylist=Favorites\n"
		if err := atomicReplaceFile(adapter.config.StatusPath, []byte(loading)); err != nil {
			return nil, err
		}
		time.Sleep(time.Second)
		playing := strings.Replace(loading, "state=LOADING", "state=PLAYING", 1)
		if err := atomicReplaceFile(adapter.config.StatusPath, []byte(playing)); err != nil {
			return nil, err
		}
		if err := atomicReplaceFile(adapter.config.SupervisorStatusPath,
			[]byte(supervisorStatus("MEGAVGM", "MODIFIED", "RUNNING",
				filepath.Dir(paths[0])))); err != nil {
			return nil, err
		}
		acceptancePublished <- time.Now()
		<-ctx.Done()
		return []byte("MEGAVGM MODE ACTIVE\n"), ctx.Err()
	}

	firstStarted := time.Now()
	first := playlistHTTPRequest(t, http.MethodPost, "Favorites", `{"index":0}`,
		adapter.HandlePlayPlaylist)
	firstElapsed := time.Since(firstStarted)
	acceptedAt := <-acceptancePublished
	if first.Code != http.StatusAccepted {
		t.Fatalf("cold response=%d body=%s", first.Code, first.Body.String())
	}
	if responseAfterAcceptance := time.Since(acceptedAt); responseAfterAcceptance >= 200*time.Millisecond {
		t.Fatalf("HTTP response lagged accepted seven-second bootstrap: %s",
			responseAfterAcceptance)
	}
	if firstElapsed < 7*time.Second || firstElapsed >= 8*time.Second {
		t.Fatalf("cold fixture duration=%s", firstElapsed)
	}

	for index := 1; index < len(paths); index++ {
		started := time.Now()
		recorder := playlistHTTPRequest(t, http.MethodPost, "Favorites",
			fmt.Sprintf(`{"index":%d}`, index), adapter.HandlePlayPlaylist)
		elapsed := time.Since(started)
		if recorder.Code != http.StatusAccepted || elapsed >= 200*time.Millisecond {
			t.Fatalf("warm op%d queued: code=%d elapsed=%s body=%s",
				index+1, recorder.Code, elapsed, recorder.Body.String())
		}
		t.Logf("Play #%d after seven-second bootstrap HTTP 202=%s", index+1, elapsed)
	}
	exact := strings.Replace(validStatus,
		"path=/media/fat/Music/04 Beyond the Galaxy.vgm", "path="+paths[4], 1)
	exact = strings.Replace(exact, "index=4", "index=5", 1)
	exact = strings.Replace(exact, "count=10", "count=5", 1)
	exact += "context=PLAYLIST\nplaylist=Favorites\n"
	if err := atomicReplaceFile(adapter.config.StatusPath, []byte(exact)); err != nil {
		t.Fatal(err)
	}
	time.Sleep(60 * time.Millisecond)
}

func TestParsePlaylistContextStatus(t *testing.T) {
	content := validStatus + "context=PLAYLIST\nplaylist=Favorites\n"
	status, err := ParseStatus(strings.NewReader(content))
	if err != nil {
		t.Fatal(err)
	}
	if status.Context != "PLAYLIST" || status.Playlist != "Favorites" {
		t.Fatalf("context=%#v", status)
	}
}

func TestPlaylistJSONRemainsVersionOne(t *testing.T) {
	adapter := newTestAdapter(t, t.TempDir(), nil)
	_ = request(t, http.MethodPost, strings.NewReader(`{"name":"User"}`), adapter.HandleCreatePlaylist)
	data, err := os.ReadFile(adapter.config.FavoritesPath)
	if err != nil {
		t.Fatal(err)
	}
	var document map[string]interface{}
	if err := json.Unmarshal(data, &document); err != nil {
		t.Fatal(err)
	}
	if document["version"] != float64(1) {
		t.Fatalf("schema changed: %s", data)
	}
}
