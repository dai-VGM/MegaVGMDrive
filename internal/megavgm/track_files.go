package megavgm

import "strings"

const preparedSIDExtension = ".mvgmsid"
const rawSIDExtension = ".sid"

func supportedTrackName(name string) bool {
	return strings.HasSuffix(name, ".vgm") || strings.HasSuffix(name, preparedSIDExtension) ||
		strings.HasSuffix(name, rawSIDExtension)
}

func trackTitle(name string) string {
	if strings.HasSuffix(name, preparedSIDExtension) {
		return strings.TrimSuffix(name, preparedSIDExtension)
	}
	if strings.HasSuffix(name, rawSIDExtension) {
		return strings.TrimSuffix(name, rawSIDExtension)
	}
	return strings.TrimSuffix(name, ".vgm")
}
