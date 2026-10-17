package megavgm

import (
	"strings"
	"testing"
)

func TestNativeDeadlineInterimTimingContract(t *testing.T) {
	for _, total := range []string{"100", "101", "90850", "4294967294"} {
		body := validStatus + "elapsed_ms=0\nplanned_duration=FINITE\nplanned_duration_ms=" + total + "\nduration_source=NATIVE_METADATA_END_TARGET_100MS_FADE_APPROXIMATION\n"
		got, err := ParseStatus(strings.NewReader(body))
		if err != nil || got.PlannedDurationMS == nil {
			t.Fatal(total, err)
		}
	}
	// A zero timer target is valid; its display duration must reflect the 100ms
	// transport minimum, because the unchanged Remote finite-duration ABI is >0.
	if _, err := ParseStatus(strings.NewReader(validStatus + "planned_duration=FINITE\nplanned_duration_ms=0\n")); err == nil {
		t.Fatal("zero finite total incorrectly accepted")
	}
}
