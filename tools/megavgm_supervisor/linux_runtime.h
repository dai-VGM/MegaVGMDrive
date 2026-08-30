#pragma once

#include "runtime_support.h"

#include <string>
#include <vector>

namespace megavgm_supervisor {

struct Paths {
	std::string stock_main = "/media/fat/MiSTer";
	std::string modified_main = "/media/fat/MegaVGMPlayer/MiSTer.megavgm";
	std::string rbf = "/media/fat/MegaVGMPlayer/MegaVGMPlayer_PlaylistLoopLab_MiSTer.rbf";
	std::string playlist_binary = "/media/fat/Scripts/megavgm_playlist";
	std::string main_command = "/dev/MiSTer_cmd";
	std::string core_name = "/tmp/CORENAME";
	std::string megavgm_status = "/tmp/MegaVGMPlayer.status";
	std::string playlist_command = "/tmp/megavgm_playlist.cmd";
	std::string playlist_status = "/tmp/megavgm_playlist.status";
	std::string playlist_stderr = "/tmp/megavgm_playlist.stderr";
	std::string playlist_trace = "/tmp/megavgm_playlist.trace";
	std::string main_load_file_status = "/tmp/megavgm_load_file.status";
	std::string supervisor_lock = "/tmp/megavgm_supervisor.lock";
	std::string supervisor_socket = "/tmp/megavgm_supervisor.sock";
	std::string supervisor_status = "/tmp/megavgm_supervisor.status";
	std::string supervisor_log = "/tmp/megavgm_supervisor.log";
	std::string expected_modified_sha256 =
		"f06631728cbe8dd89aab6886d179bbaa1d51186ba07b75fb6d719fdffd5fcdda";
};

class LinuxRuntime : public Runtime {
public:
	LinuxRuntime(Paths paths, ControlServer &control);

	OperationResult verify_inputs(const std::string &playlist,
		VerifiedInputs &inputs) override;
	OperationResult stop_stock_main(const std::string &stock_sha256) override;
	OperationResult bind_modified_main() override;
	OperationResult start_modified_main(int &pid) override;
	OperationResult verify_modified_main(int pid,
		const std::string &modified_sha256) override;
	OperationResult load_rbf() override;
	OperationResult reacquire_modified_main(int previous_pid,
		const std::string &modified_sha256, int &current_pid) override;
	OperationResult verify_megavgm_core(int &modified_pid,
		const std::string &modified_sha256) override;
	OperationResult start_playlist(const std::string &directory,
		int &pid) override;
	OperationResult verify_playlist(int pid) override;
	ControllerDiagnostics controller_diagnostics(int controller_pid,
		int modified_pid) override;
	bool process_alive(int pid) override;
	bool playlist_complete() override;
	OperationResult stop_playlist(int pid) override;
	OperationResult cleanup_playlist_state() override;
	OperationResult stop_modified_main(int pid) override;
	std::vector<int> modified_main_processes(
		const std::string &modified_sha256) override;
	std::uint64_t monotonic_ms() override;
	void sleep_ms(unsigned int milliseconds) override;
	OperationResult unmount_modified_main() override;
	OperationResult verify_stock_path(const std::string &stock_sha256) override;
	OperationResult start_stock_main(int &pid) override;
	OperationResult verify_stock_main(int pid,
		const std::string &stock_sha256) override;
	bool exit_requested() override;

private:
	OperationResult verify_regular_executable(const std::string &path);
	OperationResult verify_regular_file(const std::string &path);
	OperationResult launch_main(int &pid);
	OperationResult launch_playlist(const std::string &directory, int &pid);
	OperationResult stop_process(int pid, const std::string &name);
	OperationResult verify_process(int pid, const std::string &expected_sha256,
		const std::string &name);
	OperationResult remove_controller_path(const std::string &path,
		bool fifo_required);
	bool is_mountpoint(const std::string &path, std::string &detail);
	int find_main_by_sha256(const std::string &sha256, std::string &detail);
	std::vector<int> find_mains_by_sha256(const std::string &sha256,
		bool require_rbf_argument);
	std::vector<int> find_mains_using_file(const std::string &path);
	bool process_has_argument(int pid, const std::string &argument);
	bool process_uses_file(const std::string &path);
	bool process_has_open_file(const std::string &path);
	bool valid_megavgm_status(std::string &detail);
	void update_controller_exit_status(int controller_pid);
	void update_controller_stderr();
	void update_boundary_diagnostics();
	bool wait_for(const std::function<bool()> &condition, int timeout_ms);

	Paths paths_;
	ControlServer &control_;
	ControllerDiagnostics controller_diagnostics_state_;
};

} // namespace megavgm_supervisor
