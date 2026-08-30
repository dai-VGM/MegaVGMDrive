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

	OperationResult verify_inputs(const std::string &, VerifiedInputs &inputs) override
	{
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
		if (result.ok) pid = 101;
		return result;
	}
	OperationResult verify_modified_main(int, const std::string &) override
	{
		return call("verify_modified_main");
	}
	OperationResult load_rbf() override { return call("load_rbf"); }
	OperationResult verify_megavgm_core(int) override
	{
		return call("verify_megavgm_core");
	}
	OperationResult start_playlist(const std::string &, int &pid) override
	{
		OperationResult result = call("start_playlist");
		if (result.ok) pid = 202;
		return result;
	}
	OperationResult verify_playlist(int) override
	{
		return call("verify_playlist");
	}
	bool process_alive(int pid) override
	{
		calls.push_back(pid == 101 ? "modified_alive" : "controller_alive");
		return pid == 101 ? modified_alive : controller_alive;
	}
	OperationResult stop_playlist(int) override { return call("stop_playlist"); }
	OperationResult cleanup_playlist_state() override
	{
		return call("cleanup_playlist_state");
	}
	OperationResult stop_modified_main(int) override
	{
		return call("stop_modified_main");
	}
	OperationResult unmount_modified_main() override
	{
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

	std::vector<std::string> calls;
	std::string fail_operation;
	std::string cancel_after;
	bool cancel = false;
	bool modified_alive = true;
	bool controller_alive = true;
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
	assert(publisher.publish(snapshot).ok);
	std::string content;
	std::string detail;
	assert(megavgm_supervisor::read_text_file(status_path, content, detail));
	assert(content.find("mode=STARTING\n") != std::string::npos);
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
	test_successful_exit();
	test_modified_main_fails_to_start();
	test_rbf_load_fails();
	test_playlist_fails_to_start();
	test_modified_main_dies();
	test_playlist_controller_dies();
	test_duplicate_supervisor_invocation();
	test_exit_while_partially_initialized();
	test_stale_lock_and_status_recovery();
	test_exit_control_socket();
	test_stock_restore_verification_mismatch();
	test_sha256_implementation();
	std::cout << "megavgm_supervisor host tests: PASS\n";
	return 0;
}
