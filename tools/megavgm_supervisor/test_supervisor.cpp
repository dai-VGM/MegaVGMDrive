#include "runtime_support.h"
#include "sha256.h"
#include "supervisor.h"

#include <algorithm>
#include <cassert>
#include <fstream>
#include <iostream>
#include <string>
#include <unistd.h>
#include <vector>

using megavgm_supervisor::AtomicStatusPublisher;
using megavgm_supervisor::ControllerDiagnostics;
using megavgm_supervisor::InstanceLock;
using megavgm_supervisor::OperationResult;
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
		const std::string &start_file, VerifiedInputs &inputs) override
	{
		verified_playlist = playlist;
		verified_start_file = start_file;
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
		const std::string &start_file, int &pid) override
	{
		started_playlist = directory;
		started_start_file = start_file;
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
	std::string started_playlist;
	std::string started_start_file;
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
	const std::string path = directory + "/abc";
	{
		std::ofstream file(path, std::ios::binary);
		file << "abc";
	}
	std::string digest;
	std::string detail;
	assert(megavgm_supervisor::sha256_file(path, digest, detail));
	assert(digest == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
	unlink(path.c_str());
	rmdir(directory.c_str());
}

} // namespace

int main()
{
	test_successful_enter();
	test_selected_file_is_only_forwarded_to_controller();
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
