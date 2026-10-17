package nativeimage

import (
	"bytes"
	"encoding/binary"
	"encoding/json"
	"testing"
)

func fixture() []byte {
	b := make([]byte, 129)
	copy(b, []byte("NESM\x1a"))
	b[5] = 1
	b[6] = 28
	b[7] = 1
	b[9] = 0x80
	b[11] = 0x80
	b[13] = 0x80
	b[123] = 1
	b[128] = 0x60
	return b
}
func chunk(tag string, b []byte) []byte {
	out := make([]byte, 8)
	binary.LittleEndian.PutUint32(out, uint32(len(b)))
	copy(out[4:], tag)
	return append(out, b...)
}
func container(extra ...[]byte) []byte {
	b := []byte("NSFE")
	b = append(b, chunk("INFO", []byte{0, 0x80, 0, 0x80, 0, 0x80, 0, 1, 28, 0})...)
	for _, x := range extra {
		b = append(b, x...)
	}
	b = append(b, chunk("DATA", []byte{0x60})...)
	return append(b, chunk("NEND", nil)...)
}
func TestEquivalenceAndMetadata(t *testing.T) {
	a, e := Load(fixture())
	if e != nil {
		t.Fatal(e)
	}
	b, e := Load(container())
	if e != nil || !bytes.Equal(a.Upload, b.Upload) {
		t.Fatal(e, "execution mismatch")
	}
	c, e := Load(container(chunk("plst", []byte{21, 0, 21}), chunk("tlbl", []byte("Beginning\x00Second\x00")), chunk("time", []byte{0xff, 0xff, 0xff, 0xff, 0, 0, 0, 0}), chunk("fade", []byte{0, 0, 0, 0}), chunk("RATE", []byte{0xff, 0x40, 0x1d, 0x4e, 0x1d, 0x4e})))
	if e != nil {
		t.Fatal(e)
	}
	if c.Metadata.Playlist[0] != 21 || c.Metadata.Tracks[0].Time != nil || *c.Metadata.Tracks[0].TimeRaw != -1 || *c.Metadata.Tracks[1].Time != 0 || *c.Metadata.Tracks[0].Label != "Beginning" {
		t.Fatal("metadata mapping")
	}
	selected, e := c.Select(c.Metadata.Playlist[0] + 1)
	if e != nil || selected.Upload[7] != 22 || c.Upload[7] != 1 {
		t.Fatal("selection mutates image")
	}
	j, _ := json.Marshal(c.Metadata)
	if !bytes.Contains(j, []byte(`"BANK":[0,0,0,0,0,0,0,0]`)) {
		t.Fatal("BANK JSON")
	}
}
func TestAdmissionNegatives(t *testing.T) {
	for _, bad := range [][]byte{container(chunk("NSF2", []byte{0})), container(chunk("XXXX", nil)), container(chunk("BANK", make([]byte, 8))), container(chunk("RATE", []byte{1})), container(chunk("plst", []byte{28})), container(chunk("tlbl", []byte{0xff, 0})), container(chunk("time", []byte{1})), container(chunk("INFO", nil)), container()[:10], make([]byte, MaxContainer+1)} {
		if _, e := Load(bad); e == nil {
			t.Fatalf("accepted malformed %x", bad[:min(len(bad), 16)])
		}
	}
	for _, pos := range []int{5, 6, 7, 9, 11, 13, 122, 123, 124} {
		bad := fixture()
		if pos == 5 {
			bad[pos] = 2
		} else if pos == 122 || pos == 123 || pos == 124 {
			bad[pos] = 2
		} else {
			bad[pos] = 0
		}
		if _, e := Load(bad); e == nil {
			t.Fatalf("accepted header mutation %d", pos)
		}
	}
}
func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}
func TestOptionalAndExtensions(t *testing.T) {
	b := container(chunk("xxxx", []byte{1, 2}), chunk("RATE", []byte{0xff, 0x40}))
	b = append(b, 1, 2, 3)
	if _, e := Load(b); e != nil {
		t.Fatal(e)
	}
	for n := 1; n <= 28; n++ {
		x, e := Load(container())
		if e != nil {
			t.Fatal(e)
		}
		y, e := x.Select(n)
		if e != nil || y.Upload[7] != byte(n) {
			t.Fatal("subtune")
		}
		if !bytes.Equal(x.Upload[128:], y.Upload[128:]) || !bytes.Equal(x.Upload[8:128], y.Upload[8:128]) {
			t.Fatal("program/config changed")
		}
	}
}
