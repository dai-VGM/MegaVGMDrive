package megavgm

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"
)

func browseRequest(t *testing.T, adapter *Adapter, path string) *httptest.ResponseRecorder {
	t.Helper()
	request := httptest.NewRequest(http.MethodGet,
		"/?path="+url.QueryEscape(path), nil)
	recorder := httptest.NewRecorder()
	adapter.HandleBrowse(recorder, request)
	return recorder
}

func playRequest(t *testing.T, adapter *Adapter, path string) *httptest.ResponseRecorder {
	t.Helper()
	body, err := json.Marshal(startRequest{Path: path})
	if err != nil {
		t.Fatal(err)
	}
	return request(t, http.MethodPost, strings.NewReader(string(body)), adapter.HandlePlay)
}

func TestBrowseRootNestedFilteringAndBytewiseOrder(t *testing.T) {
	adapter := newTestAdapter(t, t.TempDir(), nil)
	root := adapter.config.ApprovedRoot
	for _, name := range []string{"Zeta", "[Arcade]", "日本語", "Space Folder"} {
		mustMkdir(t, filepath.Join(root, name))
	}
	for _, name := range []string{
		"10 End.vgm", "02 [Stage].vgm", "01 日本語.vgm", "04 SID.mvgmsid", ".hidden.vgm",
		"raw.sid", "packed.mvgmsid2", "ignore.txt", "upper.VGM", "temporary.vgm.tmp",
	} {
		writeFile(t, filepath.Join(root, name), "x", 0644)
	}
	recorder := browseRequest(t, adapter, "")
	if recorder.Code != http.StatusOK {
		t.Fatalf("status=%d body=%s", recorder.Code, recorder.Body.String())
	}
	var response BrowseResponse
	decodeResponse(t, recorder, &response)
	if response.Path != "" || response.Parent != "" {
		t.Fatalf("unexpected root: %#v", response)
	}
	want := []BrowseEntry{
		{Name: "01 日本語.vgm", Type: "file"},
		{Name: "01_Arcade", Type: "directory"},
		{Name: "02 [Stage].vgm", Type: "file"},
		{Name: "04 SID.mvgmsid", Type: "file"},
		{Name: "10 End.vgm", Type: "file"},
		{Name: "Space Folder", Type: "directory"},
		{Name: "Zeta", Type: "directory"},
		{Name: "[Arcade]", Type: "directory"},
		{Name: "raw.sid", Type: "file"},
		{Name: "日本語", Type: "directory"},
	}
	if !reflect.DeepEqual(response.Entries, want) {
		t.Fatalf("entries=%#v", response.Entries)
	}

	nested := filepath.Join(root, "Space Folder", "[Album] 日本語")
	mustMkdir(t, nested)
	writeFile(t, filepath.Join(nested, "03 Track.vgm"), "x", 0644)
	recorder = browseRequest(t, adapter, "Space Folder/[Album] 日本語")
	decodeResponse(t, recorder, &response)
	if recorder.Code != http.StatusOK ||
		response.Path != "Space Folder/[Album] 日本語" ||
		response.Parent != "Space Folder" || len(response.Entries) != 1 {
		t.Fatalf("unexpected nested response: %#v", response)
	}
}

func TestPreparedSIDPlayUsesExistingSupervisorRoute(t *testing.T) {
	dir := t.TempDir()
	var invocation []string
	adapter := newTestAdapter(t, dir, nil)
	selected := filepath.Join(adapter.config.DefaultPlaylistPath, "Commando.mvgmsid")
	writeFile(t, selected, "MVGMSID\x00", 0644)
	adapter.run = func(_ context.Context, path string, args ...string) ([]byte, error) {
		invocation = append([]string{path}, args...)
		writeSupervisor(t, adapter, "MEGAVGM", "MODIFIED", "RUNNING", adapter.config.DefaultPlaylistPath)
		return []byte("MEGAVGM MODE ACTIVE\n"), nil
	}
	writeSupervisor(t, adapter, "STOCK", "STOCK", "STOPPED", "")
	writeExecutable(t, adapter.config.SupervisorPath)
	recorder := playRequest(t, adapter, selected)
	canonicalSelected, err := filepath.EvalSymlinks(selected)
	if err != nil {
		t.Fatal(err)
	}
	if recorder.Code != http.StatusAccepted || len(invocation) != 5 || invocation[2] != "--start-file" || invocation[3] != canonicalSelected {
		t.Fatalf("status=%d invocation=%#v body=%s", recorder.Code, invocation, recorder.Body.String())
	}
	for _, rejected := range []string{"packed.mvgmsid2"} {
		path := filepath.Join(adapter.config.DefaultPlaylistPath, rejected)
		writeFile(t, path, "x", 0644)
		assertAPIError(t, playRequest(t, adapter, path), http.StatusBadRequest, "invalid_vgm_path")
	}
	writeSupervisor(t, adapter, "STOCK", "STOCK", "STOPPED", "")
	raw := filepath.Join(adapter.config.DefaultPlaylistPath, "raw.sid")
	writeFile(t, raw, "PSID", 0644)
	if response := playRequest(t, adapter, raw); response.Code != http.StatusAccepted {
		t.Fatalf("raw SID was not admitted to the existing Supervisor route: %d %s",
			response.Code, response.Body.String())
	}
}

func TestNativeNSFePlayUsesExistingSupervisorRoute(t *testing.T) {
	dir := t.TempDir()
	var invocation []string
	adapter := newTestAdapter(t, dir, nil)
	selected := filepath.Join(adapter.config.DefaultPlaylistPath, "AkumajouDensetsu.nsfe")
	writeFile(t, selected, "NSFE", 0644)
	adapter.run = func(_ context.Context, path string, args ...string) ([]byte, error) {
		invocation = append([]string{path}, args...)
		writeSupervisor(t, adapter, "MEGAVGM", "MODIFIED", "RUNNING", adapter.config.DefaultPlaylistPath)
		return []byte("MEGAVGM MODE ACTIVE\n"), nil
	}
	writeSupervisor(t, adapter, "STOCK", "STOCK", "STOPPED", "")
	writeExecutable(t, adapter.config.SupervisorPath)
	recorder := playRequest(t, adapter, selected)
	canonicalSelected, err := filepath.EvalSymlinks(selected)
	if err != nil {
		t.Fatal(err)
	}
	if recorder.Code != http.StatusAccepted || len(invocation) != 5 || invocation[2] != "--start-file" || invocation[3] != canonicalSelected {
		t.Fatalf("status=%d invocation=%#v body=%s", recorder.Code, invocation, recorder.Body.String())
	}
	for _, rejected := range []string{"packed.mvgmsid2"} {
		path := filepath.Join(adapter.config.DefaultPlaylistPath, rejected)
		writeFile(t, path, "x", 0644)
		assertAPIError(t, playRequest(t, adapter, path), http.StatusBadRequest, "invalid_vgm_path")
	}
	writeSupervisor(t, adapter, "STOCK", "STOCK", "STOPPED", "")
	raw := filepath.Join(adapter.config.DefaultPlaylistPath, "raw.sid")
	writeFile(t, raw, "PSID", 0644)
	if response := playRequest(t, adapter, raw); response.Code != http.StatusAccepted {
		t.Fatalf("raw SID was not admitted to the existing Supervisor route: %d %s",
			response.Code, response.Body.String())
	}
}

func TestBrowseRejectsTraversalSymlinkEscapeAndMissingDirectory(t *testing.T) {
	dir := t.TempDir()
	adapter := newTestAdapter(t, dir, nil)
	outside := filepath.Join(dir, "outside")
	mustMkdir(t, outside)
	if err := os.Symlink(outside, filepath.Join(adapter.config.ApprovedRoot, "escape")); err != nil {
		t.Fatal(err)
	}
	for _, path := range []string{"..", "escape", "missing"} {
		recorder := browseRequest(t, adapter, path)
		assertAPIError(t, recorder, http.StatusBadRequest, "invalid_browse_path")
	}
}

func TestPlayFromStockPassesSelectedFileToSupervisor(t *testing.T) {
	dir := t.TempDir()
	var invocation []string
	adapter := newTestAdapter(t, dir, nil)
	selected := filepath.Join(adapter.config.DefaultPlaylistPath, "03 Scene Select.vgm")
	writeFile(t, selected, "Vgm ", 0644)
	adapter.run = func(_ context.Context, path string, args ...string) ([]byte, error) {
		invocation = append([]string{path}, args...)
		writeSupervisor(t, adapter, "MEGAVGM", "MODIFIED", "RUNNING",
			adapter.config.DefaultPlaylistPath)
		return []byte("MEGAVGM MODE ACTIVE\n"), nil
	}
	writeSupervisor(t, adapter, "STOCK", "STOCK", "STOPPED", "")
	writeExecutable(t, adapter.config.SupervisorPath)
	recorder := playRequest(t, adapter, selected)
	if recorder.Code != http.StatusAccepted {
		t.Fatalf("status=%d body=%s", recorder.Code, recorder.Body.String())
	}
	if got := recorder.Header().Get("X-MegaVGM-Play-Handler"); got != "generic-file" {
		t.Fatalf("handler header=%q", got)
	}
	canonicalSelected, err := filepath.EvalSymlinks(selected)
	if err != nil {
		t.Fatal(err)
	}
	canonicalDirectory, err := filepath.EvalSymlinks(adapter.config.DefaultPlaylistPath)
	if err != nil {
		t.Fatal(err)
	}
	want := []string{adapter.config.SupervisorPath, "enter", "--start-file",
		canonicalSelected, canonicalDirectory}
	if !reflect.DeepEqual(invocation, want) {
		t.Fatalf("invocation=%#v", invocation)
	}
	traces := readHandoffTraces(t, adapter)
	if len(traces) != 1 || traces[0].Event != "remote_http" ||
		traces[0].Handler != "HandlePlay" || traces[0].Context != "PARENT_FOLDER" ||
		traces[0].SupervisorMode != "STOCK" || traces[0].Selected != canonicalSelected ||
		traces[0].Directory != canonicalDirectory {
		t.Fatalf("generic play trace=%#v", traces)
	}
}

func TestPlayFromStockWaitsForSupervisorStatusConvergence(t *testing.T) {
	dir := t.TempDir()
	adapter := newTestAdapter(t, dir, nil)
	adapter.config.StartTimeout = time.Second
	selected := filepath.Join(adapter.config.DefaultPlaylistPath, "03 Scene Select.vgm")
	writeFile(t, selected, "Vgm ", 0644)
	writeSupervisor(t, adapter, "STOCK", "STOCK", "STOPPED", "")
	writeExecutable(t, adapter.config.SupervisorPath)
	writeErrors := make(chan error, 1)
	adapter.run = func(_ context.Context, _ string, _ ...string) ([]byte, error) {
		go func() {
			time.Sleep(80 * time.Millisecond)
			writeErrors <- os.WriteFile(adapter.config.SupervisorStatusPath,
				[]byte(supervisorStatus("MEGAVGM", "MODIFIED", "RUNNING",
					adapter.config.DefaultPlaylistPath)), 0644)
		}()
		return []byte("ENTER ACCEPTED\n"), nil
	}
	recorder := playRequest(t, adapter, selected)
	if err := <-writeErrors; err != nil {
		t.Fatal(err)
	}
	if recorder.Code != http.StatusAccepted {
		t.Fatalf("status=%d body=%s", recorder.Code, recorder.Body.String())
	}
}

func TestPlayWhileActiveDelegatesToController(t *testing.T) {
	dir := t.TempDir()
	var invocation []string
	adapter := newTestAdapter(t, dir, func(_ context.Context, path string,
		args ...string) ([]byte, error) {
		invocation = append([]string{path}, args...)
		return nil, nil
	})
	other := filepath.Join(adapter.config.ApprovedRoot, "02_Arcade", "After Burner II")
	mustMkdir(t, other)
	selected := filepath.Join(other, "02 Final Take Off.vgm")
	writeFile(t, selected, "Vgm ", 0644)
	writeSupervisor(t, adapter, "MEGAVGM", "MODIFIED", "RUNNING",
		adapter.config.DefaultPlaylistPath)
	makeFIFO(t, adapter.config.CommandPath)
	writeExecutable(t, adapter.config.CtlPath)
	recorder := playRequest(t, adapter, selected)
	if recorder.Code != http.StatusAccepted {
		t.Fatalf("status=%d body=%s", recorder.Code, recorder.Body.String())
	}
	canonicalSelected, err := filepath.EvalSymlinks(selected)
	if err != nil {
		t.Fatal(err)
	}
	want := []string{adapter.config.CtlPath, "play", canonicalSelected}
	if !reflect.DeepEqual(invocation, want) {
		t.Fatalf("invocation=%#v", invocation)
	}
}

func TestPlayRejectsInvalidFilesAndSymlinks(t *testing.T) {
	dir := t.TempDir()
	adapter := newTestAdapter(t, dir, nil)
	writeSupervisor(t, adapter, "STOCK", "STOCK", "STOPPED", "")
	nonVGM := filepath.Join(adapter.config.ApprovedRoot, "track.txt")
	writeFile(t, nonVGM, "x", 0644)
	outside := filepath.Join(dir, "outside.vgm")
	writeFile(t, outside, "x", 0644)
	symlink := filepath.Join(adapter.config.ApprovedRoot, "escape.vgm")
	if err := os.Symlink(outside, symlink); err != nil {
		t.Fatal(err)
	}
	for _, path := range []string{"../outside.vgm", nonVGM, symlink, "missing.vgm",
		strings.Repeat("x", MaximumPlayPath+1) + ".vgm"} {
		assertAPIError(t, playRequest(t, adapter, path),
			http.StatusBadRequest, "invalid_vgm_path")
	}
}

func TestPlayPropagatesSupervisorFailureAndControllerUnavailable(t *testing.T) {
	dir := t.TempDir()
	adapter := newTestAdapter(t, dir, func(context.Context, string,
		...string) ([]byte, error) {
		return []byte("ENTER_FAILED\n"), errors.New("exit 1")
	})
	selected := filepath.Join(adapter.config.DefaultPlaylistPath, "01 Credit.vgm")
	writeFile(t, selected, "Vgm ", 0644)
	writeExecutable(t, adapter.config.SupervisorPath)
	writeSupervisor(t, adapter, "STOCK", "STOCK", "STOPPED", "")
	assertAPIError(t, playRequest(t, adapter, selected),
		http.StatusBadGateway, "supervisor_start_failed")

	writeSupervisor(t, adapter, "MEGAVGM", "MODIFIED", "RUNNING",
		adapter.config.DefaultPlaylistPath)
	assertAPIError(t, playRequest(t, adapter, selected),
		http.StatusServiceUnavailable, "controller_unavailable")
}

func TestResourceCapacityRejectionBeforeColdSelection(t *testing.T) {
	for _, body := range []string{
		"PHASE2A_PREFLIGHT_FAILED: resource_capacity_exceeded\n",
		"log\nPHASE2A_PREFLIGHT_FAILED: resource_capacity_exceeded\n",
	} {
		a := newTestAdapter(t, t.TempDir(), nil)
		selected := filepath.Join(a.config.DefaultPlaylistPath, "01 Over.vgm")
		writeFile(t, selected, "Vgm ", 0644)
		writeExecutable(t, a.config.SupervisorPath)
		writeSupervisor(t, a, "STOCK", "STOCK", "STOPPED", "")
		a.run = func(context.Context, string, ...string) ([]byte, error) { return []byte(body), errors.New("exit1") }
		response := playRequest(t, a, selected)
		if response.Code != http.StatusConflict || !strings.Contains(response.Body.String(), "resource_capacity_exceeded") {
			t.Fatalf("status %d body %s", response.Code, response.Body.String())
		}
	}
	for _, body := range []string{"/music/resource_capacity_exceeded.vgm", "PHASE2A_PREFLIGHT_FAILED: resource_capacity_exceeded EXTRA", "resource_capacity_exceeded", ""} {
		if resourceCapacityOutput([]byte(body)) {
			t.Fatalf("false resource rejection %q", body)
		}
	}
}

func TestResourceCapacityColdDirectoryAndNamedPlaylist(t *testing.T) {
	for _, route := range []string{"directory", "playlist"} {
		t.Run(route, func(t *testing.T) {
			a := newTestAdapter(t, t.TempDir(), nil)
			a.config.StartTimeout = DefaultStartTimeout
			selected := createFavoriteVGM(t, a, "Capacity/01 Over.vgm")
			writeExecutable(t, a.config.SupervisorPath)
			writeSupervisor(t, a, "STOCK", "STOCK", "STOPPED", "")
			calls := 0
			a.run = func(context.Context, string, ...string) ([]byte, error) {
				calls++
				return []byte("PHASE2A_PREFLIGHT_FAILED: resource_capacity_exceeded\n"), errors.New("exit1")
			}
			var response *httptest.ResponseRecorder
			if route == "directory" {
				response = performStartRequest(t, a, filepath.Dir(selected))
			} else {
				if x := request(t, http.MethodPost, strings.NewReader(`{"name":"Capacity"}`), a.HandleCreatePlaylist); x.Code != 201 {
					t.Fatal(x.Body.String())
				}
				body, _ := json.Marshal(map[string]string{"path": selected})
				if x := playlistHTTPRequest(t, http.MethodPost, "Capacity", string(body), a.HandleAddPlaylistTrack); x.Code != 200 {
					t.Fatal(x.Body.String())
				}
				response = playlistHTTPRequest(t, http.MethodPost, "Capacity", `{"index":0}`, a.HandlePlayPlaylist)
			}
			if calls != 1 || response.Code != http.StatusConflict || !strings.Contains(response.Body.String(), "resource_capacity_exceeded") {
				t.Fatalf("calls=%d status=%d body=%s", calls, response.Code, response.Body.String())
			}
		})
	}
}
