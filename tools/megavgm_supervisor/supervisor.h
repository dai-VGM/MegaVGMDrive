#pragma once

#include <cstdint>
#include <functional>
#include <string>
#include <vector>

namespace megavgm_supervisor {

struct OperationResult {
	bool ok = false;
	std::string detail;

	static OperationResult success();
	static OperationResult failure(const std::string &detail);
};

struct VerifiedInputs {
	std::string stock_sha256;
	std::string modified_sha256;
};

struct Snapshot {
	std::string mode = "STOCK";
	std::string main = "STOCK";
	std::string controller = "STOPPED";
	std::string rbf = "YM2151_SEGAPCM";
	std::string playlist;
	std::string stock_sha256;
	std::string modified_sha256;
	std::string detail;
};

class StatusPublisher {
public:
	virtual ~StatusPublisher() = default;
	virtual OperationResult publish(const Snapshot &snapshot) = 0;
};

class Runtime {
public:
	virtual ~Runtime() = default;

	virtual OperationResult verify_inputs(const std::string &playlist,
		VerifiedInputs &inputs) = 0;
	virtual OperationResult stop_stock_main(const std::string &stock_sha256) = 0;
	virtual OperationResult bind_modified_main() = 0;
	virtual OperationResult start_modified_main(int &pid) = 0;
	virtual OperationResult verify_modified_main(int pid,
		const std::string &modified_sha256) = 0;
	virtual OperationResult load_rbf() = 0;
	virtual OperationResult reacquire_modified_main(int previous_pid,
		const std::string &modified_sha256, int &current_pid) = 0;
	virtual OperationResult verify_megavgm_core(int &modified_pid,
		const std::string &modified_sha256) = 0;
	virtual OperationResult start_playlist(const std::string &directory,
		int &pid) = 0;
	virtual OperationResult verify_playlist(int pid) = 0;
	virtual bool process_alive(int pid) = 0;
	virtual bool playlist_complete() = 0;
	virtual OperationResult stop_playlist(int pid) = 0;
	virtual OperationResult cleanup_playlist_state() = 0;
	virtual OperationResult stop_modified_main(int pid) = 0;
	virtual std::vector<int> modified_main_processes(
		const std::string &modified_sha256) = 0;
	virtual std::uint64_t monotonic_ms() = 0;
	virtual void sleep_ms(unsigned int milliseconds) = 0;
	virtual OperationResult unmount_modified_main() = 0;
	virtual OperationResult verify_stock_path(const std::string &stock_sha256) = 0;
	virtual OperationResult start_stock_main(int &pid) = 0;
	virtual OperationResult verify_stock_main(int pid,
		const std::string &stock_sha256) = 0;
	virtual bool exit_requested() = 0;
};

class Supervisor {
public:
	Supervisor(Runtime &runtime, StatusPublisher &publisher);

	OperationResult enter(const std::string &playlist);
	OperationResult exit(const std::string &reason = "explicit exit");
	OperationResult monitor_once();
	bool active() const { return active_; }
	const Snapshot &snapshot() const { return snapshot_; }

private:
	OperationResult check_exit_request();
	OperationResult rollback(const std::string &reason,
		bool orderly_restore = false);
	OperationResult drain_modified_mains();
	OperationResult publish();
	void remember_failure(std::vector<std::string> &failures,
		const std::string &operation, const OperationResult &result);

	Runtime &runtime_;
	StatusPublisher &publisher_;
	Snapshot snapshot_;
	bool stock_stopped_ = false;
	bool bind_mounted_ = false;
	bool modified_started_ = false;
	bool controller_state_touched_ = false;
	bool controller_started_ = false;
	bool active_ = false;
	int modified_pid_ = -1;
	int controller_pid_ = -1;
};

} // namespace megavgm_supervisor
