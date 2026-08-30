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

Supervisor::Supervisor(Runtime &runtime, StatusPublisher &publisher)
	: runtime_(runtime), publisher_(publisher)
{
}

OperationResult Supervisor::publish()
{
	return publisher_.publish(snapshot_);
}

OperationResult Supervisor::check_exit_request()
{
	if (!runtime_.exit_requested()) return OperationResult::success();
	return OperationResult::failure("exit requested during initialization");
}

OperationResult Supervisor::enter(const std::string &playlist)
{
	snapshot_ = Snapshot{};
	snapshot_.mode = "STARTING";
	snapshot_.main = "STOCK";
	snapshot_.playlist = playlist;
	snapshot_.detail = "verifying prerequisites";
	OperationResult result = publish();
	if (!result.ok) return result;

	VerifiedInputs inputs;
	result = runtime_.verify_inputs(playlist, inputs);
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
	result = runtime_.verify_megavgm_core(modified_pid_);
	if (!result.ok) return rollback("MegaVGM core verification failed: " + result.detail);
	result = check_exit_request();
	if (!result.ok) return rollback(result.detail);

	snapshot_.detail = "starting playlist controller";
	result = publish();
	if (!result.ok) return rollback("status publication failed: " + result.detail);
	controller_state_touched_ = true;
	result = runtime_.start_playlist(playlist, controller_pid_);
	if (!result.ok) return rollback("playlist start failed: " + result.detail);
	controller_started_ = true;
	result = runtime_.verify_playlist(controller_pid_);
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

OperationResult Supervisor::rollback(const std::string &reason)
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
		remember_failure(failures, "stop playlist",
			runtime_.stop_playlist(controller_pid_));
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
	if (modified_started_) {
		const OperationResult stopped = runtime_.stop_modified_main(modified_pid_);
		remember_failure(failures, "stop modified Main", stopped);
		modified_stopped = stopped.ok || !runtime_.process_alive(modified_pid_);
		if (!modified_stopped)
			failures.push_back("modified Main remains alive; bind retained");
		modified_started_ = !modified_stopped;
		if (modified_stopped) modified_pid_ = -1;
	}
	if (bind_mounted_ && modified_stopped) {
		const OperationResult unmounted = runtime_.unmount_modified_main();
		remember_failure(failures, "unmount modified Main", unmounted);
		if (unmounted.ok) bind_mounted_ = false;
	}

	bool stock_restored = false;
	if (stock_stopped_ && modified_stopped) {
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
	if (reason == "explicit exit") return OperationResult::success();
	return OperationResult::failure(reason + "; stock Main restored");
}

OperationResult Supervisor::exit(const std::string &reason)
{
	return rollback(reason);
}

OperationResult Supervisor::monitor_once()
{
	if (!active_) return OperationResult::failure("supervisor is not active");
	if (!runtime_.process_alive(modified_pid_))
		return rollback("modified Main exited unexpectedly");
	if (!runtime_.process_alive(controller_pid_))
		return rollback("playlist controller exited unexpectedly");
	if (runtime_.exit_requested()) return rollback("explicit exit");
	return OperationResult::success();
}

} // namespace megavgm_supervisor
