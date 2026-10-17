package megavgm

// CloseMonitor only cancels diagnostic convergence observation. It never sends
// an Exit/Stop command or changes Supervisor/controller ownership.
// Call after HTTP handlers have drained.
func (a *Adapter) CloseMonitor() {
	a.playlistConvergenceMu.Lock()
	defer a.playlistConvergenceMu.Unlock()
	if a.playlistConvergenceCancel != nil {
		a.playlistConvergenceCancel()
		a.playlistConvergenceCancel = nil
	}
}
