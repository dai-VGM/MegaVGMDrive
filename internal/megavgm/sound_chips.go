package megavgm

import "strings"

// Optional display evidence from the same atomic controller snapshot as
// path/session. Never classify a file or infer chips from an RBF/profile here.
// Unrecognized display metadata is omitted, without changing transport validity.
func parseSoundChips(value string) []string {
	if value == "" || len(value) > 96 {
		return nil
	}
	known := map[string]bool{"PSG": true, "YM2612": true, "YM2151": true,
		"YM2203": true, "SegaPCM": true, "YM2610": true, "YM2610B": true,
		"SID 6581": true, "SID 8580": true, "C140": true}
	chips := strings.Split(value, ",")
	seen := make(map[string]bool)
	for _, chip := range chips {
		if !known[chip] || seen[chip] {
			return nil
		}
		seen[chip] = true
	}
	return chips
}
