#include "linux_runtime.h"
#include "runtime_support.h"
#include "sha256.h"
#include "supervisor.h"
#include "test_profile.h"

#include <algorithm>
#include <array>
#include <cassert>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <string>
#include <sys/stat.h>
#include <unistd.h>
#include <vector>

using megavgm_supervisor::AtomicStatusPublisher;
using megavgm_supervisor::ControllerDiagnostics;
using megavgm_supervisor::InstanceLock;
using megavgm_supervisor::OperationResult;
using megavgm_supervisor::Paths;
using megavgm_supervisor::Runtime;
using megavgm_supervisor::Snapshot;
using megavgm_supervisor::StatusPublisher;
using megavgm_supervisor::Supervisor;
using megavgm_supervisor::VerifiedInputs;

namespace {

class RecordingPublisher : public StatusPublisher {
public:
	OperationResult publish(const Snapshot &snapshot) override
	{
		snapshots.push_back(snapshot);
		return OperationResult::success();
	}

	std::vector<Snapshot> snapshots;
};

class FakeRuntime : public Runtime {
public:
	OperationResult call(const std::string &operation)
	{
		calls.push_back(operation);
		if (cancel_after == operation) cancel = true;
		if (fail_operation == operation)
			return OperationResult::failure(operation + " injected failure");
		return OperationResult::success();
	}

	OperationResult verify_inputs(const std::string &playlist,
		const std::string &start_file, const std::string &playlist_snapshot,
		VerifiedInputs &inputs) override
	{
		verified_playlist = playlist;
		verified_start_file = start_file;
		verified_playlist_snapshot = playlist_snapshot;
		inputs.modified_main_path = "/fixed/MiSTer.megavgm";
		inputs.modified_main_size = "1063652";
		inputs.modified_main_sha_expected = "modified-hash";
		inputs.modified_main_sha_actual = "modified-hash";
		inputs.modified_main_sha256_file_success = "YES";
		inputs.modified_main_sha_errno = "0";
		OperationResult result = call("verify_inputs");
		if (result.ok) {
			inputs.stock_sha256 = "stock-hash";
			inputs.modified_sha256 = "modified-hash";
		}
		return result;
	}
	OperationResult stop_stock_main(const std::string &) override
	{
		return call("stop_stock_main");
	}
	OperationResult bind_modified_main() override
	{
		return call("bind_modified_main");
	}
	OperationResult start_modified_main(int &pid) override
	{
		OperationResult result = call("start_modified_main");
		if (result.ok) {
			pid = 101;
			initial_modified_alive = true;
		}
		return result;
	}
	OperationResult verify_modified_main(int, const std::string &) override
	{
		return call("verify_modified_main");
	}
	OperationResult load_rbf() override
	{
		OperationResult result = call("load_rbf");
		if (result.ok && exit_initial_on_load) initial_modified_alive = false;
		return result;
	}
	OperationResult select_test_rbf(const std::string &, const std::string &) override {
		return call("select_test_rbf");
	}
	OperationResult reacquire_modified_main(int previous_pid, const std::string &,
		int &current_pid) override
	{
		OperationResult result = call("reacquire_modified_main");
		last_reacquire_previous_pid = previous_pid;
		++reacquire_count;
		if (!result.ok) return result;
		if ((reacquire_count == 1 && !initial_modified_alive &&
			startup_successor_available &&
			successor_sha_valid && successor_rbf_argument) ||
			(reacquire_count > 1 && runtime_successor_available)) {
			current_pid = reacquire_count == 1 ? 102 : 103;
			last_reacquired_pid = current_pid;
			modified_alive = true;
			return OperationResult::success();
		}
		return OperationResult::failure("no valid successor");
	}
	OperationResult verify_megavgm_core(int &pid, const std::string &) override
	{
		verified_core_pid = pid;
		OperationResult result = call("verify_megavgm_core");
		if (!result.ok) return result;
		if (status_scenario == "ABSENT_THEN_READY") {
			status_probe_count = 2;
			return OperationResult::success();
		}
		status_probe_count = 1;
		if (status_scenario == "NEVER")
			return OperationResult::failure("status readiness timeout");
		if (status_scenario == "MALFORMED")
			return OperationResult::failure("malformed status");
		return OperationResult::success();
	}
	OperationResult start_playlist(const std::string &directory,
		const std::string &start_file, const std::string &playlist_snapshot,
		int &pid) override
	{
		started_playlist = directory;
		started_start_file = start_file;
		started_playlist_snapshot = playlist_snapshot;
		OperationResult result = call("start_playlist");
		if (result.ok) {
			pid = 202;
			controller_diagnostic.pid = pid;
			controller_diagnostic.megavgm_status_at_launch =
				status_scenario == "READY" ||
				status_scenario == "ABSENT_THEN_READY";
			controller_diagnostic.active_main_sha256 = "modified-hash";
			controller_diagnostic.active_rbf_argv = "/fixed/playlist.rbf";
			controller_diagnostic.trace_text =
				"INITIAL_FPGA_SESSION=82 MISTER_CMD_WRITE=SUCCESS";
			controller_diagnostic.main_load_file_text =
				"version=1 pid=102 phase=TRANSFER_SUCCESS index=1 path=/music/01.vgm";
			if (!controller_exec_success) {
				controller_diagnostic.exec_state = "FAILED:ENOENT";
				controller_diagnostic.exit_state = "EXIT_CODE_127";
				controller_diagnostic.stderr_text = "exec: ENOENT";
				return OperationResult::failure("controller exec failed");
			}
			controller_diagnostic.exec_state = "SUCCESS";
		}
		return result;
	}
	OperationResult verify_playlist(int) override
	{
		OperationResult result = call("verify_playlist");
		if (result.ok) {
			controller_diagnostic.command_fifo_seen = true;
			controller_diagnostic.status_seen = true;
		}
		return result;
	}
	ControllerDiagnostics controller_diagnostics(int controller_pid,
		int) override
	{
		if (controller_pid > 0) controller_diagnostic.pid = controller_pid;
		if (!controller_alive && controller_diagnostic.exit_state == "NOT_OBSERVED") {
			controller_diagnostic.exit_state = controller_exit_state;
			controller_diagnostic.stderr_text = controller_stderr;
		}
		return controller_diagnostic;
	}
	bool process_alive(int pid) override
	{
		if (pid == 101) {
			calls.push_back("modified_alive");
			return initial_modified_alive;
		}
		if (pid == 102 || pid == 103) {
			calls.push_back("modified_alive");
			return modified_alive;
		}
		calls.push_back("controller_alive");
		return controller_alive;
	}
	bool playlist_complete() override
	{
		calls.push_back("playlist_complete");
		return controller_complete;
	}
	OperationResult stop_playlist(int) override
	{
		OperationResult result = call("stop_playlist");
		if (result.ok && controller_diagnostic.exit_state == "NOT_OBSERVED")
			controller_diagnostic.exit_state = "SUPERVISOR_STOPPED";
		return result;
	}
	OperationResult cleanup_playlist_state() override
	{
		return call("cleanup_playlist_state");
	}
	OperationResult stop_modified_main(int pid) override
	{
		OperationResult result = call("stop_modified_main");
		stopped_modified_pids.push_back(pid);
		if (result.ok) {
			if (pid == 101) initial_modified_alive = false;
			if (pid == 102 || pid == 103) modified_alive = false;
		}
		return result;
	}
	std::vector<int> modified_main_processes(const std::string &) override
	{
		calls.push_back("modified_main_processes");
		if (drain_scan_position < drain_scan_sequence.size())
			return drain_scan_sequence[drain_scan_position++];
		std::vector<int> processes;
		if (initial_modified_alive) processes.push_back(101);
		if (modified_alive) processes.push_back(last_reacquired_pid > 0 ?
			last_reacquired_pid : 102);
		return processes;
	}
	std::uint64_t monotonic_ms() override { return now_ms; }
	void sleep_ms(unsigned int milliseconds) override
	{
		calls.push_back("sleep_ms");
		now_ms += milliseconds;
	}
	OperationResult unmount_modified_main() override
	{
		unmount_at_ms = now_ms;
		return call("unmount_modified_main");
	}
	OperationResult verify_stock_path(const std::string &) override
	{
		return call("verify_stock_path");
	}
	OperationResult start_stock_main(int &pid) override
	{
		OperationResult result = call("start_stock_main");
		if (result.ok) pid = 303;
		return result;
	}
	OperationResult verify_stock_main(int, const std::string &) override
	{
		return call("verify_stock_main");
	}
	bool exit_requested() override
	{
		calls.push_back("exit_requested");
		return cancel;
	}

	bool called(const std::string &operation) const
	{
		return std::find(calls.begin(), calls.end(), operation) != calls.end();
	}
	bool called_before(const std::string &first, const std::string &second) const
	{
		const auto first_call = std::find(calls.begin(), calls.end(), first);
		const auto second_call = std::find(calls.begin(), calls.end(), second);
		return first_call != calls.end() && second_call != calls.end() &&
			first_call < second_call;
	}
	std::size_t call_count(const std::string &operation) const
	{
		return static_cast<std::size_t>(std::count(calls.begin(), calls.end(),
			operation));
	}

	std::vector<std::string> calls;
	std::string fail_operation;
	std::string cancel_after;
	bool cancel = false;
	bool exit_initial_on_load = true;
	bool initial_modified_alive = false;
	bool modified_alive = false;
	bool controller_alive = true;
	bool controller_complete = false;
	bool controller_exec_success = true;
	std::string controller_exit_state = "EXIT_CODE_1";
	std::string controller_stderr = "PLAYLIST FAILED";
	std::string status_scenario = "READY";
	int status_probe_count = 0;
	ControllerDiagnostics controller_diagnostic;
	bool startup_successor_available = true;
	bool successor_sha_valid = true;
	bool successor_rbf_argument = true;
	bool runtime_successor_available = false;
	int reacquire_count = 0;
	int last_reacquire_previous_pid = -1;
	int last_reacquired_pid = -1;
	int verified_core_pid = -1;
	std::uint64_t now_ms = 0;
	std::vector<std::vector<int>> drain_scan_sequence;
	std::size_t drain_scan_position = 0;
	std::vector<int> stopped_modified_pids;
	std::uint64_t unmount_at_ms = 0;
	std::string verified_playlist;
	std::string verified_start_file;
	std::string verified_playlist_snapshot;
	std::string started_playlist;
	std::string started_start_file;
	std::string started_playlist_snapshot;
};

void expect_restored(const Supervisor &supervisor)
{
	assert(supervisor.snapshot().mode == "STOCK");
	assert(supervisor.snapshot().main == "STOCK");
	assert(supervisor.snapshot().controller == "STOPPED");
}

void test_successful_enter()
{
	FakeRuntime runtime;
	RecordingPublisher publisher;
	Supervisor supervisor(runtime, publisher);
	assert(supervisor.enter("/music").ok);
	assert(supervisor.active());
	assert(supervisor.snapshot().mode == "MEGAVGM");
	assert(supervisor.snapshot().main == "MODIFIED");
	assert(supervisor.snapshot().controller == "RUNNING");
	assert(supervisor.snapshot().controller_pid == "202");
	assert(supervisor.snapshot().controller_exec == "SUCCESS");
	assert(supervisor.snapshot().megavgm_status_at_controller_launch == "YES");
	assert(supervisor.snapshot().playlist_command_seen == "YES");
	assert(supervisor.snapshot().playlist_status_seen == "YES");
	assert(supervisor.snapshot().active_main_sha256 == "modified-hash");
	assert(supervisor.snapshot().active_rbf_argv == "/fixed/playlist.rbf");
	assert(supervisor.snapshot().controller_trace.find(
		"INITIAL_FPGA_SESSION=82") != std::string::npos);
	assert(supervisor.snapshot().main_load_file.find(
		"phase=TRANSFER_SUCCESS") != std::string::npos);
}

void test_transport_m5_modified_main_is_the_only_default_allowed_hash()
{
	const Paths paths;
	assert(paths.expected_modified_sha256 ==
		"a0e7b7d3557457a80ecd62a6bb4643585c33b78fbe515a7a7a5783b05b5addb5");
}

void test_prerequisite_failure_does_not_stop_stock_main()
{
	FakeRuntime runtime;
	runtime.fail_operation = "verify_inputs";
	RecordingPublisher publisher;
	Supervisor supervisor(runtime, publisher);
	const OperationResult result = supervisor.enter("/music");
	assert(!result.ok);
	assert(runtime.calls.size() == 1);
	assert(runtime.calls.front() == "verify_inputs");
	assert(supervisor.snapshot().mode == "FAILURE");
	assert(supervisor.snapshot().main == "UNKNOWN");
	assert(supervisor.snapshot().controller == "UNKNOWN");
	assert(supervisor.snapshot().modified_main_path == "/fixed/MiSTer.megavgm");
	assert(supervisor.snapshot().modified_main_size == "1063652");
	assert(supervisor.snapshot().modified_main_sha_expected == "modified-hash");
	assert(supervisor.snapshot().modified_main_sha_actual == "modified-hash");
	assert(supervisor.snapshot().modified_main_sha256_file_success == "YES");
	assert(supervisor.snapshot().modified_main_sha_errno == "0");
	assert(supervisor.snapshot().detail.find(
		"stock Main was not stopped") != std::string::npos);
}

void test_selected_file_is_only_forwarded_to_controller()
{
	FakeRuntime runtime;
	RecordingPublisher publisher;
	Supervisor supervisor(runtime, publisher);
	const std::string directory = "/music/Album";
	const std::string selected = directory + "/03 Selected.vgm";
	assert(supervisor.enter(directory, selected).ok);
	assert(runtime.verified_playlist == directory);
	assert(runtime.verified_start_file == selected);
	assert(runtime.started_playlist == directory);
	assert(runtime.started_start_file == selected);
	assert(supervisor.snapshot().playlist == directory);
}

void test_initial_playlist_snapshot_is_forwarded_without_directory_fallback()
{
	FakeRuntime runtime;
	RecordingPublisher publisher;
	Supervisor supervisor(runtime, publisher);
	const std::string directory = "/music/Album";
	const std::string snapshot = "/tmp/megavgm_playlist.snapshot-cold";
	assert(supervisor.enter(directory, {}, snapshot).ok);
	assert(runtime.verified_playlist == directory);
	assert(runtime.verified_start_file.empty());
	assert(runtime.verified_playlist_snapshot == snapshot);
	assert(runtime.started_playlist == directory);
	assert(runtime.started_start_file.empty());
	assert(runtime.started_playlist_snapshot == snapshot);
}

void test_status_absent_then_ready_before_controller_start()
{
	FakeRuntime runtime;
	runtime.status_scenario = "ABSENT_THEN_READY";
	RecordingPublisher publisher;
	Supervisor supervisor(runtime, publisher);
	assert(supervisor.enter("/music").ok);
	assert(runtime.status_probe_count == 2);
	assert(runtime.called("start_playlist"));
	assert(supervisor.snapshot().megavgm_status_at_controller_launch == "YES");
}

void test_status_never_ready_rolls_back()
{
	FakeRuntime runtime;
	runtime.status_scenario = "NEVER";
	RecordingPublisher publisher;
	Supervisor supervisor(runtime, publisher);
	assert(!supervisor.enter("/music").ok);
	expect_restored(supervisor);
	assert(!runtime.called("start_playlist"));
}

void test_malformed_status_rolls_back()
{
	FakeRuntime runtime;
	runtime.status_scenario = "MALFORMED";
	RecordingPublisher publisher;
	Supervisor supervisor(runtime, publisher);
	assert(!supervisor.enter("/music").ok);
	expect_restored(supervisor);
	assert(!runtime.called("start_playlist"));
}

void test_controller_exec_failure_rolls_back_with_diagnostics()
{
	FakeRuntime runtime;
	runtime.controller_exec_success = false;
	RecordingPublisher publisher;
	Supervisor supervisor(runtime, publisher);
	assert(!supervisor.enter("/music").ok);
	expect_restored(supervisor);
	assert(supervisor.snapshot().controller_pid == "202");
	assert(supervisor.snapshot().controller_exec == "FAILED:ENOENT");
	assert(supervisor.snapshot().controller_exit == "EXIT_CODE_127");
	assert(supervisor.snapshot().controller_stderr == "exec: ENOENT");
}

void test_modified_main_pid_replacement_during_core_load()
{
	FakeRuntime runtime;
	RecordingPublisher publisher;
	Supervisor supervisor(runtime, publisher);
	assert(supervisor.enter("/music").ok);
	assert(runtime.last_reacquire_previous_pid == 101);
	assert(!runtime.initial_modified_alive);
	assert(runtime.last_reacquired_pid == 102);
	assert(runtime.successor_sha_valid);
	assert(runtime.successor_rbf_argument);
	assert(runtime.verified_core_pid == 102);
	assert(supervisor.active());
}

void test_modified_main_pid_replacement_without_successor()
{
	FakeRuntime runtime;
	runtime.startup_successor_available = false;
	RecordingPublisher publisher;
	Supervisor supervisor(runtime, publisher);
	assert(!supervisor.enter("/music").ok);
	expect_restored(supervisor);
	assert(runtime.called("modified_main_processes"));
	assert(runtime.called("unmount_modified_main"));
	assert(runtime.called_before("modified_main_processes",
		"unmount_modified_main"));
	assert(runtime.called("start_stock_main"));
}

void test_modified_main_pid_replacement_rejects_invalid_successor()
{
	for (int invalid = 0; invalid != 2; ++invalid) {
		FakeRuntime runtime;
		if (invalid == 0) runtime.successor_sha_valid = false;
		else runtime.successor_rbf_argument = false;
		RecordingPublisher publisher;
		Supervisor supervisor(runtime, publisher);
		assert(!supervisor.enter("/music").ok);
		expect_restored(supervisor);
		assert(runtime.called("modified_main_processes"));
	}
}

void test_successful_exit()
{
	FakeRuntime runtime;
	RecordingPublisher publisher;
	Supervisor supervisor(runtime, publisher);
	assert(supervisor.enter("/music").ok);
	assert(supervisor.exit().ok);
	expect_restored(supervisor);
	assert(runtime.called("stop_playlist"));
	assert(runtime.called("stop_modified_main"));
	assert(runtime.called("unmount_modified_main"));
	assert(runtime.called_before("stop_modified_main",
		"unmount_modified_main"));
	assert(runtime.called("verify_stock_main"));
}

void expect_enter_failure_restores(const std::string &operation)
{
	FakeRuntime runtime;
	runtime.fail_operation = operation;
	RecordingPublisher publisher;
	Supervisor supervisor(runtime, publisher);
	assert(!supervisor.enter("/music").ok);
	expect_restored(supervisor);
	assert(runtime.called("start_stock_main"));
	assert(runtime.called("verify_stock_main"));
}

void test_modified_main_fails_to_start()
{
	expect_enter_failure_restores("start_modified_main");
}

void test_rbf_load_fails()
{
	expect_enter_failure_restores("load_rbf");
}

void test_playlist_fails_to_start()
{
	FakeRuntime runtime;
	runtime.fail_operation = "start_playlist";
	RecordingPublisher publisher;
	Supervisor supervisor(runtime, publisher);
	assert(!supervisor.enter("/music").ok);
	expect_restored(supervisor);
	assert(runtime.called("cleanup_playlist_state"));
}

void test_modified_main_dies()
{
	FakeRuntime runtime;
	RecordingPublisher publisher;
	Supervisor supervisor(runtime, publisher);
	assert(supervisor.enter("/music").ok);
	runtime.modified_alive = false;
	assert(!supervisor.monitor_once().ok);
	expect_restored(supervisor);
}

void test_playlist_controller_dies()
{
	FakeRuntime runtime;
	RecordingPublisher publisher;
	Supervisor supervisor(runtime, publisher);
	assert(supervisor.enter("/music").ok);
	runtime.controller_alive = false;
	assert(!supervisor.monitor_once().ok);
	expect_restored(supervisor);
	assert(supervisor.snapshot().detail.find("playlist controller exited unexpectedly") !=
		std::string::npos);
	assert(supervisor.snapshot().controller_exit == "EXIT_CODE_1");
	assert(supervisor.snapshot().controller_stderr == "PLAYLIST FAILED");
}

void test_playlist_normal_complete_restores_stock()
{
	FakeRuntime runtime;
	RecordingPublisher publisher;
	Supervisor supervisor(runtime, publisher);
	assert(supervisor.enter("/music").ok);
	runtime.controller_complete = true;
	runtime.controller_alive = false;
	assert(supervisor.monitor_once().ok);
	expect_restored(supervisor);
	assert(!supervisor.active());
	assert(supervisor.snapshot().detail.find("playlist completed normally") !=
		std::string::npos);
}

void test_modified_main_drain_catches_late_successor()
{
	FakeRuntime runtime;
	RecordingPublisher publisher;
	Supervisor supervisor(runtime, publisher);
	assert(supervisor.enter("/music").ok);
	runtime.drain_scan_sequence = {
		{102}, {}, {}, {}, {}, {}, {103}, {}, {}, {}, {}, {}, {}, {}, {}, {},
		{}, {}, {}, {}, {}, {}, {}
	};
	assert(supervisor.exit().ok);
	expect_restored(supervisor);
	assert(std::find(runtime.stopped_modified_pids.begin(),
		runtime.stopped_modified_pids.end(), 102) !=
		runtime.stopped_modified_pids.end());
	assert(std::find(runtime.stopped_modified_pids.begin(),
		runtime.stopped_modified_pids.end(), 103) !=
		runtime.stopped_modified_pids.end());
	assert(runtime.now_ms >= 2200);
	assert(runtime.unmount_at_ms >= 2200);
	assert(runtime.called_before("stop_modified_main", "unmount_modified_main"));
}

void test_exit_races_with_normal_complete()
{
	FakeRuntime runtime;
	RecordingPublisher publisher;
	Supervisor supervisor(runtime, publisher);
	assert(supervisor.enter("/music").ok);
	runtime.controller_complete = true;
	runtime.controller_alive = false;
	runtime.cancel = true;
	assert(supervisor.monitor_once().ok);
	expect_restored(supervisor);
	assert(!supervisor.active());
	assert(runtime.call_count("unmount_modified_main") == 1);
	assert(runtime.call_count("start_stock_main") == 1);
}

void test_exit_while_partially_initialized()
{
	FakeRuntime runtime;
	runtime.cancel_after = "bind_modified_main";
	RecordingPublisher publisher;
	Supervisor supervisor(runtime, publisher);
	assert(!supervisor.enter("/music").ok);
	expect_restored(supervisor);
	assert(!runtime.called("start_modified_main"));
}

std::string temporary_directory()
{
	char path[] = "/tmp/megavgm_supervisor_test.XXXXXX";
	char *created = mkdtemp(path);
	assert(created != nullptr);
	return created;
}

void test_duplicate_supervisor_invocation()
{
	const std::string directory = temporary_directory();
	const std::string lock_path = directory + "/lock";
	InstanceLock first;
	InstanceLock second;
	assert(first.acquire(lock_path).ok);
	const OperationResult duplicate = second.acquire(lock_path);
	assert(!duplicate.ok);
	assert(duplicate.detail == "ALREADY_RUNNING");
	unlink(lock_path.c_str());
	rmdir(directory.c_str());
}

void test_stale_lock_and_status_recovery()
{
	const std::string directory = temporary_directory();
	const std::string lock_path = directory + "/lock";
	const std::string status_path = directory + "/status";
	{
		std::ofstream stale_lock(lock_path);
		stale_lock << "99999\n";
		std::ofstream stale_status(status_path);
		stale_status << "mode=MEGAVGM\nold=true\n";
	}
	InstanceLock lock;
	assert(lock.acquire(lock_path).ok);
	AtomicStatusPublisher publisher(status_path);
	Snapshot snapshot;
	snapshot.mode = "STARTING";
	snapshot.main = "STOCK";
	snapshot.controller = "STOPPED";
	snapshot.controller_trace = "INITIAL_FPGA_SESSION=82";
	snapshot.main_load_file = "phase=TRANSFER_SUCCESS";
	assert(publisher.publish(snapshot).ok);
	std::string content;
	std::string detail;
	assert(megavgm_supervisor::read_text_file(status_path, content, detail));
	assert(content.find("mode=STARTING\n") != std::string::npos);
	assert(content.find("controller_trace=INITIAL_FPGA_SESSION=82\n") !=
		std::string::npos);
	assert(content.find("main_load_file=phase=TRANSFER_SUCCESS\n") !=
		std::string::npos);
	assert(content.find("old=true") == std::string::npos);
	unlink(status_path.c_str());
	unlink(lock_path.c_str());
	rmdir(directory.c_str());
}

void test_exit_control_socket()
{
	const std::string directory = temporary_directory();
	const std::string socket_path = directory + "/control.sock";
	{
		megavgm_supervisor::ControlServer server;
		const OperationResult opened = server.open(socket_path);
		if (!opened.ok) std::cerr << "control socket open: " << opened.detail << '\n';
		assert(opened.ok);
		assert(!server.exit_requested());
		assert(megavgm_supervisor::send_exit_request(socket_path).ok);
		assert(server.exit_requested());
	}
	rmdir(directory.c_str());
}

void test_exit_classifies_missing_socket_during_restore()
{
	const std::string directory = temporary_directory();
	const std::string socket_path = directory + "/missing.sock";
	const std::string status_path = directory + "/status";
	{
		std::ofstream status(status_path);
		status << "mode=SHUTTING_DOWN\nmain=MODIFIED\ncontroller=STOPPED\n";
	}
	OperationResult result = megavgm_supervisor::request_exit_or_classify(
		socket_path, status_path);
	assert(result.ok);
	assert(result.detail == "RESTORE_IN_PROGRESS");
	{
		std::ofstream status(status_path);
		status << "mode=STOCK\nmain=STOCK\ncontroller=STOPPED\n";
	}
	result = megavgm_supervisor::request_exit_or_classify(socket_path,
		status_path);
	assert(result.ok);
	assert(result.detail == "ALREADY_STOPPED");
	unlink(status_path.c_str());
	rmdir(directory.c_str());
}

void test_failed_unmount_skips_stock_verification()
{
	FakeRuntime runtime;
	RecordingPublisher publisher;
	Supervisor supervisor(runtime, publisher);
	assert(supervisor.enter("/music").ok);
	runtime.fail_operation = "unmount_modified_main";
	assert(!supervisor.exit().ok);
	assert(supervisor.snapshot().mode == "FAILURE");
	assert(supervisor.snapshot().main == "RESTORE_FAILED");
	assert(!runtime.called("verify_stock_path"));
	assert(!runtime.called("start_stock_main"));
}

void test_stock_restore_verification_mismatch()
{
	FakeRuntime runtime;
	RecordingPublisher publisher;
	Supervisor supervisor(runtime, publisher);
	assert(supervisor.enter("/music").ok);
	runtime.fail_operation = "verify_stock_path";
	assert(!supervisor.exit().ok);
	assert(supervisor.snapshot().mode == "FAILURE");
	assert(supervisor.snapshot().main == "RESTORE_FAILED");
	assert(!runtime.called("start_stock_main"));
}

void test_sha256_implementation()
{
	const std::string directory = temporary_directory();
	const std::string abc_path = directory + "/abc";
	{
		std::ofstream file(abc_path, std::ios::binary);
		file << "abc";
	}
	std::string digest;
	std::string detail;
	int error_number = -1;
	assert(megavgm_supervisor::sha256_file(abc_path, digest, detail,
		&error_number));
	assert(digest == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
	assert(error_number == 0);
	unlink(abc_path.c_str());

	struct Vector {
		std::size_t size;
		const char *digest;
	};
	const Vector vectors[] = {
		{0, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"},
		{1, "6e340b9cffb37a989ca544e6bb780a2c78901d3fb33738768511a30617afa01d"},
		{55, "463eb28e72f82e0a96c0a4cc53690c571281131f672aa229e0d45ae59b598b59"},
		{56, "da2ae4d6b36748f2a318f23e7ab1dfdf45acdc9d049bd80e59de82a60895f562"},
		{63, "29af2686fd53374a36b0846694cc342177e428d1647515f078784d69cdb9e488"},
		{64, "fdeab9acf3710362bd2658cdc9a29e8f9c757fcf9811603a8c447cd1d9151108"},
		{65, "4bfd2c8b6f1eec7a2afeb48b934ee4b2694182027e6d0fc075074f2fabb31781"},
		{119, "da18797ed7c3a777f0847f429724a2d8cd5138e6ed2895c3fa1a6d39d18f7ec6"},
		{120, "f52b23db1fbb6ded89ef42a23ce0c8922c45f25c50b568a93bf1c075420bbb7c"},
		{127, "92ca0fa6651ee2f97b884b7246a562fa71250fedefe5ebf270d31c546bfea976"},
		{128, "471fb943aa23c511f6f72f8d1652d9c880cfa392ad80503120547703e56a2be5"},
		{129, "5099c6a56203f9687f7d33f4bfdf576d31dc91f6b695ecea38b2770c87631135"},
		{1063652,
			"2360cd5c8e2346f961db483a500daf66b6468cbf4c5d39766e2e4756306e048e"},
	};
	for (const Vector &vector : vectors) {
		const std::string path = directory + "/vector-" +
			std::to_string(vector.size);
		std::ofstream file(path, std::ios::binary);
		std::array<char, 4096> buffer = {{}};
		std::size_t offset = 0;
		while (offset < vector.size) {
			const std::size_t amount = std::min(buffer.size(),
				vector.size - offset);
			for (std::size_t i = 0; i < amount; ++i)
				buffer[i] = static_cast<char>((offset + i) & 0xff);
			file.write(buffer.data(), static_cast<std::streamsize>(amount));
			offset += amount;
		}
		file.close();
		assert(file.good());
		assert(megavgm_supervisor::sha256_file(path, digest, detail,
			&error_number));
		assert(digest == vector.digest);
		assert(error_number == 0);
		unlink(path.c_str());
	}

	const char *m5_main = std::getenv("MEGAVGM_TEST_MAIN_PATH");
	if (m5_main && *m5_main) {
		struct stat attributes = {};
		assert(stat(m5_main, &attributes) == 0);
		assert(attributes.st_size == 1063652);
		assert(megavgm_supervisor::sha256_file(m5_main, digest, detail,
			&error_number));
		assert(digest ==
			"a0e7b7d3557457a80ecd62a6bb4643585c33b78fbe515a7a7a5783b05b5addb5");
		assert(error_number == 0);
	}
	rmdir(directory.c_str());
}

void test_fixed_test_profile_selection()
{
	using megavgm_supervisor::apply_test_profile;
	using megavgm_supervisor::set_test_profile;
	const std::string directory = temporary_directory();
	Paths paths;
	paths.supervisor_lock = directory + "/lock";
	paths.supervisor_status = directory + "/status";
	paths.test_profile_directory = directory + "/selection";
	const std::string default_rbf = paths.rbf;
	assert(apply_test_profile(paths).ok && paths.rbf == default_rbf);
	assert(!set_test_profile(paths, "../../bad.rbf").ok);
	assert(set_test_profile(paths, "ym2610b-phase1b").ok);
	Paths chosen = paths;
	assert(apply_test_profile(chosen).ok);
	assert(chosen.rbf_profile == "YM2610B_PHASE1B");
	assert(chosen.rbf == "/media/fat/MegaVGMPlayer/MegaVGMPlayer_GoldenTransport12Phase1B_YM2610B_MiSTer.rbf");
	assert(chosen.expected_modified_sha256 == paths.expected_modified_sha256);
	assert(chosen.playlist_binary == paths.playlist_binary);
#ifdef MEGAVGM_PHASE2A
	assert(set_test_profile(paths, "phase2a").ok);
	Paths automatic = paths;
	assert(apply_test_profile(automatic).ok && automatic.phase2a);
	assert(automatic.rbf_profile == "PHASE2A_AUTO");
	assert(automatic.playlist_binary == "/media/fat/MegaVGMPlayer/megavgm_playlist-phase2a");
	assert(automatic.expected_modified_sha256 == paths.expected_modified_sha256);
	{
		InstanceLock owner;
		assert(owner.acquire(paths.supervisor_lock).ok);
		assert(!set_test_profile(paths, "phase2a").ok);
	}
	assert(set_test_profile(paths, "ym2610b-phase1b").ok);
#endif
	// The same snapshot must pass through unchanged for either fixed resident.
	std::vector<std::string> default_calls;
	for (const Paths &profile : {paths, chosen}) {
		FakeRuntime runtime;
		RecordingPublisher publisher;
		Supervisor supervisor(runtime, publisher, profile.rbf_profile);
		assert(supervisor.enter("/music", {}, "/tmp/snapshot").ok);
		assert(runtime.verified_playlist_snapshot == "/tmp/snapshot");
		assert(runtime.verified_start_file.empty());
		assert(supervisor.snapshot().rbf == profile.rbf_profile);
		assert(supervisor.exit().ok);
		if (default_calls.empty()) default_calls = runtime.calls;
		else assert(default_calls == runtime.calls); // identical lifecycle and restore
	}
	{
		InstanceLock owner;
		assert(owner.acquire(paths.supervisor_lock).ok);
		assert(!set_test_profile(paths, "default").ok);
		assert(!set_test_profile(paths, "ym2610b-phase1b").ok);
	}
	std::ofstream(paths.supervisor_status) << "mode=STARTING\nmain=MODIFIED\ncontroller=STOPPED\n";
	assert(!set_test_profile(paths, "default").ok);
	std::ofstream(paths.supervisor_status) << "mode=STOCK\nmain=STOCK\ncontroller=STOPPED\n";
	// Atomic-write failure must retain the previous selection.
	const std::string temporary = paths.test_profile_directory + "/.profile." + std::to_string(getpid());
	std::ofstream(temporary) << "occupied";
	assert(!set_test_profile(paths, "ym2610b-phase1b").ok);
	chosen = paths; assert(apply_test_profile(chosen).ok && chosen.rbf_profile == "YM2610B_PHASE1B");
	unlink(temporary.c_str());
	const std::string marker = paths.test_profile_directory + "/profile";
	std::ofstream(marker) << "unknown\n";
	chosen = paths; assert(!apply_test_profile(chosen).ok);
	unlink(marker.c_str());
	assert(symlink(paths.supervisor_status.c_str(), marker.c_str()) == 0);
	chosen = paths; assert(!apply_test_profile(chosen).ok);
	unlink(marker.c_str());
	assert(set_test_profile(paths, "ym2610b-phase1b").ok);
	assert(chmod(paths.test_profile_directory.c_str(), 0777) == 0);
	chosen = paths; assert(!apply_test_profile(chosen).ok);
	assert(chmod(paths.test_profile_directory.c_str(), 0700) == 0);
	assert(set_test_profile(paths, "default").ok);
	assert(set_test_profile(paths, "default").ok);
	chosen = paths; assert(apply_test_profile(chosen).ok && chosen.rbf == default_rbf);
	rmdir(paths.test_profile_directory.c_str());
	unlink(paths.supervisor_status.c_str()); unlink(paths.supervisor_lock.c_str()); rmdir(directory.c_str());
}

void test_fade_only_test_profiles()
{
	using megavgm_supervisor::apply_test_profile;
	using megavgm_supervisor::set_test_profile;
	const std::string directory = temporary_directory();
	Paths paths;
	paths.supervisor_lock = directory + "/lock";
	paths.supervisor_status = directory + "/status";
	paths.test_profile_directory = directory + "/selection";
	const std::string marker = paths.test_profile_directory + "/profile";
	struct Profile { const char *name; const char *label; const char *rbf; };
	const Profile profiles[] = {
		{"fade-only-a", "FADE_ONLY_A", "/media/fat/_Utility/MegaVGMPlayer_Transport13FadeOnly_A_MiSTer.rbf"},
		{"fade-only-b", "FADE_ONLY_B", "/media/fat/_Utility/MegaVGMPlayer_Transport13FadeOnly_B_MiSTer.rbf"},
	};
	std::vector<std::string> lifecycle;
	for (const auto &profile : profiles) {
		std::ofstream(paths.supervisor_status) << "mode=STOCK\nmain=STOCK\ncontroller=STOPPED\n";
		assert(set_test_profile(paths, profile.name).ok);
		assert(set_test_profile(paths, profile.name).ok); // idempotent while STOCK
		Paths chosen = paths;
		assert(apply_test_profile(chosen).ok);
		assert(chosen.rbf == profile.rbf && chosen.rbf_profile == profile.label);
		assert(chosen.modified_main == "/media/fat/MegaVGMPlayer/MiSTer.megavgm");
		assert(chosen.expected_modified_sha256 == "a0e7b7d3557457a80ecd62a6bb4643585c33b78fbe515a7a7a5783b05b5addb5");
		assert(chosen.playlist_binary == paths.playlist_binary);
		assert(chosen.main_command == paths.main_command && chosen.megavgm_status == paths.megavgm_status);
		assert(chosen.main_load_file_status == paths.main_load_file_status);
		// Both resident test RBFs take the unchanged strict-Main/snapshot/restore path.
		FakeRuntime runtime;
		RecordingPublisher publisher;
		Supervisor supervisor(runtime, publisher, chosen.rbf_profile);
		assert(supervisor.enter("/music", {}, "/tmp/snapshot").ok);
		assert(runtime.verified_playlist_snapshot == "/tmp/snapshot");
		assert(runtime.verified_start_file.empty());
		assert(supervisor.snapshot().rbf == profile.label);
		assert(supervisor.exit().ok);
		if (lifecycle.empty()) lifecycle = runtime.calls;
		else assert(lifecycle == runtime.calls);
		{
			InstanceLock owner;
			assert(owner.acquire(paths.supervisor_lock).ok);
			for (const auto *name : {"default", "ym2610b-phase1b", "fade-only-a", "fade-only-b"})
				assert(!set_test_profile(paths, name).ok);
		}
		for (const auto *state : {"STARTING", "MEGAVGM", "STOPPING", "FAILURE"}) {
			std::ofstream(paths.supervisor_status) << "mode=" << state << "\nmain=MODIFIED\ncontroller=RUNNING\n";
			for (const auto *name : {"default", "ym2610b-phase1b", "fade-only-a", "fade-only-b"})
				assert(!set_test_profile(paths, name).ok);
			chosen = paths;
			assert(apply_test_profile(chosen).ok && chosen.rbf == profile.rbf);
		}
		std::ofstream(paths.supervisor_status) << "mode=STOCK\nmain=STOCK\ncontroller=STOPPED\n";
		assert(!set_test_profile(paths, "fade-only-a/../../bad").ok);
		const std::string temporary = paths.test_profile_directory + "/.profile." + std::to_string(getpid());
		std::ofstream(temporary) << "occupied";
		assert(!set_test_profile(paths, profile.name).ok);
		chosen = paths;
		assert(apply_test_profile(chosen).ok && chosen.rbf == profile.rbf);
		unlink(temporary.c_str());
		assert(set_test_profile(paths, "default").ok);
		chosen = paths;
		assert(apply_test_profile(chosen).ok && chosen.rbf == paths.rbf && chosen.rbf_profile == paths.rbf_profile);
	}
	assert(set_test_profile(paths, "fade-only-a").ok);
	for (const auto *record : {"fade-only-a", "fade-only-a\nextra\n", "fade-only-b\r\n"}) {
		std::ofstream(marker) << record;
		Paths chosen = paths;
		assert(!apply_test_profile(chosen).ok && chosen.rbf == paths.rbf);
	}
	assert(set_test_profile(paths, "default").ok);
	rmdir(paths.test_profile_directory.c_str());
	unlink(paths.supervisor_status.c_str()); unlink(paths.supervisor_lock.c_str()); rmdir(directory.c_str());
	std::cout << "FADE_ONLY_PROFILES paths/strict-Main/STOCK-lock/lifecycle/snapshot/default/invalid-record: PASS\n";
}

} // namespace

void test_phase2a_parked_controller_switch()
{
	FakeRuntime runtime;
	RecordingPublisher publisher;
	Supervisor supervisor(runtime, publisher);
	assert(supervisor.enter("/music", {}, "/tmp/snapshot").ok);
	runtime.runtime_successor_available = true;
	assert(supervisor.switch_test_rbf("/test/B.rbf", "PROFILE_B").ok);
	assert(supervisor.active() && supervisor.snapshot().rbf == "PROFILE_B");
	assert(runtime.call_count("start_playlist") == 1);
	assert(runtime.call_count("stop_playlist") == 0);
	assert(runtime.call_count("bind_modified_main") == 1);
	assert(runtime.call_count("unmount_modified_main") == 0);
	assert(runtime.call_count("load_rbf") == 2);
	assert(runtime.call_count("verify_modified_main") == 2);
	assert(runtime.call_count("verify_megavgm_core") == 2);
	assert(supervisor.modified_pid() == 103);
	assert(supervisor.exit().ok);
	expect_restored(supervisor);
	assert(runtime.call_count("stop_playlist") == 1);
	std::cout << "PHASE2A parked controller/drain/successor/SHA/stock restore: PASS\n";
}

int main()
{
	test_phase2a_parked_controller_switch();
	test_fixed_test_profile_selection();
	test_fade_only_test_profiles();
	test_transport_m5_modified_main_is_the_only_default_allowed_hash();
	test_prerequisite_failure_does_not_stop_stock_main();
	test_successful_enter();
	test_selected_file_is_only_forwarded_to_controller();
	test_initial_playlist_snapshot_is_forwarded_without_directory_fallback();
	test_status_absent_then_ready_before_controller_start();
	test_status_never_ready_rolls_back();
	test_malformed_status_rolls_back();
	test_controller_exec_failure_rolls_back_with_diagnostics();
	test_modified_main_pid_replacement_during_core_load();
	test_modified_main_pid_replacement_without_successor();
	test_modified_main_pid_replacement_rejects_invalid_successor();
	test_successful_exit();
	test_modified_main_fails_to_start();
	test_rbf_load_fails();
	test_playlist_fails_to_start();
	test_modified_main_dies();
	test_playlist_controller_dies();
	test_playlist_normal_complete_restores_stock();
	test_modified_main_drain_catches_late_successor();
	test_exit_races_with_normal_complete();
	test_duplicate_supervisor_invocation();
	test_exit_while_partially_initialized();
	test_stale_lock_and_status_recovery();
	test_exit_control_socket();
	test_exit_classifies_missing_socket_during_restore();
	test_failed_unmount_skips_stock_verification();
	test_stock_restore_verification_mismatch();
	test_sha256_implementation();
	std::cout << "megavgm_supervisor host tests: PASS\n";
	return 0;
}
