package megavgm

import "strings"

const preparedSIDExtension = ".mvgmsid"

func supportedTrackName(name string) bool {
	return strings.HasSuffix(name, ".vgm") || strings.HasSuffix(name, preparedSIDExtension)
}

func trackTitle(name string) string {
	if strings.HasSuffix(name, preparedSIDExtension) {
		return strings.TrimSuffix(name, preparedSIDExtension)
	}
	return strings.TrimSuffix(name, ".vgm")
}
