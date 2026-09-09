package megavgm

import (
	"encoding/json"
	"strings"
	"testing"
)

const transportFixture = "switch_epoch=megavgm-phase2a.abc123\nswitch_generation=18446744073709551615\nswitch_state=SWITCHING\ncurrent_profile=PROFILE_A\nrequired_profile=PROFILE_B\nswitch_domain=2\nswitch_baseline=0\nswitch_changed=1\nswitch_path=/media/fat/MegaVGMDrive/Night Striker/01 Coin.vgm\n"

func TestTransportStatus(t *testing.T) {
	base := supervisorStatus("MEGAVGM", "MODIFIED", "RUNNING", "Favorites")
	old, e := ParseSupervisorStatus(strings.NewReader(base))
	if e != nil || old.Transport != nil {
		t.Fatal(old, e)
	}
	for state := range transportStates {
		s, e := ParseSupervisorStatus(strings.NewReader(base + strings.Replace(transportFixture, "=SWITCHING\n", "="+state+"\n", 1)))
		if e != nil || s.Transport.State != state || s.Transport.Generation != "18446744073709551615" {
			t.Fatal(s, e)
		}
		b, _ := json.Marshal(Status{Transport: s.Transport})
		if !strings.Contains(string(b), `"switchGeneration":"18446744073709551615"`) {
			t.Fatal(string(b))
		}
	}
	for _, bad := range []string{
		strings.Replace(transportFixture, "SWITCHING", "WAIT_MAGIC", 1),
		strings.Replace(transportFixture, "switch_changed=1\n", "", 1),
		strings.Replace(transportFixture, "PROFILE_A", "YM2612", 1),
		strings.Replace(transportFixture, "switch_baseline=0", "switch_baseline=4294967296", 1),
		strings.Replace(transportFixture, "switch_domain=2", "switch_domain=+2", 1),
		transportFixture + "switch_state=READY\n",
	} {
		if _, e := ParseSupervisorStatus(strings.NewReader(base + bad)); e == nil {
			t.Fatal("accepted invalid transport", bad)
		}
	}
}
