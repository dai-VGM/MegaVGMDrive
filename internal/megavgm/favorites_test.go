package megavgm

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
)

func favoriteRequest(t *testing.T, method, path string, handler http.HandlerFunc) *httptest.ResponseRecorder {
	t.Helper()
	body, err := json.Marshal(startRequest{Path: path})
	if err != nil {
		t.Fatal(err)
	}
	recorder := httptest.NewRecorder()
	handler(recorder, httptest.NewRequest(method, "/", strings.NewReader(string(body))))
	return recorder
}

func getFavorites(t *testing.T, adapter *Adapter) FavoritesResponse {
	t.Helper()
	recorder := request(t, http.MethodGet, nil, adapter.HandleFavorites)
	if recorder.Code != http.StatusOK {
		t.Fatalf("status=%d body=%s", recorder.Code, recorder.Body.String())
	}
	var response FavoritesResponse
	decodeResponse(t, recorder, &response)
	return response
}

func createFavoriteVGM(t *testing.T, adapter *Adapter, relative string) string {
	t.Helper()
	path := filepath.Join(adapter.config.ApprovedRoot, filepath.FromSlash(relative))
	mustMkdir(t, filepath.Dir(path))
	writeFile(t, path, "Vgm ", 0644)
	canonical, err := filepath.EvalSymlinks(path)
	if err != nil {
		t.Fatal(err)
	}
	return canonical
}

func TestFavoritesFirstUseAddDuplicateRemoveAndOrder(t *testing.T) {
	adapter := newTestAdapter(t, t.TempDir(), nil)
	first := createFavoriteVGM(t, adapter, "Album/01 First.vgm")
	second := createFavoriteVGM(t, adapter, "Other/02 Second.vgm")

	empty := getFavorites(t, adapter)
	if empty.Version != 1 || empty.Playlist != "Favorites" || len(empty.Entries) != 0 {
		t.Fatalf("unexpected empty response: %#v", empty)
	}
	data, err := os.ReadFile(adapter.config.FavoritesPath)
	if err != nil {
		t.Fatal(err)
	}
	var document favoritesDocument
	if err := json.Unmarshal(data, &document); err != nil || document.Version != 1 {
		t.Fatalf("invalid first-use storage: %s err=%v", data, err)
	}

	for _, path := range []string{first, first, second} {
		recorder := favoriteRequest(t, http.MethodPost, path, adapter.HandleAddFavorite)
		if recorder.Code != http.StatusOK {
			t.Fatalf("add status=%d body=%s", recorder.Code, recorder.Body.String())
		}
	}
	response := getFavorites(t, adapter)
	if len(response.Entries) != 2 || response.Entries[0].Path != first ||
		response.Entries[1].Path != second {
		t.Fatalf("favorites lost order/idempotence: %#v", response.Entries)
	}
	if response.Entries[0].Title != "01 First" ||
		response.Entries[0].Directory != "Album" || !response.Entries[0].Available {
		t.Fatalf("unsafe display projection: %#v", response.Entries[0])
	}

	for attempt := 0; attempt < 2; attempt++ {
		recorder := favoriteRequest(t, http.MethodDelete, first, adapter.HandleRemoveFavorite)
		if recorder.Code != http.StatusOK {
			t.Fatalf("remove status=%d body=%s", recorder.Code, recorder.Body.String())
		}
	}
	response = getFavorites(t, adapter)
	if len(response.Entries) != 1 || response.Entries[0].Path != second {
		t.Fatalf("remove was not idempotent: %#v", response.Entries)
	}
}

func TestFavoritesHundredSequentialMutations(t *testing.T) {
	adapter := newTestAdapter(t, t.TempDir(), nil)
	paths := make([]string, 100)
	stressDirectory := filepath.Join(adapter.config.ApprovedRoot, "Stress")
	mustMkdir(t, stressDirectory)
	canonicalStressDirectory, err := filepath.EvalSymlinks(stressDirectory)
	if err != nil {
		t.Fatal(err)
	}
	for index := range paths {
		paths[index] = filepath.Join(canonicalStressDirectory,
			fmt.Sprintf("%03d Track.vgm", index))
		writeFile(t, paths[index], "Vgm ", 0644)
		if recorder := favoriteRequest(t, http.MethodPost, paths[index], adapter.HandleAddFavorite); recorder.Code != http.StatusOK {
			t.Fatalf("add %d status=%d body=%s", index, recorder.Code, recorder.Body.String())
		}
	}
	for index := 0; index < len(paths); index += 2 {
		if recorder := favoriteRequest(t, http.MethodDelete, paths[index], adapter.HandleRemoveFavorite); recorder.Code != http.StatusOK {
			t.Fatalf("remove %d status=%d body=%s", index, recorder.Code, recorder.Body.String())
		}
	}
	response := getFavorites(t, adapter)
	if len(response.Entries) != 50 {
		t.Fatalf("entries=%d", len(response.Entries))
	}
	for index, entry := range response.Entries {
		if entry.Path != paths[index*2+1] {
			t.Fatalf("order[%d]=%q", index, entry.Path)
		}
	}
}

func TestFavoritesConcurrentHTTPMutationHasNoLostUpdates(t *testing.T) {
	adapter := newTestAdapter(t, t.TempDir(), nil)
	paths := make([]string, 64)
	for index := range paths {
		paths[index] = createFavoriteVGM(t, adapter,
			fmt.Sprintf("Concurrent/%02d Track.vgm", index))
	}

	var wait sync.WaitGroup
	errorsSeen := make(chan string, len(paths)*2)
	for _, path := range paths {
		for attempt := 0; attempt < 2; attempt++ {
			wait.Add(1)
			go func(path string) {
				defer wait.Done()
				recorder := favoriteRequest(t, http.MethodPost, path, adapter.HandleAddFavorite)
				if recorder.Code != http.StatusOK {
					errorsSeen <- recorder.Body.String()
				}
			}(path)
		}
	}
	wait.Wait()
	close(errorsSeen)
	for failure := range errorsSeen {
		t.Fatalf("concurrent mutation failed: %s", failure)
	}
	response := getFavorites(t, adapter)
	if len(response.Entries) != len(paths) {
		t.Fatalf("lost concurrent updates: got=%d want=%d", len(response.Entries), len(paths))
	}
	if _, err := os.ReadFile(adapter.config.FavoritesPath); err != nil {
		t.Fatal(err)
	}
}

func TestFavoritesAtomicWriteFailurePreservesPrimary(t *testing.T) {
	adapter := newTestAdapter(t, t.TempDir(), nil)
	first := createFavoriteVGM(t, adapter, "Atomic/01 First.vgm")
	second := createFavoriteVGM(t, adapter, "Atomic/02 Second.vgm")
	if recorder := favoriteRequest(t, http.MethodPost, first, adapter.HandleAddFavorite); recorder.Code != http.StatusOK {
		t.Fatal(recorder.Body.String())
	}
	before, err := os.ReadFile(adapter.config.FavoritesPath)
	if err != nil {
		t.Fatal(err)
	}
	realAtomicWrite := adapter.favorites.atomicWrite
	adapter.favorites.atomicWrite = func(path string, data []byte) error {
		if path == adapter.config.FavoritesPath {
			return errors.New("injected rename failure")
		}
		return realAtomicWrite(path, data)
	}
	recorder := favoriteRequest(t, http.MethodPost, second, adapter.HandleAddFavorite)
	assertAPIError(t, recorder, http.StatusInternalServerError, "favorites_write_failed")
	after, err := os.ReadFile(adapter.config.FavoritesPath)
	if err != nil {
		t.Fatal(err)
	}
	if string(after) != string(before) {
		t.Fatal("primary changed after failed atomic replacement")
	}
}

func TestFavoritesMalformedJSONAndBackupRecovery(t *testing.T) {
	adapter := newTestAdapter(t, t.TempDir(), nil)
	mustMkdir(t, filepath.Dir(adapter.config.FavoritesPath))
	writeFile(t, adapter.config.FavoritesPath, "{broken", 0644)
	assertAPIError(t, request(t, http.MethodGet, nil, adapter.HandleFavorites),
		http.StatusInternalServerError, "favorites_storage_unavailable")

	path := createFavoriteVGM(t, adapter, "Recovery/01 Saved.vgm")
	document := emptyFavoritesDocument()
	document.Playlists[favoritesPlaylistName] = []string{path}
	backup, err := encodeFavoritesDocument(document)
	if err != nil {
		t.Fatal(err)
	}
	if err := atomicReplaceFile(adapter.config.FavoritesPath+".bak", backup); err != nil {
		t.Fatal(err)
	}
	response := getFavorites(t, adapter)
	if len(response.Entries) != 1 || response.Entries[0].Path != path {
		t.Fatalf("backup was not recovered: %#v", response)
	}
}

func TestFavoritesUnavailableEntryAndDeleteAfterFileRemoval(t *testing.T) {
	adapter := newTestAdapter(t, t.TempDir(), nil)
	path := createFavoriteVGM(t, adapter, "Missing/01 Gone.vgm")
	if recorder := favoriteRequest(t, http.MethodPost, path, adapter.HandleAddFavorite); recorder.Code != http.StatusOK {
		t.Fatal(recorder.Body.String())
	}
	if err := os.Remove(path); err != nil {
		t.Fatal(err)
	}
	response := getFavorites(t, adapter)
	if len(response.Entries) != 1 || response.Entries[0].Available {
		t.Fatalf("deleted favorite not represented as unavailable: %#v", response)
	}
	if recorder := favoriteRequest(t, http.MethodDelete, path, adapter.HandleRemoveFavorite); recorder.Code != http.StatusOK {
		t.Fatalf("delete unavailable status=%d body=%s", recorder.Code, recorder.Body.String())
	}
}

func TestFavoritesRejectOutsideTraversalSymlinkAndInvalidFile(t *testing.T) {
	dir := t.TempDir()
	adapter := newTestAdapter(t, dir, nil)
	outside := filepath.Join(dir, "outside.vgm")
	writeFile(t, outside, "Vgm ", 0644)
	symlink := filepath.Join(adapter.config.ApprovedRoot, "escape.vgm")
	if err := os.Symlink(outside, symlink); err != nil {
		t.Fatal(err)
	}
	invalid := []string{
		outside,
		filepath.Join(adapter.config.ApprovedRoot, "..", "outside.vgm"),
		symlink,
		filepath.Join(adapter.config.ApprovedRoot, "missing.vgm"),
	}
	for _, path := range invalid {
		assertAPIError(t, favoriteRequest(t, http.MethodPost, path, adapter.HandleAddFavorite),
			http.StatusBadRequest, "invalid_vgm_path")
	}
}

func TestFavoritesPersistAcrossAdapterRestartAndPlayUsesExistingHandler(t *testing.T) {
	dir := t.TempDir()
	firstAdapter := newTestAdapter(t, dir, nil)
	path := createFavoriteVGM(t, firstAdapter, "Restart/01 Persistent.vgm")
	if recorder := favoriteRequest(t, http.MethodPost, path, firstAdapter.HandleAddFavorite); recorder.Code != http.StatusOK {
		t.Fatal(recorder.Body.String())
	}

	var invocation []string
	secondAdapter := newTestAdapter(t, dir, func(_ context.Context, command string, args ...string) ([]byte, error) {
		invocation = append([]string{command}, args...)
		return nil, nil
	})
	response := getFavorites(t, secondAdapter)
	if len(response.Entries) != 1 || response.Entries[0].Path != path {
		t.Fatalf("favorite did not persist: %#v", response)
	}
	writeSupervisor(t, secondAdapter, "MEGAVGM", "MODIFIED", "RUNNING", secondAdapter.config.DefaultPlaylistPath)
	makeFIFO(t, secondAdapter.config.CommandPath)
	writeExecutable(t, secondAdapter.config.CtlPath)
	recorder := playRequest(t, secondAdapter, response.Entries[0].Path)
	if recorder.Code != http.StatusAccepted || len(invocation) != 3 ||
		invocation[0] != secondAdapter.config.CtlPath || invocation[1] != "play" || invocation[2] != path {
		t.Fatalf("favorite did not use existing Play handler: invocation=%#v body=%s", invocation, recorder.Body.String())
	}
}
