package megavgm

import (
	"net/http"
	"os"
	"strings"
	"testing"
)

func TestRecoverableTrackLoadError(t *testing.T) {
	base := strings.Replace(validStatus, "state=PLAYING", "state=STOPPED", 1)
	for _, code := range []string{"resource_capacity_exceeded", "invalid_track", "unsupported_track", "track_prepare_failed"} {
		parsed, err := ParseStatus(strings.NewReader(base + "load_error=" + code + "\nload_error_detail=fixture refusal\n"))
		if err != nil || parsed.LoadError != code || parsed.LoadErrorDetail != "fixture refusal" {
			t.Fatalf("%s: %+v %v", code, parsed, err)
		}
	}
	for _, suffix := range []string{
		"load_error=arbitrary\nload_error_detail=bad\n",
		"load_error=invalid_track\n",
		"load_error_detail=bad\n",
		"load_error=invalid_track\nload_error_detail=" + strings.Repeat("x", 513) + "\n",
	} {
		if _, err := ParseStatus(strings.NewReader(base + suffix)); err == nil {
			t.Fatalf("accepted invalid error: %q", suffix)
		}
	}
	if _, err := ParseStatus(strings.NewReader(validStatus + "load_error=invalid_track\nload_error_detail=bad\n")); err == nil {
		t.Fatal("PLAYING carried rejected-target error")
	}
}

func TestRejectedTrackStatusStaysActiveAndClears(t *testing.T) {
	a := newTestAdapter(t, t.TempDir(), nil)
	writeSupervisor(t, a, "MEGAVGM", "MODIFIED", "RUNNING", "/music")
	makeFIFO(t, a.config.CommandPath)
	base := strings.Replace(validStatus, "state=PLAYING", "state=STOPPED", 1)
	if err := os.WriteFile(a.config.StatusPath, []byte(base+"load_error=unsupported_track\nload_error_detail=declaration-only ROM block\n"), 0600); err != nil {
		t.Fatal(err)
	}
	var s Status
	response := request(t, http.MethodGet, nil, a.HandleStatus)
	decodeResponse(t, response, &s)
	if response.Code != 200 || !s.ControllerRunning || s.Mode != "MEGAVGM" || s.State != "STOPPED" || s.Detail != "TRACK_LOAD_REJECTED: unsupported_track: declaration-only ROM block" {
		t.Fatalf("rejection lost active lifecycle: %+v", s)
	}
	if err := os.WriteFile(a.config.StatusPath, []byte(validStatus), 0600); err != nil {
		t.Fatal(err)
	}
	response = request(t, http.MethodGet, nil, a.HandleStatus)
	s = Status{}
	decodeResponse(t, response, &s)
	if s.Detail != "test status" || s.State != "PLAYING" {
		t.Fatalf("old target error leaked: %+v", s)
	}
	// Stock must never surface an old Controller's refusal.
	writeSupervisor(t, a, "STOCK", "STOCK", "STOPPED", "")
	response = request(t, http.MethodGet, nil, a.HandleStatus)
	s = Status{}
	decodeResponse(t, response, &s)
	if s.ControllerRunning || s.Detail != "test status" {
		t.Fatalf("stale error leaked to Stock: %+v", s)
	}
}
