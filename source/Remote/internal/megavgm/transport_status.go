package megavgm

import (
	"errors"
	"regexp"
	"strconv"
)

// Optional read-only Supervisor receipt. Decimal strings preserve uint64
// generation/domain exactly through JavaScript; no second operation owner.
type TransportStatus struct {
	Epoch           string `json:"epoch"`
	Generation      string `json:"switchGeneration"`
	State           string `json:"switchState"`
	CurrentProfile  string `json:"currentProfile"`
	RequiredProfile string `json:"requiredProfile"`
	Domain          string `json:"domain"`
	Baseline        uint32 `json:"baseline"`
	Changed         bool   `json:"profileChanged"`
	Path            string `json:"path"`
}

var transportKeys = []string{"switch_epoch", "switch_generation", "switch_state", "current_profile", "required_profile", "switch_domain", "switch_baseline", "switch_changed", "switch_path"}
var transportEpoch = regexp.MustCompile(`^megavgm-phase2a\.[A-Za-z0-9]+$`)
var transportStates = map[string]bool{"IDLE": true, "PARKED": true, "FADING": true, "SWITCHING": true, "READY": true, "PLAYING": true, "ENDED": true, "STOPPED": true, "FAILED": true}

func parseTransportStatus(v map[string]string) (*TransportStatus, error) {
	present := 0
	for _, key := range transportKeys {
		if _, ok := v[key]; ok {
			present++
		}
	}
	if present == 0 {
		return nil, nil
	}
	invalid := errors.New("invalid supervisor transport status")
	if present != len(transportKeys) || !transportEpoch.MatchString(v["switch_epoch"]) || len(v["switch_epoch"]) > 128 || !transportStates[v["switch_state"]] {
		return nil, invalid
	}
	profile := func(p string) bool {
		return p == "PROFILE_A" || p == "PROFILE_B" || p == "PROFILE_C" || p == "PROFILE_D" || p == "PROFILE_E" || p == "PROFILE_F"
	}
	if !profile(v["current_profile"]) || (!profile(v["required_profile"]) && v["required_profile"] != "UNKNOWN") {
		return nil, invalid
	}
	for _, key := range []string{"switch_generation", "switch_domain", "switch_baseline"} {
		bits := 64
		if key == "switch_baseline" {
			bits = 32
		}
		n, err := parseUnsigned(v[key], bits)
		if err != nil || strconv.FormatUint(n, 10) != v[key] {
			return nil, invalid
		}
	}
	if v["switch_changed"] != "0" && v["switch_changed"] != "1" {
		return nil, invalid
	}
	if len(v["switch_path"]) > MaximumPathLength || hasControl(v["switch_path"]) {
		return nil, invalid
	}
	n, _ := parseUnsigned(v["switch_baseline"], 32)
	return &TransportStatus{v["switch_epoch"], v["switch_generation"], v["switch_state"], v["current_profile"], v["required_profile"], v["switch_domain"], uint32(n), v["switch_changed"] == "1", v["switch_path"]}, nil
}
