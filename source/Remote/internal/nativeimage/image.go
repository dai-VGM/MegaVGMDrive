// Package nativeimage admits containers without executing CPU or sound writes.
// Serialization follows Engine E nsfe_fixture/native_image.py (comparison oracle).
package nativeimage

import (
	"bytes"
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"fmt"
	"unicode/utf8"
)

const Schema = "engine-e-native-image-v1"
const MaxContainer = 2 * 1024 * 1024

func Hash(b []byte) string { h := sha256.Sum256(b); return hex.EncodeToString(h[:]) }

type Track struct {
	Physical int     `json:"physical_zero_based"`
	Label    *string `json:"label"`
	Author   *string `json:"author"`
	Time     *int32  `json:"time_ms"`
	Fade     *int32  `json:"fade_ms"`
	TimeRaw  *int32  `json:"time_raw_ms"`
	FadeRaw  *int32  `json:"fade_raw_ms"`
}
type Metadata struct {
	Schema        string   `json:"schema"`
	Format        string   `json:"source_format"`
	SourceHash    string   `json:"source_sha256"`
	ProgramHash   string   `json:"program_sha256"`
	ExecutionHash string   `json:"execution_sha256"`
	SourcePath    string   `json:"source_path,omitempty"`
	SourceBytes   int      `json:"source_bytes"`
	PayloadBytes  int      `json:"payload_bytes"`
	ResidentBytes int      `json:"resident_bytes"`
	Load          uint16   `json:"load"`
	Init          uint16   `json:"INIT"`
	Play          uint16   `json:"PLAY"`
	Bank          [8]byte  `json:"BANK"`
	Rate          uint16   `json:"ntsc_period_us"`
	PALRate       uint16   `json:"pal_period_us"`
	DendyRate     uint16   `json:"dendy_period_us"`
	Songs         int      `json:"songs"`
	Start         int      `json:"starting_physical_zero_based"`
	Expansion     byte     `json:"expansion_audio_flag"`
	Chips         []string `json:"sound_chips"`
	Playlist      []int    `json:"playlist_zero_based"`
	Tracks        []Track  `json:"tracks"`
	Auth          []string `json:"auth"`
	Selected      int      `json:"selected_physical_one_based"`
	Policy        string   `json:"time_policy"`
}
type Image struct {
	Upload   []byte
	Metadata Metadata
}

func word(b []byte, p int) uint16 { return binary.LittleEndian.Uint16(b[p : p+2]) }
func strs(b []byte) ([]string, error) {
	if len(b) == 0 {
		return nil, nil
	}
	if b[len(b)-1] != 0 || !utf8.Valid(b) {
		return nil, fmt.Errorf("invalid terminated UTF-8 metadata")
	}
	s := bytes.Split(b[:len(b)-1], []byte{0})
	r := make([]string, len(s))
	for n, x := range s {
		r[n] = string(x)
	}
	return r, nil
}
func ints(b []byte) ([]int32, error) {
	if len(b)%4 != 0 {
		return nil, fmt.Errorf("partial int32 metadata")
	}
	r := make([]int32, len(b)/4)
	for n := range r {
		r[n] = int32(binary.LittleEndian.Uint32(b[n*4:]))
	}
	return r, nil
}
func pointer(s []string, n int) *string {
	if n >= len(s) {
		return nil
	}
	x := s[n]
	return &x
}
func signed(v []int32, n int) (*int32, *int32) {
	if n >= len(v) {
		return nil, nil
	}
	x := v[n]
	if x < 0 {
		return &x, nil
	}
	return &x, &x
}
func validate(b []byte) (Metadata, error) {
	fail := func(s string) (Metadata, error) { return Metadata{}, fmt.Errorf("native admission: %s", s) }
	if len(b) <= 128 || len(b) > 262272 || !bytes.Equal(b[:5], []byte("NESM\x1a")) || b[5] != 1 {
		return fail("NSF1 header/extent")
	}
	if !bytes.Equal(b[124:128], make([]byte, 4)) {
		return fail("NSF2/appended metadata")
	}
	if b[6] == 0 || b[7] == 0 || b[7] > b[6] || b[122] != 0 || b[123]&^byte(1) != 0 {
		return fail("subtune/region/expansion")
	}
	l, i, p := word(b, 8), word(b, 10), word(b, 12)
	if l < 0x8000 || i < 0x8000 || p < 0x8000 {
		return fail("CPU addresses")
	}
	banked := !bytes.Equal(b[112:120], make([]byte, 8))
	pad := int(l) - 0x8000
	if banked {
		pad = int(l) & 4095
	}
	extent := pad + len(b) - 128
	if extent > 262144 || (!banked && extent > 32768) {
		return fail("resident extent")
	}
	if banked {
		for _, v := range b[112:120] {
			if int(v) >= (extent+4095)/4096 {
				return fail("initial bank")
			}
		}
	}
	m := Metadata{Schema: Schema, ProgramHash: Hash(b[128:]), ExecutionHash: Hash(b), PayloadBytes: len(b) - 128, ResidentBytes: extent, Load: l, Init: i, Play: p, Bank: [8]byte{b[112], b[113], b[114], b[115], b[116], b[117], b[118], b[119]}, Rate: word(b, 110), PALRate: word(b, 120), Songs: int(b[6]), Start: int(b[7]) - 1, Expansion: b[123], Chips: []string{"NES APU"}, Policy: "METADATA_ONLY_NO_AUTOMATIC_FADE_OR_QUEUE_POLICY"}
	if m.Rate == 0 || m.PALRate == 0 {
		return fail("zero rate")
	}
	if m.Expansion == 1 {
		m.Chips = append(m.Chips, "VRC6")
	}
	return m, nil
}
func Load(source []byte) (Image, error) {
	if len(source) > MaxContainer {
		return Image{}, fmt.Errorf("container exceeds 2MiB")
	}
	if bytes.HasPrefix(source, []byte("NSFE")) {
		return nsfe(source)
	}
	if len(source) <= 128 {
		return Image{}, fmt.Errorf("short NSF")
	}
	b := append([]byte(nil), source...)
	if word(b, 110) == 0 {
		binary.LittleEndian.PutUint16(b[110:], 16639)
	}
	if word(b, 120) == 0 {
		binary.LittleEndian.PutUint16(b[120:], 19997)
	}
	m, e := validate(b)
	if e != nil {
		return Image{}, e
	}
	m.Format = "NSF1"
	m.SourceHash = Hash(source)
	m.SourceBytes = len(source)
	for n := 0; n < m.Songs; n++ {
		m.Playlist = append(m.Playlist, n)
		m.Tracks = append(m.Tracks, Track{Physical: n})
	}
	for _, p := range []int{14, 46, 78} {
		s := bytes.SplitN(b[p:p+32], []byte{0}, 2)[0]
		m.Auth = append(m.Auth, string(s))
	}
	return Image{b, m}, nil
}
func nsfe(source []byte) (Image, error) {
	parts := map[string][]byte{}
	ended := false
	mandatory := map[string]bool{"INFO": true, "DATA": true, "BANK": true, "RATE": true, "NEND": true}
	for pos := 4; pos < len(source); {
		if len(source)-pos < 8 {
			return Image{}, fmt.Errorf("truncated chunk")
		}
		size := uint64(binary.LittleEndian.Uint32(source[pos:]))
		kind := string(source[pos+4 : pos+8])
		if size > uint64(len(source)-pos-8) {
			return Image{}, fmt.Errorf("truncated payload")
		}
		if _, ok := parts[kind]; ok {
			return Image{}, fmt.Errorf("duplicate chunk %q", kind)
		}
		if kind == "NSF2" || (kind[0] >= 'A' && kind[0] <= 'Z' && !mandatory[kind]) {
			return Image{}, fmt.Errorf("unsupported mandatory %q", kind)
		}
		_, info := parts["INFO"]
		if kind == "DATA" && !info {
			return Image{}, fmt.Errorf("DATA before INFO")
		}
		if (kind == "time" || kind == "fade" || kind == "tlbl" || kind == "taut" || kind == "regn") && !info {
			return Image{}, fmt.Errorf("metadata before INFO")
		}
		parts[kind] = source[pos+8 : pos+8+int(size)]
		pos += 8 + int(size)
		if kind == "NEND" {
			ended = true
			break
		}
	}
	info, ok := parts["INFO"]
	data, hasData := parts["DATA"]
	if !ended || !ok || !hasData || len(info) < 9 {
		return Image{}, fmt.Errorf("INFO/DATA/NEND required")
	}
	if info[6]&0xfc != 0 {
		return Image{}, fmt.Errorf("reserved INFO region flags")
	}
	b := make([]byte, 128)
	copy(b, []byte("NESM\x1a"))
	b[5] = 1
	b[6] = info[8]
	b[7] = 1
	if len(info) > 9 {
		if info[9] == 255 {
			return Image{}, fmt.Errorf("invalid start")
		}
		b[7] = info[9] + 1
	}
	copy(b[8:14], info[:6])
	copy(b[122:124], info[6:8])
	if reg, ok := parts["regn"]; ok {
		if (len(reg) != 1 && len(reg) != 2) || reg[0] != 1 || (len(reg) == 2 && reg[1] != 0) {
			return Image{}, fmt.Errorf("unsupported regn")
		}
		b[122] = 0
	}
	if bank, ok := parts["BANK"]; ok {
		copy(b[112:120], bank)
		if bytes.Equal(b[112:120], make([]byte, 8)) {
			return Image{}, fmt.Errorf("forced allzero BANK not NSF1 representable")
		}
	}
	ntsc, pal, dendy := uint16(16639), uint16(19997), uint16(19997)
	if rate, ok := parts["RATE"]; ok {
		if len(rate) != 2 && len(rate) != 4 && len(rate) != 6 {
			return Image{}, fmt.Errorf("unsupported RATE")
		}
		ntsc = word(rate, 0)
		if len(rate) >= 4 {
			pal = word(rate, 2)
		}
		dendy = pal
		if len(rate) == 6 {
			dendy = word(rate, 4)
		}
	}
	binary.LittleEndian.PutUint16(b[110:], ntsc)
	binary.LittleEndian.PutUint16(b[120:], pal)
	auth, e := strs(parts["auth"])
	if e != nil {
		return Image{}, e
	}
	for n, s := range auth {
		if n >= 3 {
			break
		}
		out := []byte{}
		for _, r := range s {
			if r > 127 {
				out = append(out, '?')
			} else {
				out = append(out, byte(r))
			}
		}
		if len(out) > 31 {
			out = out[:31]
		}
		copy(b[14+32*n:46+32*n], out)
	}
	b = append(b, data...)
	m, e := validate(b)
	if e != nil {
		return Image{}, e
	}
	m.Format = "NSFe"
	m.SourceHash = Hash(source)
	m.SourceBytes = len(source)
	m.Auth = auth
	m.DendyRate = dendy
	if plst, ok := parts["plst"]; ok {
		if len(plst) == 0 {
			return Image{}, fmt.Errorf("empty plst")
		}
		for _, n := range plst {
			if int(n) >= m.Songs {
				return Image{}, fmt.Errorf("plst range")
			}
			m.Playlist = append(m.Playlist, int(n))
		}
	} else {
		for n := 0; n < m.Songs; n++ {
			m.Playlist = append(m.Playlist, n)
		}
	}
	labels, e := strs(parts["tlbl"])
	if e != nil {
		return Image{}, e
	}
	authors, e := strs(parts["taut"])
	if e != nil {
		return Image{}, e
	}
	times, e := ints(parts["time"])
	if e != nil {
		return Image{}, e
	}
	fades, e := ints(parts["fade"])
	if e != nil {
		return Image{}, e
	}
	for n := 0; n < m.Songs; n++ {
		tr, t := signed(times, n)
		fr, f := signed(fades, n)
		m.Tracks = append(m.Tracks, Track{n, pointer(labels, n), pointer(authors, n), t, f, tr, fr})
	}
	return Image{b, m}, nil
}
func (x Image) Select(physical int) (Image, error) {
	if physical == 0 {
		physical = x.Metadata.Start + 1
	}
	if physical < 1 || physical > x.Metadata.Songs {
		return Image{}, fmt.Errorf("track out of range")
	}
	b := append([]byte(nil), x.Upload...)
	b[7] = byte(physical)
	x.Upload = b
	x.Metadata.Selected = physical
	x.Metadata.ExecutionHash = Hash(b)
	return x, nil
}
