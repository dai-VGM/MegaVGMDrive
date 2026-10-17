package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"github.com/dai-VGM/megavgm-remote/internal/nativeimage"
	"io"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

func run() error {
	input := flag.String("input", "", "immutable original NSF/NSFe")
	cache := flag.String("cache-root", "/media/fat/MegaVGMPlayer/cache/native", "owned preparation cache")
	track := flag.Int("track", 0, "one-based physical track; zero=INFO start")
	plst := flag.Int("playlist-index", -1, "zero-based plst index")
	approved := flag.String("approved-root", "/media/fat/MegaVGMDrive", "approved original source root")
	receipt := flag.Bool("timing-receipt", false, "emit owned preparation timing receipt after path")
	inspect := flag.Bool("inspect", false, "read-only metadata JSON; never publish")
	flag.Parse()
	if *plst < -1 {
		return fmt.Errorf("invalid playlist-index")
	}
	if *input == "" {
		return fmt.Errorf("input required")
	}
	root, e := filepath.EvalSymlinks(*approved)
	if e != nil {
		return e
	}
	path, e := filepath.EvalSymlinks(*input)
	if e != nil {
		return e
	}
	root, e = filepath.Abs(root)
	if e != nil {
		return e
	}
	path, e = filepath.Abs(path)
	if e != nil {
		return e
	}
	if !strings.HasPrefix(path, root+string(os.PathSeparator)) {
		return fmt.Errorf("source outside approved root")
	}
	st, e := os.Stat(path)
	if e != nil || !st.Mode().IsRegular() {
		return fmt.Errorf("source not regular")
	}
	f, e := os.Open(path)
	if e != nil {
		return e
	}
	source, e := io.ReadAll(io.LimitReader(f, nativeimage.MaxContainer+1))
	f.Close()
	if e != nil {
		return e
	}
	image, e := nativeimage.Load(source)
	if e != nil {
		return e
	}
	if *plst >= 0 {
		if *track != 0 || *plst >= len(image.Metadata.Playlist) {
			return fmt.Errorf("invalid selection")
		}
		*track = image.Metadata.Playlist[*plst] + 1
	}
	image, e = image.Select(*track)
	if e != nil {
		return e
	}
	image.Metadata.SourcePath = path
	if *inspect {
		return json.NewEncoder(os.Stdout).Encode(image.Metadata)
	}
	// New immutable entries; existing contents must match, never overwrite them.
	if e = os.MkdirAll(*cache, 0755); e != nil {
		return e
	}
	c, e := filepath.EvalSymlinks(*cache)
	if e != nil {
		return e
	}
	c, e = filepath.Abs(c)
	if e != nil {
		return e
	}
	key := nativeimage.Hash([]byte(nativeimage.Schema + "\x00" + path + "\x00" + nativeimage.Hash(source) + "\x00" + strconv.Itoa(image.Metadata.Selected)))
	dest := filepath.Join(c, key+".nsf")
	meta := dest + ".json"
	j, e := json.Marshal(image.Metadata)
	if e != nil {
		return e
	}
	j = append(j, '\n')
	// Source must still identify the same bytes before exposing the image.
	f, e = os.Open(path)
	if e != nil {
		return e
	}
	again, e := io.ReadAll(io.LimitReader(f, nativeimage.MaxContainer+1))
	f.Close()
	if e != nil || nativeimage.Hash(again) != nativeimage.Hash(source) {
		return fmt.Errorf("original changed during admission")
	}
	for _, item := range []struct {
		p string
		b []byte
	}{{meta, j}, {dest, image.Upload}} {
		if s, e := os.Lstat(item.p); e == nil {
			if !s.Mode().IsRegular() {
				return fmt.Errorf("cache target not regular")
			}
			b, e := os.ReadFile(item.p)
			if e != nil || nativeimage.Hash(b) != nativeimage.Hash(item.b) {
				return fmt.Errorf("cache content mismatch")
			}
			continue
		} else if !os.IsNotExist(e) {
			return e
		}
		tmp := item.p + ".tmp." + strconv.Itoa(os.Getpid())
		f, e := os.OpenFile(tmp, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0644)
		if e != nil {
			return e
		}
		defer os.Remove(tmp)
		if _, e = f.Write(item.b); e == nil {
			e = f.Sync()
		}
		if closeErr := f.Close(); e == nil {
			e = closeErr
		}
		if e != nil {
			return e
		}
		if e = os.Link(tmp, item.p); e != nil {
			return e
		} // publication is no-clobber, binary last
	}
	fmt.Println(dest)
	if *receipt {
		fmt.Print(timingReceipt(image.Metadata))
	}
	return nil
}

// Unknown/negative metadata uses player default; zero remains an explicit value.
func timingReceipt(m nativeimage.Metadata) string {
	t, f := "-", "-"
	if m.Format == "NSFe" && m.Selected > 0 && m.Selected <= len(m.Tracks) {
		tr := m.Tracks[m.Selected-1]
		if tr.Time != nil {
			t = strconv.FormatInt(int64(*tr.Time), 10)
		}
		if tr.Fade != nil {
			f = strconv.FormatInt(int64(*tr.Fade), 10)
		}
	}
	return fmt.Sprintf("NATIVE_TIMING_V1 %s %s %s %d %s %s\n", m.Format, m.SourceHash, m.ExecutionHash, m.Selected, t, f)
}
func main() {
	if e := run(); e != nil {
		fmt.Fprintln(os.Stderr, e)
		os.Exit(1)
	}
}
