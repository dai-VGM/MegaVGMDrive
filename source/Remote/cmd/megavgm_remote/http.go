package main

import (
	"embed"
	"io/fs"
	"net/http"
	"path"
	"strings"

	"github.com/dai-VGM/megavgm-remote/internal/megavgm"
	"github.com/gorilla/mux"
)

//go:embed web/build
var client embed.FS

func handler(a *megavgm.Adapter) http.Handler {
	r := mux.NewRouter()
	sub := r.PathPrefix("/api").Subrouter()
	sub.HandleFunc("/megavgm/status", a.HandleStatus).Methods("GET")
	sub.HandleFunc("/megavgm/browse", a.HandleBrowse).Methods("GET")
	sub.HandleFunc("/megavgm/favorites", a.HandleFavorites).Methods("GET")
	sub.HandleFunc("/megavgm/favorites", a.HandleAddFavorite).Methods("POST")
	sub.HandleFunc("/megavgm/favorites", a.HandleRemoveFavorite).Methods("DELETE")
	sub.HandleFunc("/megavgm/playlists", a.HandlePlaylists).Methods("GET")
	sub.HandleFunc("/megavgm/playlists", a.HandleCreatePlaylist).Methods("POST")
	sub.HandleFunc("/megavgm/playlists/{name}", a.HandlePlaylist).Methods("GET")
	sub.HandleFunc("/megavgm/playlists/{name}", a.HandleRenamePlaylist).Methods("PATCH")
	sub.HandleFunc("/megavgm/playlists/{name}", a.HandleDeletePlaylist).Methods("DELETE")
	sub.HandleFunc("/megavgm/playlists/{name}/tracks", a.HandleAddPlaylistTrack).Methods("POST")
	sub.HandleFunc("/megavgm/playlists/{name}/tracks", a.HandleRemovePlaylistTrack).Methods("DELETE")
	sub.HandleFunc("/megavgm/playlists/{name}/play", a.HandlePlayPlaylist).Methods("POST")
	sub.HandleFunc("/megavgm/play", a.HandlePlay).Methods("POST")
	sub.HandleFunc("/megavgm/start", a.HandleStart).Methods("POST")
	sub.HandleFunc("/megavgm/exit", a.HandleExit).Methods("POST")
	sub.HandleFunc("/megavgm/next", a.HandleNext).Methods("POST")
	sub.HandleFunc("/megavgm/prev", a.HandlePrevious).Methods("POST")
	sub.HandleFunc("/megavgm/stop", a.HandleStop).Methods("POST")
	sub.HandleFunc("/megavgm/repeat", a.HandleRepeat).Methods("POST")
	sub.HandleFunc("/megavgm/shuffle", a.HandleShuffle).Methods("POST")
	build, err := fs.Sub(client, "web/build")
	if err != nil {
		panic(err)
	}
	files := http.FileServer(http.FS(build))
	r.PathPrefix("/").HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		p := path.Clean(req.URL.Path)
		if p == "/api" || strings.HasPrefix(p, "/api/") {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusNotFound)
			_, _ = w.Write([]byte("{\"error\":\"api_not_found\"}\n"))
			return
		}
		if p == "/" {
			http.Redirect(w, req, "/megavgm", http.StatusTemporaryRedirect)
			return
		}
		if p == "/megavgm" || strings.HasPrefix(p, "/megavgm/") {
			req = req.Clone(req.Context())
			req.URL.Path = "/megavgm.html"
		}
		files.ServeHTTP(w, req)
	})
	return r
}
