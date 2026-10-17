package megavgm

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
)

const (
	favoritesSchemaVersion = 1
	favoritesPlaylistName  = "Favorites"
)

var errFavoritesCorrupt = errors.New("favorites storage is corrupt")
var (
	errPlaylistExists   = errors.New("playlist already exists")
	errPlaylistMissing  = errors.New("playlist does not exist")
	errReservedPlaylist = errors.New("reserved playlist")
)

type favoritesDocument struct {
	Version   int                 `json:"version"`
	Playlists map[string][]string `json:"playlists"`
}

type FavoriteEntry struct {
	Path      string `json:"path"`
	Title     string `json:"title"`
	Filename  string `json:"filename"`
	Directory string `json:"directory"`
	Available bool   `json:"available"`
}

type FavoritesResponse struct {
	Version  int             `json:"version"`
	Playlist string          `json:"playlist"`
	Entries  []FavoriteEntry `json:"entries"`
}

type favoriteMutationResponse struct {
	Path     string `json:"path"`
	Favorite bool   `json:"favorite"`
}

type favoritesStore struct {
	mu          sync.Mutex
	path        string
	root        string
	atomicWrite func(string, []byte) error
}

func newFavoritesStore(path, root string) *favoritesStore {
	return &favoritesStore{
		path: path, root: root, atomicWrite: atomicReplaceFile,
	}
}

func emptyFavoritesDocument() favoritesDocument {
	return favoritesDocument{
		Version: favoritesSchemaVersion,
		Playlists: map[string][]string{
			favoritesPlaylistName: {},
		},
	}
}

func encodeFavoritesDocument(document favoritesDocument) ([]byte, error) {
	var encoded bytes.Buffer
	encoder := json.NewEncoder(&encoded)
	encoder.SetIndent("", "  ")
	if err := encoder.Encode(document); err != nil {
		return nil, err
	}
	return encoded.Bytes(), nil
}

func decodeFavoritesDocument(data []byte, root string) (favoritesDocument, error) {
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.DisallowUnknownFields()
	var document favoritesDocument
	if err := decoder.Decode(&document); err != nil {
		return favoritesDocument{}, errFavoritesCorrupt
	}
	var extra interface{}
	if err := decoder.Decode(&extra); !errors.Is(err, io.EOF) {
		return favoritesDocument{}, errFavoritesCorrupt
	}
	if document.Version != favoritesSchemaVersion || document.Playlists == nil {
		return favoritesDocument{}, errFavoritesCorrupt
	}
	paths, ok := document.Playlists[favoritesPlaylistName]
	if !ok || paths == nil {
		return favoritesDocument{}, errFavoritesCorrupt
	}
	_ = paths
	for name, playlistPaths := range document.Playlists {
		if !validPlaylistName(name) || playlistPaths == nil {
			return favoritesDocument{}, errFavoritesCorrupt
		}
		seen := make(map[string]bool, len(playlistPaths))
		normalized := make([]string, 0, len(playlistPaths))
		for _, path := range playlistPaths {
			identity, err := favoritePathIdentity(path, root)
			if err != nil {
				return favoritesDocument{}, errFavoritesCorrupt
			}
			if !seen[identity] {
				seen[identity] = true
				normalized = append(normalized, identity)
			}
		}
		document.Playlists[name] = normalized
	}
	return document, nil
}

func validPlaylistName(name string) bool {
	return name != "" && len(name) <= 80 && strings.TrimSpace(name) == name &&
		!hasControl(name) && !strings.ContainsAny(name, "/\\")
}

func atomicReplaceFile(path string, data []byte) error {
	directory := filepath.Dir(path)
	if err := os.MkdirAll(directory, 0755); err != nil {
		return err
	}
	temporary, err := os.CreateTemp(directory, ".playlists.json.tmp-")
	if err != nil {
		return err
	}
	temporaryPath := temporary.Name()
	defer os.Remove(temporaryPath)

	if err := temporary.Chmod(0644); err != nil {
		_ = temporary.Close()
		return err
	}
	if _, err := temporary.Write(data); err != nil {
		_ = temporary.Close()
		return err
	}
	if err := temporary.Sync(); err != nil {
		_ = temporary.Close()
		return err
	}
	if err := temporary.Close(); err != nil {
		return err
	}
	if err := os.Rename(temporaryPath, path); err != nil {
		return err
	}
	directoryHandle, err := os.Open(directory)
	if err != nil {
		return err
	}
	err = directoryHandle.Sync()
	closeErr := directoryHandle.Close()
	if err != nil {
		return err
	}
	return closeErr
}

func favoritePathIdentity(path, root string) (string, error) {
	if path == "" || len(path) > MaximumPlayPath || !filepath.IsAbs(path) ||
		hasControl(path) || pathHasDotDot(path) {
		return "", errors.New("invalid favorite path")
	}
	canonicalRoot, err := filepath.EvalSymlinks(root)
	if err != nil {
		return "", errors.New("approved root unavailable")
	}
	cleaned := filepath.Clean(path)
	if !withinRoot(canonicalRoot, cleaned) || !supportedTrackName(filepath.Base(cleaned)) {
		return "", errors.New("favorite path outside approved root")
	}
	return cleaned, nil
}

func favoriteAvailable(path, root string) bool {
	canonical, _, err := canonicalVGM(path, root)
	return err == nil && canonical == path
}

func favoriteEntry(path, root string) FavoriteEntry {
	filename := filepath.Base(path)
	canonicalRoot, rootErr := filepath.EvalSymlinks(root)
	if rootErr != nil {
		canonicalRoot = filepath.Clean(root)
	}
	directory, err := filepath.Rel(canonicalRoot, filepath.Dir(path))
	if err != nil || directory == "." {
		directory = ""
	}
	return FavoriteEntry{
		Path: path, Title: trackTitle(filename),
		Filename: filename, Directory: filepath.ToSlash(directory),
		Available: favoriteAvailable(path, root),
	}
}

func (store *favoritesStore) loadLocked() (favoritesDocument, []byte, error) {
	data, err := os.ReadFile(store.path)
	if errors.Is(err, os.ErrNotExist) {
		document := emptyFavoritesDocument()
		encoded, encodeErr := encodeFavoritesDocument(document)
		if encodeErr != nil {
			return favoritesDocument{}, nil, encodeErr
		}
		if writeErr := store.atomicWrite(store.path, encoded); writeErr != nil {
			return favoritesDocument{}, nil, writeErr
		}
		return document, encoded, nil
	}
	if err != nil {
		return favoritesDocument{}, nil, err
	}
	document, decodeErr := decodeFavoritesDocument(data, store.root)
	if decodeErr == nil {
		return document, data, nil
	}

	backupData, backupErr := os.ReadFile(store.path + ".bak")
	if backupErr != nil {
		return favoritesDocument{}, nil, errFavoritesCorrupt
	}
	backupDocument, backupDecodeErr := decodeFavoritesDocument(backupData, store.root)
	if backupDecodeErr != nil {
		return favoritesDocument{}, nil, errFavoritesCorrupt
	}
	if writeErr := store.atomicWrite(store.path, backupData); writeErr != nil {
		return favoritesDocument{}, nil, writeErr
	}
	return backupDocument, backupData, nil
}

func (store *favoritesStore) writeLocked(document favoritesDocument, previous []byte) error {
	encoded, err := encodeFavoritesDocument(document)
	if err != nil {
		return err
	}
	if bytes.Equal(encoded, previous) {
		return nil
	}
	if len(previous) != 0 {
		if err := store.atomicWrite(store.path+".bak", previous); err != nil {
			return fmt.Errorf("write favorites backup: %w", err)
		}
	}
	if err := store.atomicWrite(store.path, encoded); err != nil {
		return fmt.Errorf("write favorites: %w", err)
	}
	return nil
}

func (store *favoritesStore) list() ([]string, error) {
	store.mu.Lock()
	defer store.mu.Unlock()
	document, _, err := store.loadLocked()
	if err != nil {
		return nil, err
	}
	paths := document.Playlists[favoritesPlaylistName]
	return append([]string(nil), paths...), nil
}

func (store *favoritesStore) add(path string) error {
	store.mu.Lock()
	defer store.mu.Unlock()
	document, previous, err := store.loadLocked()
	if err != nil {
		return err
	}
	paths := document.Playlists[favoritesPlaylistName]
	for _, existing := range paths {
		if existing == path {
			return nil
		}
	}
	document.Playlists[favoritesPlaylistName] = append(paths, path)
	return store.writeLocked(document, previous)
}

func (store *favoritesStore) remove(path string) error {
	store.mu.Lock()
	defer store.mu.Unlock()
	document, previous, err := store.loadLocked()
	if err != nil {
		return err
	}
	paths := document.Playlists[favoritesPlaylistName]
	filtered := make([]string, 0, len(paths))
	for _, existing := range paths {
		if existing != path {
			filtered = append(filtered, existing)
		}
	}
	if len(filtered) == len(paths) {
		return nil
	}
	document.Playlists[favoritesPlaylistName] = filtered
	return store.writeLocked(document, previous)
}

func (store *favoritesStore) document() (favoritesDocument, error) {
	store.mu.Lock()
	defer store.mu.Unlock()
	document, _, err := store.loadLocked()
	if err != nil {
		return favoritesDocument{}, err
	}
	copyDocument := emptyFavoritesDocument()
	copyDocument.Playlists = make(map[string][]string, len(document.Playlists))
	for name, paths := range document.Playlists {
		copyDocument.Playlists[name] = append([]string(nil), paths...)
	}
	return copyDocument, nil
}

func (store *favoritesStore) createPlaylist(name string) error {
	if !validPlaylistName(name) || name == favoritesPlaylistName {
		return errReservedPlaylist
	}
	store.mu.Lock()
	defer store.mu.Unlock()
	document, previous, err := store.loadLocked()
	if err != nil {
		return err
	}
	if _, exists := document.Playlists[name]; exists {
		return errPlaylistExists
	}
	document.Playlists[name] = []string{}
	return store.writeLocked(document, previous)
}

func (store *favoritesStore) renamePlaylist(oldName, newName string) error {
	if oldName == favoritesPlaylistName || newName == favoritesPlaylistName {
		return errReservedPlaylist
	}
	if !validPlaylistName(oldName) || !validPlaylistName(newName) {
		return errors.New("invalid playlist name")
	}
	store.mu.Lock()
	defer store.mu.Unlock()
	document, previous, err := store.loadLocked()
	if err != nil {
		return err
	}
	paths, exists := document.Playlists[oldName]
	if !exists {
		return errPlaylistMissing
	}
	if _, exists := document.Playlists[newName]; exists {
		return errPlaylistExists
	}
	delete(document.Playlists, oldName)
	document.Playlists[newName] = paths
	return store.writeLocked(document, previous)
}

func (store *favoritesStore) deletePlaylist(name string) error {
	if name == favoritesPlaylistName {
		return errReservedPlaylist
	}
	if !validPlaylistName(name) {
		return errors.New("invalid playlist name")
	}
	store.mu.Lock()
	defer store.mu.Unlock()
	document, previous, err := store.loadLocked()
	if err != nil {
		return err
	}
	if _, exists := document.Playlists[name]; !exists {
		return errPlaylistMissing
	}
	delete(document.Playlists, name)
	return store.writeLocked(document, previous)
}

func (store *favoritesStore) addTrack(name, path string) error {
	if !validPlaylistName(name) {
		return errors.New("invalid playlist name")
	}
	store.mu.Lock()
	defer store.mu.Unlock()
	document, previous, err := store.loadLocked()
	if err != nil {
		return err
	}
	paths, exists := document.Playlists[name]
	if !exists {
		return errPlaylistMissing
	}
	for _, existing := range paths {
		if existing == path {
			return nil
		}
	}
	document.Playlists[name] = append(paths, path)
	return store.writeLocked(document, previous)
}

func (store *favoritesStore) removeTrack(name, path string) error {
	if !validPlaylistName(name) {
		return errors.New("invalid playlist name")
	}
	store.mu.Lock()
	defer store.mu.Unlock()
	document, previous, err := store.loadLocked()
	if err != nil {
		return err
	}
	paths, exists := document.Playlists[name]
	if !exists {
		return errPlaylistMissing
	}
	filtered := make([]string, 0, len(paths))
	for _, existing := range paths {
		if existing != path {
			filtered = append(filtered, existing)
		}
	}
	if len(filtered) == len(paths) {
		return nil
	}
	document.Playlists[name] = filtered
	return store.writeLocked(document, previous)
}

func (a *Adapter) HandleFavorites(w http.ResponseWriter, _ *http.Request) {
	paths, err := a.favorites.list()
	if err != nil {
		writeAPIError(w, http.StatusInternalServerError, "favorites_storage_unavailable")
		return
	}
	entries := make([]FavoriteEntry, 0, len(paths))
	for _, path := range paths {
		entries = append(entries, favoriteEntry(path, a.config.ApprovedRoot))
	}
	writeJSON(w, http.StatusOK, FavoritesResponse{
		Version: favoritesSchemaVersion, Playlist: favoritesPlaylistName,
		Entries: entries,
	})
}

func (a *Adapter) HandleAddFavorite(w http.ResponseWriter, r *http.Request) {
	input, err := decodeStartRequest(r)
	if err != nil {
		writeAPIError(w, http.StatusBadRequest, "invalid_request")
		return
	}
	path, _, err := canonicalVGM(input.Path, a.config.ApprovedRoot)
	if err != nil {
		writeAPIError(w, http.StatusBadRequest, "invalid_vgm_path")
		return
	}
	if err := a.favorites.add(path); err != nil {
		writeAPIError(w, http.StatusInternalServerError, "favorites_write_failed")
		return
	}
	writeJSON(w, http.StatusOK, favoriteMutationResponse{Path: path, Favorite: true})
}

func (a *Adapter) HandleRemoveFavorite(w http.ResponseWriter, r *http.Request) {
	input, err := decodeStartRequest(r)
	if err != nil {
		writeAPIError(w, http.StatusBadRequest, "invalid_request")
		return
	}
	path, err := favoritePathIdentity(input.Path, a.config.ApprovedRoot)
	if err != nil {
		writeAPIError(w, http.StatusBadRequest, "invalid_vgm_path")
		return
	}
	if err := a.favorites.remove(path); err != nil {
		writeAPIError(w, http.StatusInternalServerError, "favorites_write_failed")
		return
	}
	writeJSON(w, http.StatusOK, favoriteMutationResponse{Path: path, Favorite: false})
}
