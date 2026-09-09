package megavgm

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"syscall"
	"testing"
	"time"
)

const validStatus = "state=PLAYING\n" +
	"index=4\n" +
	"count=10\n" +
	"path=/media/fat/Music/04 Beyond the Galaxy.vgm\n" +
	"session=27\n" +
	"loop_count=1\n"

func supervisorStatus(mode, main, controller, playlist string) string {
	return "mode=" + mode + "\n" +
		"main=" + main + "\n" +
		"controller=" + controller + "\n" +
		"playlist=" + playlist + "\n" +
		"detail=test status\n"
}

const supervisorHashDiagnostics = "modified_main_path=/media/fat/MegaVGMPlayer/MiSTer.megavgm\n" +
	"modified_main_size=1063652\n" +
	"modified_main_sha_expected=ae6e050f87749962a354b0879bac45f33e58be64fb3892d4157a1754407f955e\n" +
	"modified_main_sha_actual=ae6e050f87749962a354b0879bac45f33e58be64fb3892d4157a1754407f955e\n" +
	"modified_main_sha256_file_success=YES\n" +
	"modified_main_sha_errno=0\n"

func TestParseValidPlayingStatus(t *testing.T) {
	status, err := ParseStatus(strings.NewReader(validStatus))
	if err != nil {
		t.Fatal(err)
	}
	if status.State != "PLAYING" || status.Index != 4 || status.Count != 10 || status.Session != 27 {
		t.Fatalf("unexpected status: %#v", status)
	}
	if status.Title != "04 Beyond the Galaxy" || status.LoopCount != 1 {
		t.Fatalf("unexpected track data: %#v", status)
	}
	if status.Repeat != "OFF" || status.Shuffle || status.Traversal != "ORDERED" {
		t.Fatalf("unexpected default playback modes: %#v", status)
	}
}

func TestParseStoppedStatusRetainsTrackIdentity(t *testing.T) {
	status, err := ParseStatus(strings.NewReader(strings.Replace(
		validStatus, "state=PLAYING", "state=STOPPED", 1)))
	if err != nil {
		t.Fatal(err)
	}
	if status.State != "STOPPED" || status.Path == "" || status.Session != 27 {
		t.Fatalf("unexpected stopped status: %#v", status)
	}
}

func TestParsePlaybackModes(t *testing.T) {
	modeStatus := validStatus + "repeat=ALL\nshuffle=1\ntraversal=SHUFFLE\n"
	status, err := ParseStatus(strings.NewReader(modeStatus))
	if err != nil {
		t.Fatal(err)
	}
	if status.Repeat != "ALL" || !status.Shuffle || status.Traversal != "SHUFFLE" {
		t.Fatalf("unexpected playback modes: %#v", status)
	}
	for _, replacement := range []string{
		"repeat=BAD\nshuffle=1\ntraversal=SHUFFLE\n",
		"repeat=ALL\nshuffle=2\ntraversal=SHUFFLE\n",
		"repeat=ALL\nshuffle=0\ntraversal=SHUFFLE\n",
	} {
		if _, err := ParseStatus(strings.NewReader(validStatus + replacement)); err == nil {
			t.Fatalf("invalid playback modes accepted: %q", replacement)
		}
	}
}

func TestParseStatusRejectsMalformedValues(t *testing.T) {
	tests := []string{
		strings.Replace(validStatus, "state=PLAYING", "bad line", 1),
		strings.Repeat("x", MaximumStatusSize+1),
		validStatus + "state=PLAYING\n",
		strings.Replace(validStatus, "session=27", "session=-1", 1),
		strings.Replace(validStatus, "state=PLAYING", "state=UNKNOWN", 1),
	}
	for _, content := range tests {
		if _, err := ParseStatus(strings.NewReader(content)); err == nil {
			t.Fatalf("parse unexpectedly succeeded for %q", content[:min(len(content), 80)])
		}
	}
}

func TestParseSupervisorStatus(t *testing.T) {
	status, err := ParseSupervisorStatus(strings.NewReader(supervisorStatus(
		"MEGAVGM", "MODIFIED", "RUNNING", "/media/fat/MegaVGMDrive/game")))
	if err != nil {
		t.Fatal(err)
	}
	if status.Mode != "MEGAVGM" || status.Main != "MODIFIED" || status.Controller != "RUNNING" {
		t.Fatalf("unexpected status: %#v", status)
	}
}

func TestParseSupervisorStatusIgnoresForwardCompatibleFields(t *testing.T) {
	tests := []struct {
		name     string
		status   string
		wantMode string
		wantMain string
		wantCtl  string
	}{
		{
			name:     "pre-diagnostic",
			status:   supervisorStatus("MEGAVGM", "MODIFIED", "RUNNING", "/music"),
			wantMode: "MEGAVGM", wantMain: "MODIFIED", wantCtl: "RUNNING",
		},
		{
			name: "megavgm-diagnostics",
			status: supervisorStatus("MEGAVGM", "MODIFIED", "RUNNING", "/music") +
				supervisorHashDiagnostics,
			wantMode: "MEGAVGM", wantMain: "MODIFIED", wantCtl: "RUNNING",
		},
		{
			name: "stock-diagnostics",
			status: supervisorStatus("STOCK", "STOCK", "STOPPED", "") +
				supervisorHashDiagnostics,
			wantMode: "STOCK", wantMain: "STOCK", wantCtl: "STOPPED",
		},
		{
			name: "failure-diagnostics",
			status: supervisorStatus("FAILURE", "UNKNOWN", "UNKNOWN", "") +
				supervisorHashDiagnostics,
			wantMode: "FAILURE", wantMain: "UNKNOWN", wantCtl: "UNKNOWN",
		},
		{
			name: "one-unknown",
			status: supervisorStatus("MEGAVGM", "MODIFIED", "RUNNING", "/music") +
				"future_field=value\n",
			wantMode: "MEGAVGM", wantMain: "MODIFIED", wantCtl: "RUNNING",
		},
		{
			name: "multiple-unknown",
			status: supervisorStatus("STOCK", "STOCK", "STOPPED", "") +
				"future_one=1\nfuture_two=two=parts\nfuture_three=\n",
			wantMode: "STOCK", wantMain: "STOCK", wantCtl: "STOPPED",
		},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			status, err := ParseSupervisorStatus(strings.NewReader(test.status))
			if err != nil {
				t.Fatal(err)
			}
			if status.Mode != test.wantMode || status.Main != test.wantMain ||
				status.Controller != test.wantCtl {
				t.Fatalf("unexpected status: %#v", status)
			}
		})
	}
}

func TestParseSupervisorStatusStillRejectsInvalidRequiredSchema(t *testing.T) {
	valid := supervisorStatus("MEGAVGM", "MODIFIED", "RUNNING", "/music")
	tests := map[string]string{
		"missing-mode":   strings.Replace(valid, "mode=MEGAVGM\n", "", 1),
		"invalid-mode":   strings.Replace(valid, "mode=MEGAVGM", "mode=INVALID", 1),
		"malformed-line": valid + "not-a-key-value-line\n",
		"duplicate-mode": valid + "mode=MEGAVGM\n",
	}
	for name, content := range tests {
		t.Run(name, func(t *testing.T) {
			if _, err := ParseSupervisorStatus(strings.NewReader(content)); err == nil {
				t.Fatalf("invalid supervisor status accepted: %q", content)
			}
		})
	}
}

func TestStatusAcceptsDiagnosticSupervisorStatus(t *testing.T) {
	dir := t.TempDir()
	adapter := newTestAdapter(t, dir, nil)
	writeFile(t, adapter.config.SupervisorStatusPath,
		supervisorStatus("MEGAVGM", "MODIFIED", "RUNNING",
			adapter.config.DefaultPlaylistPath)+supervisorHashDiagnostics, 0644)
	makeFIFO(t, adapter.config.CommandPath)
	writeFile(t, adapter.config.StatusPath, validStatus, 0644)
	recorder := request(t, http.MethodGet, nil, adapter.HandleStatus)
	if recorder.Code != http.StatusOK {
		t.Fatalf("status=%d body=%s", recorder.Code, recorder.Body.String())
	}
	if strings.Contains(recorder.Body.String(), "modified_main_") {
		t.Fatalf("diagnostic Supervisor fields leaked into API: %s", recorder.Body.String())
	}
	var status Status
	decodeResponse(t, recorder, &status)
	if status.Mode != "MEGAVGM" || status.Main != "MODIFIED" ||
		!status.ControllerRunning || status.Session != 27 {
		t.Fatalf("unexpected status: %#v", status)
	}
}

func TestStatusCombinesSupervisorAndPlaylist(t *testing.T) {
	dir := t.TempDir()
	adapter := newTestAdapter(t, dir, nil)
	writeSupervisor(t, adapter, "MEGAVGM", "MODIFIED", "RUNNING", adapter.config.DefaultPlaylistPath)
	makeFIFO(t, adapter.config.CommandPath)
	writeFile(t, adapter.config.StatusPath,
		validStatus+"repeat=ONE\nshuffle=1\ntraversal=SHUFFLE\n", 0644)
	recorder := request(t, http.MethodGet, nil, adapter.HandleStatus)
	if recorder.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", recorder.Code, recorder.Body.String())
	}
	var status Status
	decodeResponse(t, recorder, &status)
	if status.Mode != "MEGAVGM" || status.Main != "MODIFIED" || !status.ControllerRunning || status.Session != 27 {
		t.Fatalf("unexpected status: %#v", status)
	}
	if status.Repeat != "ONE" || !status.Shuffle || status.Traversal != "SHUFFLE" {
		t.Fatalf("playback mode truth missing from API: %#v", status)
	}
	if status.StatusFileMtimeUnixMs <= 0 || status.StatusReadUnixMs < status.StatusFileMtimeUnixMs {
		t.Fatalf("missing status timing: %#v", status)
	}
}

func TestFreshBootWithoutSupervisorStatusIsStock(t *testing.T) {
	dir := t.TempDir()
	adapter := newTestAdapter(t, dir, nil)
	recorder := request(t, http.MethodGet, nil, adapter.HandleStatus)
	var status Status
	decodeResponse(t, recorder, &status)
	if recorder.Code != http.StatusOK || status.Mode != "STOCK" || status.Main != "STOCK" {
		t.Fatalf("unexpected fresh-boot status: %#v", status)
	}
}

func TestStockIgnoresStalePlaylistStatusAndFIFO(t *testing.T) {
	dir := t.TempDir()
	adapter := newTestAdapter(t, dir, nil)
	writeSupervisor(t, adapter, "STOCK", "STOCK", "STOPPED", "")
	makeFIFO(t, adapter.config.CommandPath)
	writeFile(t, adapter.config.StatusPath, validStatus, 0644)
	recorder := request(t, http.MethodGet, nil, adapter.HandleStatus)
	var status Status
	decodeResponse(t, recorder, &status)
	if recorder.Code != http.StatusOK || status.Mode != "STOCK" || status.ControllerRunning ||
		status.State != "" || status.Path != "" || status.Session != 0 {
		t.Fatalf("stale playlist data leaked: %#v", status)
	}
}

func TestMalformedSupervisorStatus(t *testing.T) {
	dir := t.TempDir()
	adapter := newTestAdapter(t, dir, nil)
	writeFile(t, adapter.config.SupervisorStatusPath, "mode=MEGAVGM\n", 0644)
	recorder := request(t, http.MethodGet, nil, adapter.HandleStatus)
	assertAPIError(t, recorder, http.StatusInternalServerError, "invalid_supervisor_status")
}

func TestStartFromStockReachesMegaVGM(t *testing.T) {
	dir := t.TempDir()
	var invocation []string
	adapter := newTestAdapter(t, dir, nil)
	// Replace the runner now that the adapter exists, and publish the state the
	// real ENTER parent reports only after its resident daemon is active.
	adapter.run = func(_ context.Context, path string, args ...string) ([]byte, error) {
		invocation = append([]string{path}, args...)
		writeSupervisor(t, adapter, "MEGAVGM", "MODIFIED", "RUNNING", adapter.config.DefaultPlaylistPath)
		return []byte("MEGAVGM MODE ACTIVE\n"), nil
	}
	writeSupervisor(t, adapter, "STOCK", "STOCK", "STOPPED", "")
	writeExecutable(t, adapter.config.SupervisorPath)
	recorder := performStartRequest(t, adapter, adapter.config.DefaultPlaylistPath)
	if recorder.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", recorder.Code, recorder.Body.String())
	}
	wantPlaylist, err := filepath.EvalSymlinks(adapter.config.DefaultPlaylistPath)
	if err != nil {
		t.Fatal(err)
	}
	if len(invocation) != 3 || invocation[0] != adapter.config.SupervisorPath ||
		invocation[1] != "enter" || invocation[2] != wantPlaylist {
		t.Fatalf("invocation = %#v", invocation)
	}
	assertLifecycleResult(t, recorder, "MEGAVGM_MODE_ACTIVE", "MEGAVGM")
}

func TestStartWaitsForStatusConvergenceAfterSupervisorReturns(t *testing.T) {
	dir := t.TempDir()
	adapter := newTestAdapter(t, dir, nil)
	adapter.config.StartTimeout = time.Second
	writeSupervisor(t, adapter, "STOCK", "STOCK", "STOPPED", "")
	writeExecutable(t, adapter.config.SupervisorPath)
	writeErrors := make(chan error, 1)
	adapter.run = func(_ context.Context, _ string, _ ...string) ([]byte, error) {
		go func() {
			time.Sleep(80 * time.Millisecond)
			writeErrors <- os.WriteFile(adapter.config.SupervisorStatusPath,
				[]byte(supervisorStatus("MEGAVGM", "MODIFIED", "RUNNING",
					adapter.config.DefaultPlaylistPath)), 0644)
		}()
		return []byte("ENTER ACCEPTED\n"), nil
	}
	started := time.Now()
	recorder := performStartRequest(t, adapter, adapter.config.DefaultPlaylistPath)
	if err := <-writeErrors; err != nil {
		t.Fatal(err)
	}
	if recorder.Code != http.StatusOK {
		t.Fatalf("status=%d body=%s", recorder.Code, recorder.Body.String())
	}
	if elapsed := time.Since(started); elapsed < 50*time.Millisecond {
		t.Fatalf("handler did not wait for status convergence: %s", elapsed)
	}
	assertLifecycleResult(t, recorder, "MEGAVGM_MODE_ACTIVE", "MEGAVGM")
}

func TestStartAlreadyActiveSamePlaylistIsIdempotent(t *testing.T) {
	dir := t.TempDir()
	var calls atomic.Int32
	adapter := newTestAdapter(t, dir, func(context.Context, string, ...string) ([]byte, error) {
		calls.Add(1)
		return nil, nil
	})
	writeSupervisor(t, adapter, "MEGAVGM", "MODIFIED", "RUNNING", adapter.config.DefaultPlaylistPath)
	recorder := performStartRequest(t, adapter, adapter.config.DefaultPlaylistPath)
	if recorder.Code != http.StatusOK || calls.Load() != 0 {
		t.Fatalf("status=%d calls=%d body=%s", recorder.Code, calls.Load(), recorder.Body.String())
	}
	assertLifecycleResult(t, recorder, "ALREADY_ACTIVE", "MEGAVGM")
}

func TestStartRejectsInvalidPaths(t *testing.T) {
	dir := t.TempDir()
	adapter := newTestAdapter(t, dir, nil)
	writeSupervisor(t, adapter, "STOCK", "STOCK", "STOPPED", "")
	for _, path := range []string{"relative/path", adapter.config.DefaultPlaylistPath + "\nother", ""} {
		recorder := performStartRequest(t, adapter, path)
		assertAPIError(t, recorder, http.StatusBadRequest, "invalid_playlist_path")
	}
	file := filepath.Join(adapter.config.ApprovedRoot, "not-a-directory")
	writeFile(t, file, "x", 0644)
	assertAPIError(t, performStartRequest(t, adapter, file), http.StatusBadRequest, "invalid_playlist_path")
	badJSON := request(t, http.MethodPost, strings.NewReader(`{"path":`), adapter.HandleStart)
	assertAPIError(t, badJSON, http.StatusBadRequest, "invalid_request")
}

func TestStartRejectsTraversalAndSymlinkEscape(t *testing.T) {
	dir := t.TempDir()
	adapter := newTestAdapter(t, dir, nil)
	writeSupervisor(t, adapter, "STOCK", "STOCK", "STOPPED", "")
	outside := filepath.Join(dir, "outside")
	mustMkdir(t, outside)
	assertAPIError(t, performStartRequest(t, adapter,
		filepath.Join(adapter.config.ApprovedRoot, "..", "outside")), http.StatusBadRequest, "invalid_playlist_path")
	link := filepath.Join(adapter.config.ApprovedRoot, "escape")
	if err := os.Symlink(outside, link); err != nil {
		t.Fatal(err)
	}
	assertAPIError(t, performStartRequest(t, adapter, link), http.StatusBadRequest, "invalid_playlist_path")
}

func TestStartRejectsOutsideApprovedRoot(t *testing.T) {
	dir := t.TempDir()
	adapter := newTestAdapter(t, dir, nil)
	writeSupervisor(t, adapter, "STOCK", "STOCK", "STOPPED", "")
	outside := filepath.Join(dir, "outside")
	mustMkdir(t, outside)
	assertAPIError(t, performStartRequest(t, adapter, outside), http.StatusBadRequest, "invalid_playlist_path")
}

func TestStartSupervisorMissing(t *testing.T) {
	dir := t.TempDir()
	adapter := newTestAdapter(t, dir, nil)
	writeSupervisor(t, adapter, "STOCK", "STOCK", "STOPPED", "")
	assertAPIError(t, performStartRequest(t, adapter, adapter.config.DefaultPlaylistPath),
		http.StatusServiceUnavailable, "supervisor_unavailable")
}

func TestStartSupervisorFailure(t *testing.T) {
	dir := t.TempDir()
	adapter := newTestAdapter(t, dir, func(context.Context, string, ...string) ([]byte, error) {
		return []byte("ENTER_FAILED\n"), errors.New("exit 1")
	})
	writeSupervisor(t, adapter, "STOCK", "STOCK", "STOPPED", "")
	writeExecutable(t, adapter.config.SupervisorPath)
	assertAPIError(t, performStartRequest(t, adapter, adapter.config.DefaultPlaylistPath),
		http.StatusBadGateway, "supervisor_start_failed")
}

func TestStartTimeout(t *testing.T) {
	dir := t.TempDir()
	adapter := newTestAdapter(t, dir, func(ctx context.Context, _ string, _ ...string) ([]byte, error) {
		<-ctx.Done()
		return nil, ctx.Err()
	})
	adapter.config.StartTimeout = time.Millisecond
	writeSupervisor(t, adapter, "STOCK", "STOCK", "STOPPED", "")
	writeExecutable(t, adapter.config.SupervisorPath)
	assertAPIError(t, performStartRequest(t, adapter, adapter.config.DefaultPlaylistPath),
		http.StatusGatewayTimeout, "supervisor_start_timeout")
}

func TestExitFromMegaVGMRestoresStock(t *testing.T) {
	dir := t.TempDir()
	adapter := newTestAdapter(t, dir, nil)
	adapter.run = func(_ context.Context, path string, args ...string) ([]byte, error) {
		if path != adapter.config.SupervisorPath || len(args) != 1 || args[0] != "exit" {
			t.Fatalf("unexpected invocation: %s %#v", path, args)
		}
		writeSupervisor(t, adapter, "STOCK", "STOCK", "STOPPED", "")
		return []byte("STOCK MISTER RESTORED\n"), nil
	}
	writeSupervisor(t, adapter, "MEGAVGM", "MODIFIED", "RUNNING", adapter.config.DefaultPlaylistPath)
	writeExecutable(t, adapter.config.SupervisorPath)
	recorder := request(t, http.MethodPost, nil, adapter.HandleExit)
	if recorder.Code != http.StatusOK {
		t.Fatalf("status=%d body=%s", recorder.Code, recorder.Body.String())
	}
	assertLifecycleResult(t, recorder, "STOCK_MISTER_RESTORED", "STOCK")
}

func TestExitAlreadyStockIsIdempotent(t *testing.T) {
	dir := t.TempDir()
	var calls atomic.Int32
	adapter := newTestAdapter(t, dir, func(context.Context, string, ...string) ([]byte, error) {
		calls.Add(1)
		return nil, nil
	})
	writeSupervisor(t, adapter, "STOCK", "STOCK", "STOPPED", "")
	recorder := request(t, http.MethodPost, nil, adapter.HandleExit)
	if recorder.Code != http.StatusOK || calls.Load() != 0 {
		t.Fatalf("status=%d calls=%d", recorder.Code, calls.Load())
	}
	assertLifecycleResult(t, recorder, "ALREADY_STOPPED", "STOCK")
}

func TestExitWhileRestoringReportsProgress(t *testing.T) {
	dir := t.TempDir()
	adapter := newTestAdapter(t, dir, nil)
	writeSupervisor(t, adapter, "SHUTTING_DOWN", "STOPPED", "STOPPED", adapter.config.DefaultPlaylistPath)
	recorder := request(t, http.MethodPost, nil, adapter.HandleExit)
	if recorder.Code != http.StatusAccepted {
		t.Fatalf("status=%d body=%s", recorder.Code, recorder.Body.String())
	}
	assertLifecycleResult(t, recorder, "RESTORE_IN_PROGRESS", "SHUTTING_DOWN")
}

func TestRemoteHandlersRemainReachableAcrossLifecycle(t *testing.T) {
	dir := t.TempDir()
	adapter := newTestAdapter(t, dir, nil)
	adapter.run = func(_ context.Context, _ string, args ...string) ([]byte, error) {
		if args[0] == "enter" {
			writeSupervisor(t, adapter, "MEGAVGM", "MODIFIED", "RUNNING", adapter.config.DefaultPlaylistPath)
			return []byte("MEGAVGM MODE ACTIVE\n"), nil
		}
		writeSupervisor(t, adapter, "STOCK", "STOCK", "STOPPED", "")
		return []byte("STOCK MISTER RESTORED\n"), nil
	}
	writeExecutable(t, adapter.config.SupervisorPath)
	writeSupervisor(t, adapter, "STOCK", "STOCK", "STOPPED", "")
	start := performStartRequest(t, adapter, adapter.config.DefaultPlaylistPath)
	if start.Code != http.StatusOK {
		t.Fatalf("start status=%d body=%s", start.Code, start.Body.String())
	}
	assertHandlerStatusMode(t, adapter.HandleStatus, "MEGAVGM")
	exit := request(t, http.MethodPost, nil, adapter.HandleExit)
	if exit.Code != http.StatusOK {
		t.Fatalf("exit status=%d body=%s", exit.Code, exit.Body.String())
	}
	assertHandlerStatusMode(t, adapter.HandleStatus, "STOCK")
}

func TestNavigationRequiresActiveSupervisorAndMapsActions(t *testing.T) {
	for _, test := range []struct {
		name, action string
		handler      func(*Adapter) http.HandlerFunc
	}{
		{"next", "next", func(a *Adapter) http.HandlerFunc { return a.HandleNext }},
		{"previous", "prev", func(a *Adapter) http.HandlerFunc { return a.HandlePrevious }},
		{"stop", "stop", func(a *Adapter) http.HandlerFunc { return a.HandleStop }},
	} {
		t.Run(test.name, func(t *testing.T) {
			dir := t.TempDir()
			var invocation []string
			adapter := newTestAdapter(t, dir, func(_ context.Context, path string, args ...string) ([]byte, error) {
				invocation = append([]string{path}, args...)
				return nil, nil
			})
			writeSupervisor(t, adapter, "MEGAVGM", "MODIFIED", "RUNNING", adapter.config.DefaultPlaylistPath)
			makeFIFO(t, adapter.config.CommandPath)
			writeExecutable(t, adapter.config.CtlPath)
			recorder := request(t, http.MethodPost, nil, test.handler(adapter))
			if recorder.Code != http.StatusAccepted {
				t.Fatalf("status=%d body=%s", recorder.Code, recorder.Body.String())
			}
			if len(invocation) != 2 || invocation[0] != adapter.config.CtlPath || invocation[1] != test.action {
				t.Fatalf("invocation=%#v", invocation)
			}
		})
	}
}

func TestNavigationTimeout(t *testing.T) {
	dir := t.TempDir()
	adapter := newTestAdapter(t, dir, func(ctx context.Context, _ string, _ ...string) ([]byte, error) {
		<-ctx.Done()
		return nil, ctx.Err()
	})
	adapter.config.CtlTimeout = time.Millisecond
	writeSupervisor(t, adapter, "MEGAVGM", "MODIFIED", "RUNNING", adapter.config.DefaultPlaylistPath)
	makeFIFO(t, adapter.config.CommandPath)
	writeExecutable(t, adapter.config.CtlPath)
	assertAPIError(t, request(t, http.MethodPost, nil, adapter.HandleNext),
		http.StatusGatewayTimeout, "control_timeout")
}

func TestPlaybackModeCommandsRequireControllerAndMapArguments(t *testing.T) {
	tests := []struct {
		name    string
		body    string
		handler func(*Adapter) http.HandlerFunc
		want    []string
	}{
		{"repeat-off", `{"mode":"off"}`, func(a *Adapter) http.HandlerFunc { return a.HandleRepeat }, []string{"repeat", "off"}},
		{"repeat-one", `{"mode":"one"}`, func(a *Adapter) http.HandlerFunc { return a.HandleRepeat }, []string{"repeat", "one"}},
		{"repeat-all", `{"mode":"all"}`, func(a *Adapter) http.HandlerFunc { return a.HandleRepeat }, []string{"repeat", "all"}},
		{"shuffle-on", `{"enabled":true}`, func(a *Adapter) http.HandlerFunc { return a.HandleShuffle }, []string{"shuffle", "on"}},
		{"shuffle-off", `{"enabled":false}`, func(a *Adapter) http.HandlerFunc { return a.HandleShuffle }, []string{"shuffle", "off"}},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			dir := t.TempDir()
			var invocation []string
			adapter := newTestAdapter(t, dir, func(_ context.Context, path string, args ...string) ([]byte, error) {
				invocation = append([]string{path}, args...)
				return nil, nil
			})
			writeSupervisor(t, adapter, "MEGAVGM", "MODIFIED", "RUNNING", adapter.config.DefaultPlaylistPath)
			makeFIFO(t, adapter.config.CommandPath)
			writeExecutable(t, adapter.config.CtlPath)
			recorder := request(t, http.MethodPost, strings.NewReader(test.body), test.handler(adapter))
			if recorder.Code != http.StatusAccepted {
				t.Fatalf("status=%d body=%s", recorder.Code, recorder.Body.String())
			}
			want := append([]string{adapter.config.CtlPath}, test.want...)
			if strings.Join(invocation, "\x00") != strings.Join(want, "\x00") {
				t.Fatalf("invocation=%#v want=%#v", invocation, want)
			}
		})
	}

	dir := t.TempDir()
	adapter := newTestAdapter(t, dir, nil)
	writeSupervisor(t, adapter, "STOCK", "STOCK", "STOPPED", "")
	assertAPIError(t, request(t, http.MethodPost, strings.NewReader(`{"mode":"all"}`), adapter.HandleRepeat),
		http.StatusServiceUnavailable, "controller_unavailable")
	assertAPIError(t, request(t, http.MethodPost, strings.NewReader(`{"mode":"bad"}`), adapter.HandleRepeat),
		http.StatusBadRequest, "invalid_repeat_mode")
	assertAPIError(t, request(t, http.MethodPost, strings.NewReader(`{"enabled":"yes"}`), adapter.HandleShuffle),
		http.StatusBadRequest, "invalid_shuffle_mode")
	assertAPIError(t, request(t, http.MethodPost, strings.NewReader(`{}`), adapter.HandleShuffle),
		http.StatusBadRequest, "invalid_shuffle_mode")
}

func newTestAdapter(t *testing.T, dir string, runner commandRunner) *Adapter {
	t.Helper()
	root := filepath.Join(dir, "MegaVGMDrive")
	playlist := filepath.Join(root, "01_Arcade", "Galaxy_Force_II_(Sega_Y)")
	mustMkdir(t, playlist)
	config := Config{
		StatusPath:           filepath.Join(dir, "playlist.status"),
		CommandPath:          filepath.Join(dir, "playlist.cmd"),
		CtlPath:              filepath.Join(dir, "megavgm_ctl"),
		SupervisorStatusPath: filepath.Join(dir, "supervisor.status"),
		SupervisorPath:       filepath.Join(dir, "megavgm_supervisor"),
		ApprovedRoot:         root,
		FavoritesPath:        filepath.Join(dir, "config", "playlists.json"),
		HandoffTracePath:     filepath.Join(dir, "playlist-handoff.log"),
		DefaultPlaylistPath:  playlist,
		CtlTimeout:           20 * time.Millisecond,
		StartTimeout:         20 * time.Millisecond,
		ExitTimeout:          20 * time.Millisecond,
	}
	if runner == nil {
		runner = func(context.Context, string, ...string) ([]byte, error) {
			return nil, errors.New("unexpected command")
		}
	}
	adapter := newAdapter(config, runner)
	t.Cleanup(func() { retireFixture(adapter) })
	return adapter
}

func writeSupervisor(t *testing.T, adapter *Adapter, mode, main, controller, playlist string) {
	t.Helper()
	writeFile(t, adapter.config.SupervisorStatusPath,
		supervisorStatus(mode, main, controller, playlist), 0644)
}

func performStartRequest(t *testing.T, adapter *Adapter, path string) *httptest.ResponseRecorder {
	t.Helper()
	body, err := json.Marshal(startRequest{Path: path})
	if err != nil {
		t.Fatal(err)
	}
	return request(t, http.MethodPost, strings.NewReader(string(body)), adapter.HandleStart)
}

func request(t *testing.T, method string, body *strings.Reader, handler http.HandlerFunc) *httptest.ResponseRecorder {
	t.Helper()
	var reader = strings.NewReader("")
	if body != nil {
		reader = body
	}
	recorder := httptest.NewRecorder()
	handler(recorder, httptest.NewRequest(method, "/", reader))
	return recorder
}

func decodeResponse(t *testing.T, recorder *httptest.ResponseRecorder, value interface{}) {
	t.Helper()
	if err := json.NewDecoder(recorder.Body).Decode(value); err != nil {
		t.Fatal(err)
	}
}

func assertAPIError(t *testing.T, recorder *httptest.ResponseRecorder, status int, code string) {
	t.Helper()
	if recorder.Code != status {
		t.Fatalf("status=%d body=%s", recorder.Code, recorder.Body.String())
	}
	var response struct {
		Error string `json:"error"`
	}
	decodeResponse(t, recorder, &response)
	if response.Error != code {
		t.Fatalf("error=%q body=%s", response.Error, recorder.Body.String())
	}
}

func assertLifecycleResult(t *testing.T, recorder *httptest.ResponseRecorder, result, mode string) {
	t.Helper()
	var response lifecycleResponse
	decodeResponse(t, recorder, &response)
	if !response.Accepted || response.Result != result || response.Mode != mode {
		t.Fatalf("unexpected response: %#v", response)
	}
}

func writeFile(t *testing.T, path, content string, mode os.FileMode) {
	t.Helper()
	if err := os.WriteFile(path, []byte(content), mode); err != nil {
		t.Fatal(err)
	}
}

func writeExecutable(t *testing.T, path string) {
	t.Helper()
	writeFile(t, path, "test", 0755)
}

func makeFIFO(t *testing.T, path string) {
	t.Helper()
	if err := syscall.Mkfifo(path, 0600); err != nil {
		t.Fatal(err)
	}
}

func mustMkdir(t *testing.T, path string) {
	t.Helper()
	if err := os.MkdirAll(path, 0755); err != nil {
		t.Fatal(err)
	}
}

func assertHandlerStatusMode(t *testing.T, handler http.HandlerFunc, mode string) {
	t.Helper()
	response := request(t, http.MethodGet, nil, handler)
	var status Status
	decodeResponse(t, response, &status)
	if response.Code != http.StatusOK || status.Mode != mode {
		t.Fatalf("status=%d mode=%s", response.Code, status.Mode)
	}
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}
