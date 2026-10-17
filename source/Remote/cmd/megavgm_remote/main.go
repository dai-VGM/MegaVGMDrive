//go:build linux

package main

import (
	"bufio"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/dai-VGM/megavgm-remote/internal/megavgm"
)

const name = "megavgm_remote"
const address = ":8183"

type identity struct {
	PID   int    `json:"pid"`
	Start string `json:"start"`
	SHA   string `json:"sha256"`
}

type options struct{ runtime, testRoot string }

func (o options) file(suffix string) string { return filepath.Join(o.runtime, name+suffix) }

func fileSHA(p string) (string, error) {
	f, err := os.Open(p)
	if err != nil {
		return "", err
	}
	defer f.Close()
	h := sha256.New()
	if _, err = io.Copy(h, f); err != nil {
		return "", err
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}
func processIdentity(pid int) (identity, error) {
	base := fmt.Sprintf("/proc/%d", pid)
	b, err := os.ReadFile(base + "/stat")
	if err != nil {
		return identity{}, err
	}
	// comm may contain spaces or parentheses; fields after its final ')' start at field 3.
	i := strings.LastIndex(string(b), ")")
	if i < 0 {
		return identity{}, errors.New("invalid process stat")
	}
	fields := strings.Fields(string(b[i+1:]))
	if len(fields) < 20 {
		return identity{}, errors.New("short process stat")
	}
	h, err := fileSHA(base + "/exe")
	if err != nil {
		return identity{}, err
	}
	return identity{pid, fields[19], h}, nil
}
func recorded(o options) (identity, error) {
	b, err := os.ReadFile(o.file(".pid"))
	if err != nil {
		return identity{}, err
	}
	pid, err := strconv.Atoi(strings.TrimSpace(string(b)))
	if err != nil {
		return identity{}, err
	}
	b, err = os.ReadFile(o.file(".identity"))
	if err != nil {
		return identity{}, err
	}
	var want identity
	if err = json.Unmarshal(b, &want); err != nil {
		return identity{}, err
	}
	if pid <= 1 || want.PID != pid {
		return identity{}, errors.New("invalid PID identity")
	}
	got, err := processIdentity(pid)
	if err != nil {
		return identity{}, err
	}
	if got != want {
		return identity{}, errors.New("PID identity mismatch; refusing to signal")
	}
	return got, nil
}
func lock(p string) (*os.File, error) {
	f, err := os.OpenFile(p, os.O_CREATE|os.O_RDWR, 0600)
	if err != nil {
		return nil, err
	}
	if err = syscall.Flock(int(f.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		f.Close()
		return nil, fmt.Errorf("service lock busy: %w", err)
	}
	return f, nil
}
func release(f *os.File) { _ = syscall.Flock(int(f.Fd()), syscall.LOCK_UN); _ = f.Close() }

func config(o options) megavgm.Config {
	c := megavgm.DefaultConfig()
	// Explicit isolated-fixture mode; production defaults remain exact v2.0 paths.
	if o.testRoot != "" {
		c.StatusPath = filepath.Join(o.testRoot, "playlist.status")
		c.SupervisorStatusPath = filepath.Join(o.testRoot, "supervisor.status")
		c.CommandPath = filepath.Join(o.testRoot, "playlist.cmd")
		c.CtlPath = filepath.Join(o.testRoot, "ctl")
		c.SupervisorPath = filepath.Join(o.testRoot, "supervisor")
		c.ApprovedRoot = filepath.Join(o.testRoot, "library")
		c.FavoritesPath = filepath.Join(o.testRoot, "playlists.json")
		c.SnapshotDirectory = o.testRoot
		c.HandoffTracePath = filepath.Join(o.testRoot, "handoff.log")
	}
	return c
}

func serve(o options, ready io.Writer) error {
	lifetime, err := lock(o.file(".lock"))
	if err != nil {
		return err
	}
	defer release(lifetime)
	listener, err := net.Listen("tcp", address)
	if err != nil {
		return fmt.Errorf("cannot bind %s (no port fallback): %w", address, err)
	}
	defer listener.Close()
	id, err := processIdentity(os.Getpid())
	if err != nil {
		return err
	}
	b, _ := json.Marshal(id)
	if err = os.WriteFile(o.file(".identity"), b, 0600); err != nil {
		return err
	}
	if err = os.WriteFile(o.file(".pid"), []byte(strconv.Itoa(id.PID)+"\n"), 0600); err != nil {
		return err
	}
	defer os.Remove(o.file(".identity"))
	defer os.Remove(o.file(".pid"))
	a := megavgm.NewAdapter(config(o))
	defer a.CloseMonitor()
	srv := &http.Server{Handler: handler(a), ReadTimeout: 15 * time.Second, WriteTimeout: 40 * time.Second}
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGTERM, syscall.SIGINT)
	defer signal.Stop(stop)
	done := make(chan error, 1)
	go func() { done <- srv.Serve(listener) }()
	log.Printf("listening %s pid=%d sha256=%s", address, id.PID, id.SHA)
	if ready != nil {
		_, _ = fmt.Fprintln(ready, "READY")
	}
	select {
	case err = <-done:
		if !errors.Is(err, http.ErrServerClosed) {
			return err
		}
	case <-stop:
		log.Print("draining HTTP; Supervisor/controller untouched")
		ctx, cancel := context.WithTimeout(context.Background(), 45*time.Second)
		defer cancel()
		if err = srv.Shutdown(ctx); err != nil {
			// No forced process kill or playback command. Finish accepted handlers.
			log.Printf("drain deadline: %v; waiting for handlers", err)
			_ = srv.Shutdown(context.Background())
		}
	}
	return nil
}

func start(o options) error {
	guard, err := lock(o.file(".start.lock"))
	if err != nil {
		return err
	}
	defer release(guard)
	check, err := lock(o.file(".lock"))
	if err != nil {
		return errors.New("megavgm_remote already running or starting")
	}
	release(check)
	source, err := os.Executable()
	if err != nil {
		return err
	}
	in, err := os.Open(source)
	if err != nil {
		return err
	}
	defer in.Close()
	tmp, err := os.CreateTemp(o.runtime, ".megavgm_remote-stage-")
	if err != nil {
		return err
	}
	defer os.Remove(tmp.Name())
	if _, err = io.Copy(tmp, in); err != nil {
		tmp.Close()
		return err
	}
	if err = tmp.Chmod(0755); err != nil {
		tmp.Close()
		return err
	}
	if err = tmp.Sync(); err != nil {
		tmp.Close()
		return err
	}
	if err = tmp.Close(); err != nil {
		return err
	}
	if err = os.Rename(tmp.Name(), o.file("")); err != nil {
		return err
	}
	reader, writer, err := os.Pipe()
	if err != nil {
		return err
	}
	defer reader.Close()
	logfile, err := os.OpenFile(o.file(".log"), os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0600)
	if err != nil {
		writer.Close()
		return err
	}
	defer logfile.Close()
	cmd := exec.Command(o.file(""), "-service", "exec", "-runtime-dir", o.runtime, "-test-root", o.testRoot, "-ready-fd", "3")
	cmd.ExtraFiles = []*os.File{writer}
	cmd.Stdout = logfile
	cmd.Stderr = logfile
	cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
	if err = cmd.Start(); err != nil {
		writer.Close()
		return err
	}
	writer.Close()
	result := make(chan string, 1)
	go func() { line, _ := bufio.NewReader(reader).ReadString('\n'); result <- strings.TrimSpace(line) }()
	select {
	case line := <-result:
		if line != "READY" {
			_ = cmd.Wait()
			return fmt.Errorf("daemon start failed: %s (see %s)", line, o.file(".log"))
		}
		_ = cmd.Process.Release()
		fmt.Println("megavgm_remote listening on 8183")
		return nil
	case <-time.After(10 * time.Second):
		// Only the child just created here is signalled, never an unverified PID file.
		_ = cmd.Process.Signal(syscall.SIGTERM)
		return errors.New("daemon readiness timed out; inspect log before retry")
	}
}

func stop(o options) error {
	id, err := recorded(o)
	if err != nil {
		return fmt.Errorf("service not running or unverifiable: %w", err)
	}
	// Revalidate immediately before signalling; never trust PID alone.
	got, err := processIdentity(id.PID)
	if err != nil || got != id {
		return errors.New("PID identity changed")
	}
	if err = syscall.Kill(id.PID, syscall.SIGTERM); err != nil {
		return err
	}
	deadline := time.Now().Add(50 * time.Second)
	for time.Now().Before(deadline) {
		// PID cleanup precedes the deferred lifetime unlock. Wait for the lock,
		// not just PID disappearance, so an immediate restart cannot race cleanup.
		if free, e := lock(o.file(".lock")); e == nil {
			release(free)
			return nil
		}
		if replacement, e := recorded(o); e == nil && replacement != id {
			return errors.New("service replaced concurrently; replacement left untouched")
		}
		time.Sleep(50 * time.Millisecond)
	}
	return errors.New("HTTP drain still active; not force-killing")
}

func main() {
	svc := flag.String("service", "exec", "start|stop|restart|status|exec (manual only)")
	runtime := flag.String("runtime-dir", "/tmp", "private service runtime directory")
	testRoot := flag.String("test-root", "", "explicit isolated host fixture root; never used on hardware")
	readyFD := flag.Int("ready-fd", -1, "internal readiness pipe")
	flag.Parse()
	o := options{*runtime, *testRoot}
	if !filepath.IsAbs(o.runtime) || (o.testRoot != "" && !filepath.IsAbs(o.testRoot)) {
		log.Fatal("paths must be absolute")
	}
	if err := os.MkdirAll(o.runtime, 0700); err != nil {
		log.Fatal(err)
	}
	var err error
	switch *svc {
	case "start":
		err = start(o)
	case "stop":
		err = stop(o)
	case "restart":
		if _, e := recorded(o); e == nil {
			err = stop(o)
		} else {
			f, lockErr := lock(o.file(".lock"))
			if lockErr != nil {
				err = e
			} else {
				release(f)
			}
		}
		if err == nil {
			err = start(o)
		}
	case "status":
		var id identity
		id, err = recorded(o)
		if err == nil {
			fmt.Printf("running pid=%d sha256=%s port=8183\n", id.PID, id.SHA)
		}
	case "exec":
		var ready *os.File
		if *readyFD >= 0 {
			ready = os.NewFile(uintptr(*readyFD), "ready")
			syscall.CloseOnExec(*readyFD)
			defer ready.Close()
		}
		if ready == nil {
			err = serve(o, nil)
		} else {
			err = serve(o, ready)
			if err != nil {
				fmt.Fprintln(ready, "ERROR: "+err.Error())
			}
		}
	default:
		err = errors.New("unknown service action")
	}
	if err != nil {
		log.Print(err)
		os.Exit(1)
	}
}
