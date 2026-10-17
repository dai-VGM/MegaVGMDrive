package megavgm

import "testing"

func TestNativeTrackNamesAndChips(t *testing.T) {
	for _, suffix := range []string{".vgm", ".mvgmsid", ".sid", ".nsf", ".nsfe"} {
		if !supportedTrackName("Track"+suffix) || trackTitle("Track"+suffix) != "Track" {
			t.Fatal(suffix)
		}
	}
	for _, s := range []string{"Track.NSFE", "Track.nsf.tmp", "Track.nsfe.json"} {
		if supportedTrackName(s) {
			t.Fatal(s)
		}
	}
	c := parseSoundChips("NES APU,VRC6")
	if len(c) != 2 {
		t.Fatal(c)
	}
}
