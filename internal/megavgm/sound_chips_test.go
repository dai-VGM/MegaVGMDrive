package megavgm

import (
	"net/http"
	"reflect"
	"strings"
	"testing"
)

func TestSoundChipMetadata(t *testing.T) {
	for _, value := range []string{"PSG,YM2612", "YM2151,SegaPCM", "YM2203", "YM2610B", "YM2610", "PSG"} {
		s, err := ParseStatus(strings.NewReader(validStatus + "sound_chips=" + value + "\n"))
		if err != nil || !reflect.DeepEqual(s.SoundChips, strings.Split(value, ",")) || s.Session != 27 || s.Index != 4 || s.Count != 10 {
			t.Fatalf("%s: %+v %v", value, s, err)
		}
	}
	for _, value := range []string{"", "PROFILE_A", "YM2612,YM2612", "PSG,,YM2612", "unknown"} {
		s, err := ParseStatus(strings.NewReader(validStatus + "sound_chips=" + value + "\n"))
		if err != nil || len(s.SoundChips) != 0 || s.State != "PLAYING" {
			t.Fatalf("optional display metadata affected playback status: %+v %v", s, err)
		}
	}
	s, err := ParseStatus(strings.NewReader(validStatus))
	if err != nil || len(s.SoundChips) != 0 {
		t.Fatal("legacy status changed")
	}
	if _, err = ParseStatus(strings.NewReader(validStatus + "sound_chips=YM2612\nsound_chips=YM2203\n")); err == nil {
		t.Fatal("duplicate known status key accepted")
	}
}

func TestStatusChipPassthroughNotProfileInference(t *testing.T) {
	a := newTestAdapter(t, t.TempDir(), nil)
	writeFile(t, a.config.SupervisorStatusPath, supervisorStatus("MEGAVGM", "MODIFIED", "RUNNING", a.config.DefaultPlaylistPath)+transportFixture, 0644)
	makeFIFO(t, a.config.CommandPath)
	for _, chips := range []string{"PSG,YM2612", "YM2203", "YM2151,SegaPCM", "YM2610B", ""} {
		content := validStatus
		if chips != "" {
			content += "sound_chips=" + chips + "\n"
		}
		writeFile(t, a.config.StatusPath, content, 0644)
		r := request(t, http.MethodGet, nil, a.HandleStatus)
		if r.Code != 200 {
			t.Fatal(r.Code, r.Body.String())
		}
		var s Status
		decodeResponse(t, r, &s)
		if strings.Join(s.SoundChips, ",") != chips || s.Transport.CurrentProfile != "PROFILE_A" || s.Session != 27 || s.Index != 4 {
			t.Fatalf("status/profile mixed: %+v", s)
		}
	}
	writeSupervisor(t, a, "STOCK", "STOCK", "STOPPED", a.config.DefaultPlaylistPath)
	r := request(t, http.MethodGet, nil, a.HandleStatus)
	if strings.Contains(r.Body.String(), "soundChips") {
		t.Fatal("stale metadata after exit")
	}
}
