#include "supervisor.h"

#include <sstream>

namespace megavgm_supervisor {

OperationResult OperationResult::success()
{
	return {true, {}};
}

OperationResult OperationResult::failure(const std::string &detail)
{
	return {false, detail};
}

Supervisor::Supervisor(Runtime &runtime, StatusPublisher &publisher,
	const std::string &rbf_profile)
	: runtime_(runtime), publisher_(publisher), rbf_profile_(rbf_profile)
{
}

OperationResult Supervisor::publish()
{
	return publisher_.publish(snapshot_);
}

void Supervisor::observe_transport(const TransportObservation &observation)
{
	snapshot_.transport = observation;
	(void)publish();
}

void Supervisor::refresh_controller_diagnostics()
{
	const ControllerDiagnostics diagnostics =
		runtime_.controller_diagnostics(controller_pid_, modified_pid_);
	snapshot_.controller_pid = std::to_string(diagnostics.pid);
	snapshot_.controller_exec = diagnostics.exec_state;
	snapshot_.controller_exit = diagnostics.exit_state;
	snapshot_.controller_stderr = diagnostics.stderr_text;
	snapshot_.controller_trace = diagnostics.trace_text;
	snapshot_.main_load_file = diagnostics.main_load_file_text;
	snapshot_.megavgm_status_at_controller_launch =
		diagnostics.megavgm_status_at_launch ? "YES" : "NO";
	snapshot_.playlist_command_seen = diagnostics.command_fifo_seen ? "YES" : "NO";
	snapshot_.playlist_status_seen = diagnostics.status_seen ? "YES" : "NO";
	snapshot_.active_main_sha256 = diagnostics.active_main_sha256;
	snapshot_.active_rbf_argv = diagnostics.active_rbf_argv;
}

OperationResult Supervisor::check_exit_request()
{
	if (!runtime_.exit_requested()) return OperationResult::success();
	return OperationResult::failure("exit requested during initialization");
}

OperationResult Supervisor::enter(const std::string &playlist,
	const std::string &start_file, const std::string &playlist_snapshot)
{
	snapshot_ = Snapshot{};
	snapshot_.rbf = rbf_profile_;
	snapshot_.mode = "STARTING";
	snapshot_.main = "STOCK";
	snapshot_.playlist = playlist;
	snapshot_.detail = "verifying prerequisites";
	OperationResult result = publish();
	if (!result.ok) return result;

	VerifiedInputs inputs;
	result = runtime_.verify_inputs(playlist, start_file, playlist_snapshot, inputs);
	snapshot_.modified_main_path = inputs.modified_main_path;
	snapshot_.modified_main_size = inputs.modified_main_size;
	snapshot_.modified_main_sha_expected = inputs.modified_main_sha_expected;
	snapshot_.modified_main_sha_actual = inputs.modified_main_sha_actual;
	snapshot_.modified_main_sha256_file_success =
		inputs.modified_main_sha256_file_success;
	snapshot_.modified_main_sha_errno = inputs.modified_main_sha_errno;
	if (!result.ok) return rollback("prerequisite verification failed: " + result.detail);
	snapshot_.stock_sha256 = inputs.stock_sha256;
	snapshot_.modified_sha256 = inputs.modified_sha256;
	result = check_exit_request();
	if (!result.ok) return rollback(result.detail);

	snapshot_.detail = "stopping stock Main";
	result = publish();
	if (!result.ok) return rollback("status publication failed: " + result.detail);
	result = runtime_.stop_stock_main(inputs.stock_sha256);
	if (!result.ok) return rollback("stock Main stop failed: " + result.detail);
	stock_stopped_ = true;
	snapshot_.main = "STOPPED";
	result = check_exit_request();
	if (!result.ok) return rollback(result.detail);

	snapshot_.detail = "binding modified Main";
	result = publish();
	if (!result.ok) return rollback("status publication failed: " + result.detail);
	result = runtime_.bind_modified_main();
	if (!result.ok) return rollback("modified Main bind failed: " + result.detail);
	bind_mounted_ = true;
	result = check_exit_request();
	if (!result.ok) return rollback(result.detail);

	snapshot_.detail = "starting modified Main";
	result = publish();
	if (!result.ok) return rollback("status publication failed: " + result.detail);
	result = runtime_.start_modified_main(modified_pid_);
	if (!result.ok) return rollback("modified Main start failed: " + result.detail);
	modified_started_ = true;
	result = runtime_.verify_modified_main(modified_pid_, inputs.modified_sha256);
	if (!result.ok) return rollback("modified Main verification failed: " + result.detail);
	snapshot_.main = "MODIFIED";
	result = check_exit_request();
	if (!result.ok) return rollback(result.detail);

	snapshot_.detail = "loading fixed MegaVGMPlayer RBF";
	result = publish();
	if (!result.ok) return rollback("status publication failed: " + result.detail);
	result = runtime_.load_rbf();
	if (!result.ok) return rollback("RBF load failed: " + result.detail);
	int successor_pid = -1;
	result = runtime_.reacquire_modified_main(modified_pid_,
		inputs.modified_sha256, successor_pid);
	if (!result.ok)
		return rollback("modified Main successor verification failed: " +
			result.detail);
	modified_pid_ = successor_pid;
	result = runtime_.verify_megavgm_core(modified_pid_,
		inputs.modified_sha256);
	if (!result.ok) return rollback("MegaVGM core verification failed: " + result.detail);
	result = check_exit_request();
	if (!result.ok) return rollback(result.detail);

	snapshot_.detail = "starting playlist controller";
	result = publish();
	if (!result.ok) return rollback("status publication failed: " + result.detail);
	controller_state_touched_ = true;
	result = runtime_.start_playlist(playlist, start_file, playlist_snapshot,
		controller_pid_);
	refresh_controller_diagnostics();
	if (!result.ok) return rollback("playlist start failed: " + result.detail);
	controller_started_ = true;
	result = runtime_.verify_playlist(controller_pid_);
	refresh_controller_diagnostics();
	if (!result.ok) return rollback("playlist verification failed: " + result.detail);
	result = check_exit_request();
	if (!result.ok) return rollback(result.detail);

	active_ = true;
	snapshot_.mode = "MEGAVGM";
	snapshot_.main = "MODIFIED";
	snapshot_.controller = "RUNNING";
	snapshot_.detail = "MEGAVGM MODE ACTIVE";
	result = publish();
	if (!result.ok) return rollback("active status publication failed: " + result.detail);
	return OperationResult::success();
}

void Supervisor::remember_failure(std::vector<std::string> &failures,
	const std::string &operation, const OperationResult &result)
{
	if (!result.ok) failures.push_back(operation + ": " + result.detail);
}

OperationResult Supervisor::switch_test_rbf(const std::string &path, const std::string &profile)
{
	if (!active_ || !controller_started_ || !bind_mounted_)
		return OperationResult::failure("switch requires active parked controller");
	auto result = runtime_.select_test_rbf(path, profile);
	if (!result.ok) return result;
	snapshot_.detail = "PHASE2A: parked controller; switching resident RBF";
	result = publish();
	if (result.ok) result = check_exit_request();
	if (result.ok) result = drain_modified_mains();
	if (result.ok) result = check_exit_request();
	if (result.ok) result = runtime_.start_modified_main(modified_pid_);
	if (result.ok) result = runtime_.verify_modified_main(modified_pid_, snapshot_.modified_sha256);
	if (result.ok) result = runtime_.load_rbf();
	int successor = -1;
	if (result.ok) result = runtime_.reacquire_modified_main(modified_pid_, snapshot_.modified_sha256, successor);
	if (result.ok) modified_pid_ = successor;
	if (result.ok) result = runtime_.verify_megavgm_core(modified_pid_, snapshot_.modified_sha256);
	if (result.ok) result = check_exit_request();
	if (!result.ok) return rollback("PHASE2A RBF switch failed: " + result.detail);
	snapshot_.rbf = profile;
	snapshot_.detail = "PHASE2A: fresh Main/RBF ready; controller still parked";
	refresh_controller_diagnostics();
	return publish();
}

OperationResult Supervisor::drain_modified_mains()
{
	constexpr std::uint64_t kDrainTimeoutMs = 30000;
	constexpr std::uint64_t kStableZeroMs = 1500;
	constexpr unsigned int kPollMs = 100;
	const std::uint64_t deadline = runtime_.monotonic_ms() + kDrainTimeoutMs;
	std::uint64_t zero_since = 0;
	bool zero_window_active = false;
	std::string last_failure;

	while (runtime_.monotonic_ms() <= deadline) {
		const std::vector<int> processes =
			runtime_.modified_main_processes(snapshot_.modified_sha256);
		if (!processes.empty()) {
			zero_window_active = false;
			for (int pid : processes) {
				const OperationResult stopped = runtime_.stop_modified_main(pid);
				if (!stopped.ok) last_failure = stopped.detail;
			}
		} else {
			const std::uint64_t now = runtime_.monotonic_ms();
			if (!zero_window_active) {
				zero_since = now;
				zero_window_active = true;
			}
			if (now - zero_since >= kStableZeroMs)
				return OperationResult::success();
		}
		runtime_.sleep_ms(kPollMs);
	}
	return OperationResult::failure(last_failure.empty() ?
		"modified Main drain did not reach a stable zero-process window" :
		last_failure);
}

OperationResult Supervisor::rollback(const std::string &reason,
	bool orderly_restore)
{
	active_ = false;
	snapshot_.mode = "SHUTTING_DOWN";
	snapshot_.detail = reason;
	publish();
	if (!stock_stopped_) {
		snapshot_.mode = "FAILURE";
		snapshot_.main = "UNKNOWN";
		snapshot_.controller = "UNKNOWN";
		snapshot_.detail = reason + "; stock Main was not stopped";
		publish();
		return OperationResult::failure(snapshot_.detail);
	}

	std::vector<std::string> failures;
	if (controller_started_) {
		const OperationResult stopped = runtime_.stop_playlist(controller_pid_);
		remember_failure(failures, "stop playlist", stopped);
		refresh_controller_diagnostics();
		controller_started_ = false;
		controller_pid_ = -1;
	}
	if (controller_state_touched_) {
		remember_failure(failures, "cleanup playlist state",
			runtime_.cleanup_playlist_state());
		controller_state_touched_ = false;
	}
	snapshot_.controller = "STOPPED";

	bool modified_stopped = true;
	if (modified_started_ || bind_mounted_) {
		const OperationResult stopped = drain_modified_mains();
		remember_failure(failures, "drain modified Main processes", stopped);
		modified_stopped = stopped.ok;
		if (!modified_stopped)
			failures.push_back("verified modified Main remains alive; bind retained");
		modified_started_ = !modified_stopped;
		if (modified_stopped) modified_pid_ = -1;
	}
	if (bind_mounted_ && modified_stopped) {
		const OperationResult unmounted = runtime_.unmount_modified_main();
		remember_failure(failures, "unmount modified Main", unmounted);
		if (unmounted.ok) bind_mounted_ = false;
	}

	bool stock_restored = false;
	if (stock_stopped_ && modified_stopped && !bind_mounted_) {
		OperationResult verify = runtime_.verify_stock_path(snapshot_.stock_sha256);
		remember_failure(failures, "verify restored stock path", verify);
		if (verify.ok) {
			int stock_pid = -1;
			OperationResult start = runtime_.start_stock_main(stock_pid);
			remember_failure(failures, "start stock Main", start);
			if (start.ok) {
				const OperationResult verified = runtime_.verify_stock_main(stock_pid,
					snapshot_.stock_sha256);
				remember_failure(failures, "verify stock Main", verified);
				stock_restored = verified.ok;
				if (!verified.ok)
					remember_failure(failures, "stop unverified Main",
						runtime_.stop_modified_main(stock_pid));
			}
		}
	}

	stock_stopped_ = !stock_restored;
	snapshot_.main = stock_restored ? "STOCK" : "RESTORE_FAILED";
	snapshot_.mode = failures.empty() ? "STOCK" : "FAILURE";
	if (failures.empty()) {
		snapshot_.detail = "STOCK MISTER RESTORED: " + reason;
	} else {
		std::ostringstream detail;
		detail << reason << "; rollback failure";
		for (const std::string &failure : failures) detail << "; " << failure;
		snapshot_.detail = detail.str();
	}
	OperationResult status_result = publish();
	if (!status_result.ok && failures.empty())
		failures.push_back("publish final status: " + status_result.detail);

	if (!failures.empty()) return OperationResult::failure(snapshot_.detail);
	if (orderly_restore) return OperationResult::success();
	return OperationResult::failure(reason + "; stock Main restored");
}

OperationResult Supervisor::exit(const std::string &reason)
{
	return rollback(reason, true);
}

OperationResult Supervisor::monitor_once()
{
	if (!active_) return OperationResult::failure("supervisor is not active");
	if (!runtime_.process_alive(modified_pid_)) {
		int successor_pid = -1;
		const OperationResult successor = runtime_.reacquire_modified_main(
			modified_pid_, snapshot_.modified_sha256, successor_pid);
		if (!successor.ok)
			return rollback("modified Main exited without a verified successor");
		modified_pid_ = successor_pid;
	}
	if (!runtime_.process_alive(controller_pid_)) {
		refresh_controller_diagnostics();
		if (runtime_.playlist_complete())
			return rollback("playlist completed normally", true);
		return rollback("playlist controller exited unexpectedly");
	}
	if (runtime_.exit_requested()) return rollback("explicit exit");
	return OperationResult::success();
}

} // namespace megavgm_supervisor
