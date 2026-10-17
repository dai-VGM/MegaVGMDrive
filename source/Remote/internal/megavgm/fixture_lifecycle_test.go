package megavgm

import "os"

// After all test assertions, keep a late diagnostic append from recreating a
// file while testing.TempDir removes it. Production code and trace assertions
// remain unchanged. Synchronize with the production trace writer's mutex.
func retireFixture(a *Adapter) {
	a.CloseMonitor()
	a.playTraceMu.Lock()
	a.config.HandoffTracePath = os.DevNull
	a.playTraceMu.Unlock()
}
