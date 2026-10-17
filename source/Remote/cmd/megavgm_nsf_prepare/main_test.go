package main

import (
	"github.com/dai-VGM/megavgm-remote/internal/nativeimage"
	"strings"
	"testing"
)

func TestTimingReceipt(t *testing.T) {
	zero, time, fade := int32(0), int32(89000), int32(1850)
	m := nativeimage.Metadata{Format: "NSFe", Selected: 1, SourceHash: strings.Repeat("a", 64), ExecutionHash: strings.Repeat("b", 64), Tracks: []nativeimage.Track{{Time: &time, Fade: &fade}, {Time: &zero, Fade: &zero}}}
	if !strings.HasSuffix(timingReceipt(m), " 1 89000 1850\n") {
		t.Fatal(timingReceipt(m))
	}
	m.Selected = 2
	if !strings.HasSuffix(timingReceipt(m), " 2 0 0\n") {
		t.Fatal(timingReceipt(m))
	}
	m.Tracks[1].Time = nil
	m.Tracks[1].Fade = nil
	if !strings.HasSuffix(timingReceipt(m), " 2 - -\n") {
		t.Fatal(timingReceipt(m))
	}
	m.Format = "NSF1"
	m.Selected = 1
	if !strings.HasSuffix(timingReceipt(m), " 1 - -\n") {
		t.Fatal(timingReceipt(m))
	}
}
