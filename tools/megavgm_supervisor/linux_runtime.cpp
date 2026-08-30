#include "linux_runtime.h"

#include "sha256.h"

#include <algorithm>
#include <cerrno>
#include <csignal>
#include <cstdlib>
#include <cstring>
#include <dirent.h>
#include <fcntl.h>
#include <fstream>
#include <sstream>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#ifdef __linux__
#include <sys/mount.h>
#endif

namespace megavgm_supervisor {
namespace {

bool decimal_name(const char *text)
{
	if (!text || !*text) return false;
	for (const unsigned char *p =
		reinterpret_cast<const unsigned char *>(text); *p; ++p)
		if (*p < '0' || *p > '9') return false;
	return true;
}

std::string proc_path(int pid, const char *leaf)
{
	return "/proc/" + std::to_string(pid) + "/" + leaf;
}

bool same_file(const std::string &left, const std::string &right)
{
	struct stat a = {};
	struct stat b = {};
	return stat(left.c_str(), &a) == 0 && stat(right.c_str(), &b) == 0 &&
		a.st_dev == b.st_dev && a.st_ino == b.st_ino;
}

std::string trim(std::string value)
{
	while (!value.empty() &&
		(value.back() == '\n' || value.back() == '\r' || value.back() == ' '))
		value.pop_back();
	return value;
}

} // namespace

LinuxRuntime::LinuxRuntime(Paths paths, ControlServer &control)
	: paths_(std::move(paths)), control_(control)
{
}

OperationResult LinuxRuntime::verify_regular_executable(const std::string &path)
{
	struct stat attributes = {};
	if (lstat(path.c_str(), &attributes) < 0)
		return OperationResult::failure(path + ": " + std::strerror(errno));
	if (!S_ISREG(attributes.st_mode))
		return OperationResult::failure(path + ": not a regular file");
	if ((attributes.st_mode & 0111) == 0)
		return OperationResult::failure(path + ": not executable");
	return OperationResult::success();
}

OperationResult LinuxRuntime::verify_regular_file(const std::string &path)
{
	struct stat attributes = {};
	if (lstat(path.c_str(), &attributes) < 0)
		return OperationResult::failure(path + ": " + std::strerror(errno));
	if (!S_ISREG(attributes.st_mode))
		return OperationResult::failure(path + ": not a regular file");
	return OperationResult::success();
}

bool LinuxRuntime::is_mountpoint(const std::string &path, std::string &detail)
{
	std::ifstream mountinfo("/proc/self/mountinfo");
	if (!mountinfo) {
		detail = "cannot read /proc/self/mountinfo";
		return false;
	}
	std::string line;
	while (std::getline(mountinfo, line)) {
		std::istringstream fields(line);
		std::string id, parent, device, root, mountpoint;
		if (fields >> id >> parent >> device >> root >> mountpoint &&
			mountpoint == path) {
			detail.clear();
			return true;
		}
	}
	detail.clear();
	return false;
}

bool LinuxRuntime::process_uses_file(const std::string &path)
{
	DIR *directory = opendir("/proc");
	if (!directory) return false;
	bool found = false;
	while (struct dirent *entry = readdir(directory)) {
		if (!decimal_name(entry->d_name)) continue;
		const std::string executable =
			std::string("/proc/") + entry->d_name + "/exe";
		if (same_file(path, executable)) {
			found = true;
			break;
		}
	}
	closedir(directory);
	return found;
}

bool LinuxRuntime::process_has_open_file(const std::string &path)
{
	struct stat target = {};
	if (stat(path.c_str(), &target) < 0) return false;
	DIR *processes = opendir("/proc");
	if (!processes) return false;
	bool found = false;
	while (!found) {
		struct dirent *process = readdir(processes);
		if (!process) break;
		if (!decimal_name(process->d_name)) continue;
		const std::string fd_path =
			std::string("/proc/") + process->d_name + "/fd";
		DIR *descriptors = opendir(fd_path.c_str());
		if (!descriptors) continue;
		while (struct dirent *descriptor = readdir(descriptors)) {
			if (!decimal_name(descriptor->d_name)) continue;
			struct stat opened = {};
			const std::string opened_path = fd_path + "/" + descriptor->d_name;
			if (stat(opened_path.c_str(), &opened) == 0 &&
				opened.st_dev == target.st_dev && opened.st_ino == target.st_ino) {
				found = true;
				break;
			}
		}
		closedir(descriptors);
	}
	closedir(processes);
	return found;
}

OperationResult LinuxRuntime::verify_inputs(const std::string &playlist,
	VerifiedInputs &inputs)
{
	if (geteuid() != 0) return OperationResult::failure("root privileges required");
	if (playlist.empty() || playlist.size() > 4096 ||
		playlist.find('\n') != std::string::npos ||
		playlist.find('\r') != std::string::npos)
		return OperationResult::failure("invalid playlist directory");
	struct stat directory = {};
	if (stat(playlist.c_str(), &directory) < 0 || !S_ISDIR(directory.st_mode))
		return OperationResult::failure("playlist directory is unavailable");

	for (const std::string &path : {paths_.stock_main, paths_.modified_main,
		paths_.playlist_binary}) {
		OperationResult result = verify_regular_executable(path);
		if (!result.ok) return result;
	}
	OperationResult result = verify_regular_file(paths_.rbf);
	if (!result.ok) return result;
	std::string mount_detail;
	if (is_mountpoint(paths_.stock_main, mount_detail))
		return OperationResult::failure("unexpected existing Main bind mount");
	if (!mount_detail.empty()) return OperationResult::failure(mount_detail);
	if (process_uses_file(paths_.playlist_binary))
		return OperationResult::failure("playlist controller is already running");

	struct stat control = {};
	const int control_result = lstat(paths_.playlist_command.c_str(), &control);
	if (control_result == 0 && !S_ISFIFO(control.st_mode))
		return OperationResult::failure("playlist control path is not a FIFO");
	if (control_result < 0 && errno != ENOENT)
		return OperationResult::failure(std::strerror(errno));
	if (control_result == 0 && process_has_open_file(paths_.playlist_command))
		return OperationResult::failure("playlist control FIFO is already owned");

	std::string detail;
	if (!sha256_file(paths_.stock_main, inputs.stock_sha256, detail))
		return OperationResult::failure("stock Main hash failed: " + detail);
	if (!sha256_file(paths_.modified_main, inputs.modified_sha256, detail))
		return OperationResult::failure("modified Main hash failed: " + detail);
	if (inputs.modified_sha256 != paths_.expected_modified_sha256)
		return OperationResult::failure("modified Main SHA-256 mismatch");
	return OperationResult::success();
}

int LinuxRuntime::find_main_by_sha256(const std::string &sha256,
	std::string &detail)
{
	const std::vector<int> matches = find_mains_by_sha256(sha256, false);
	if (matches.size() != 1) {
		detail = matches.empty() ? "verified Main process not found" :
			"multiple verified Main processes found";
		return -1;
	}
	detail.clear();
	return matches.front();
}

bool LinuxRuntime::process_has_argument(int pid, const std::string &argument)
{
	std::string command_line;
	std::string detail;
	if (!read_text_file(proc_path(pid, "cmdline"), command_line, detail, 16384))
		return false;
	std::size_t offset = 0;
	while (offset < command_line.size()) {
		const std::size_t end = command_line.find('\0', offset);
		const std::size_t length = end == std::string::npos ?
			command_line.size() - offset : end - offset;
		if (command_line.compare(offset, length, argument) == 0) return true;
		if (end == std::string::npos) break;
		offset = end + 1;
	}
	return false;
}

std::vector<int> LinuxRuntime::find_mains_by_sha256(const std::string &sha256,
	bool require_rbf_argument)
{
	DIR *directory = opendir("/proc");
	if (!directory) return {};
	std::vector<int> matches;
	while (struct dirent *entry = readdir(directory)) {
		if (!decimal_name(entry->d_name)) continue;
		const int pid = std::atoi(entry->d_name);
		std::string comm;
		std::string ignored;
		if (!read_text_file(proc_path(pid, "comm"), comm, ignored, 64) ||
			trim(comm) != "MiSTer") continue;
		if (require_rbf_argument && !process_has_argument(pid, paths_.rbf))
			continue;
		std::string digest;
		if (sha256_file(proc_path(pid, "exe"), digest, ignored) && digest == sha256)
			matches.push_back(pid);
	}
	closedir(directory);
	return matches;
}

std::vector<int> LinuxRuntime::find_mains_using_file(const std::string &path)
{
	DIR *directory = opendir("/proc");
	if (!directory) return {};
	std::vector<int> matches;
	while (struct dirent *entry = readdir(directory)) {
		if (!decimal_name(entry->d_name)) continue;
		const int pid = std::atoi(entry->d_name);
		std::string comm;
		std::string ignored;
		if (!read_text_file(proc_path(pid, "comm"), comm, ignored, 64) ||
			trim(comm) != "MiSTer") continue;
		if (same_file(path, proc_path(pid, "exe"))) matches.push_back(pid);
	}
	closedir(directory);
	return matches;
}

bool LinuxRuntime::process_alive(int pid)
{
	if (pid <= 0 || kill(pid, 0) < 0) return false;
	std::string stat_line;
	std::string detail;
	if (!read_text_file(proc_path(pid, "stat"), stat_line, detail, 4096)) return false;
	const std::size_t close = stat_line.rfind(')');
	return close != std::string::npos && close + 2 < stat_line.size() &&
		stat_line[close + 2] != 'Z';
}

bool LinuxRuntime::wait_for(const std::function<bool()> &condition,
	int timeout_ms)
{
	for (int elapsed = 0; elapsed <= timeout_ms; elapsed += 100) {
		if (condition()) return true;
		if (control_.exit_requested()) return false;
		usleep(100000);
	}
	return false;
}

OperationResult LinuxRuntime::stop_process(int pid, const std::string &name)
{
	if (!process_alive(pid)) {
		while (waitpid(pid, nullptr, WNOHANG) > 0) {}
		return OperationResult::success();
	}
	if (kill(pid, SIGTERM) < 0 && errno != ESRCH)
		return OperationResult::failure(name + " SIGTERM: " + std::strerror(errno));
	if (!wait_for([&]() { return !process_alive(pid); }, 3000)) {
		if (kill(pid, SIGKILL) < 0 && errno != ESRCH)
			return OperationResult::failure(name + " SIGKILL: " + std::strerror(errno));
		if (!wait_for([&]() { return !process_alive(pid); }, 2000))
			return OperationResult::failure(name + " did not stop");
	}
	while (waitpid(pid, nullptr, WNOHANG) > 0) {}
	return OperationResult::success();
}

OperationResult LinuxRuntime::stop_stock_main(const std::string &stock_sha256)
{
	std::string detail;
	const int pid = find_main_by_sha256(stock_sha256, detail);
	if (pid < 0) return OperationResult::failure(detail);
	return stop_process(pid, "stock Main");
}

OperationResult LinuxRuntime::bind_modified_main()
{
#ifdef __linux__
	if (mount(paths_.modified_main.c_str(), paths_.stock_main.c_str(), nullptr,
		MS_BIND, nullptr) < 0)
		return OperationResult::failure(std::strerror(errno));
	return OperationResult::success();
#else
	return OperationResult::failure("bind mounts require Linux");
#endif
}

OperationResult LinuxRuntime::launch_main(int &pid)
{
	pid = fork();
	if (pid < 0) return OperationResult::failure(std::strerror(errno));
	if (pid == 0) {
		if (chdir("/") < 0) _exit(126);
		const int input = open("/dev/null", O_RDONLY);
		const int console = open("/dev/console", O_WRONLY);
		if (input < 0 || console < 0 || dup2(input, STDIN_FILENO) < 0 ||
			dup2(console, STDOUT_FILENO) < 0 || dup2(console, STDERR_FILENO) < 0)
			_exit(126);
		if (input > STDERR_FILENO) close(input);
		if (console > STDERR_FILENO) close(console);
		char *const arguments[] = {
			const_cast<char *>(paths_.stock_main.c_str()), nullptr};
		char shell[] = "SHELL=/bin/sh";
		char pwd[] = "PWD=/";
		char home[] = "HOME=/";
		char term[] = "TERM=vt102";
		char user[] = "USER=root";
		char path[] = "PATH=/sbin:/usr/sbin:/bin:/usr/bin";
		char *const environment[] = {shell, pwd, home, term, user, path, nullptr};
		execve(paths_.stock_main.c_str(), arguments, environment);
		_exit(127);
	}
	return OperationResult::success();
}

OperationResult LinuxRuntime::start_modified_main(int &pid)
{
	return launch_main(pid);
}

OperationResult LinuxRuntime::verify_process(int pid,
	const std::string &expected_sha256, const std::string &name)
{
	if (!wait_for([&]() { return process_alive(pid); }, 1000))
		return OperationResult::failure(name + " did not remain alive");
	usleep(1000000);
	if (!process_alive(pid)) return OperationResult::failure(name + " exited during stabilization");
	char executable[4096] = {};
	const ssize_t length = readlink(proc_path(pid, "exe").c_str(), executable,
		sizeof(executable) - 1);
	if (length <= 0) return OperationResult::failure(name + " executable path unavailable");
	const std::string executable_path(executable, static_cast<std::size_t>(length));
	if (executable_path != paths_.stock_main &&
		executable_path != paths_.modified_main)
		return OperationResult::failure(name + " executable path mismatch");
	std::string digest;
	std::string detail;
	if (!sha256_file(proc_path(pid, "exe"), digest, detail))
		return OperationResult::failure(name + " executable hash failed: " + detail);
	if (digest != expected_sha256)
		return OperationResult::failure(name + " executable SHA-256 mismatch");
	return OperationResult::success();
}

OperationResult LinuxRuntime::verify_modified_main(int pid,
	const std::string &modified_sha256)
{
	return verify_process(pid, modified_sha256, "modified Main");
}

OperationResult LinuxRuntime::reacquire_modified_main(int previous_pid,
	const std::string &modified_sha256, int &current_pid)
{
	current_pid = -1;
	const bool found = wait_for([&]() {
		std::vector<int> matches = find_mains_by_sha256(modified_sha256, true);
		matches.erase(std::remove(matches.begin(), matches.end(), previous_pid),
			matches.end());
		if (matches.size() != 1) return false;
		current_pid = matches.front();
		return true;
	}, 10000);
	if (!found)
		return OperationResult::failure(
			"no unique SHA-verified Main successor with requested RBF argv");
	OperationResult verified = verify_process(current_pid, modified_sha256,
		"successor modified Main");
	if (!verified.ok) return verified;
	if (!process_has_argument(current_pid, paths_.rbf))
		return OperationResult::failure("successor Main lost requested RBF argv");
	return OperationResult::success();
}

OperationResult LinuxRuntime::load_rbf()
{
	for (const std::string &path : {paths_.core_name, paths_.megavgm_status}) {
		struct stat attributes = {};
		if (lstat(path.c_str(), &attributes) == 0) {
			if (!S_ISREG(attributes.st_mode))
				return OperationResult::failure(path + ": not a regular file");
			if (unlink(path.c_str()) < 0)
				return OperationResult::failure(std::strerror(errno));
		} else if (errno != ENOENT) {
			return OperationResult::failure(std::strerror(errno));
		}
	}
	const std::string command = "load_core " + paths_.rbf + "\n";
	int command_fd = -1;
	if (!wait_for([&]() {
		command_fd = open(paths_.main_command.c_str(),
			O_WRONLY | O_NONBLOCK | O_CLOEXEC);
		return command_fd >= 0;
	}, 5000)) return OperationResult::failure("Main command FIFO unavailable");
	struct stat attributes = {};
	if (fstat(command_fd, &attributes) < 0 || !S_ISFIFO(attributes.st_mode)) {
		close(command_fd);
		return OperationResult::failure("Main command path is not a FIFO");
	}
	std::size_t offset = 0;
	while (offset < command.size()) {
		const ssize_t bytes = write(command_fd, command.data() + offset,
			command.size() - offset);
		if (bytes > 0) offset += static_cast<std::size_t>(bytes);
		else if (bytes < 0 && errno == EINTR) continue;
		else {
			const std::string detail = std::strerror(errno);
			close(command_fd);
			return OperationResult::failure(detail);
		}
	}
	close(command_fd);
	return OperationResult::success();
}

OperationResult LinuxRuntime::verify_megavgm_core(int &modified_pid,
	const std::string &modified_sha256)
{
	const bool active = wait_for([&]() {
		if (!process_alive(modified_pid) ||
			!process_has_argument(modified_pid, paths_.rbf)) {
			const std::vector<int> matches =
				find_mains_by_sha256(modified_sha256, true);
			if (matches.size() != 1) return false;
			modified_pid = matches.front();
		}
		std::string name;
		std::string detail;
		if (!read_text_file(paths_.core_name, name, detail, 256)) return false;
		name = trim(name);
		if (name != "MegaVGMPlayer" && name != "MegaVGMDrive") return false;
		std::string status;
		if (!read_text_file(paths_.megavgm_status, status, detail, 4096))
			return false;
		return status.find("version=") != std::string::npos &&
			status.find("session=") != std::string::npos &&
			status.find("state=") != std::string::npos;
	}, 10000);
	return active ? OperationResult::success() :
		OperationResult::failure(
			"verified successor Main and MegaVGMPlayer CORENAME/status not observed");
}

OperationResult LinuxRuntime::remove_controller_path(const std::string &path,
	bool fifo_required)
{
	struct stat attributes = {};
	if (lstat(path.c_str(), &attributes) < 0) {
		if (errno == ENOENT) return OperationResult::success();
		return OperationResult::failure(std::strerror(errno));
	}
	if (fifo_required && !S_ISFIFO(attributes.st_mode))
		return OperationResult::failure(path + ": expected FIFO");
	if (!fifo_required && !S_ISREG(attributes.st_mode))
		return OperationResult::failure(path + ": expected regular file");
	if (unlink(path.c_str()) < 0) return OperationResult::failure(std::strerror(errno));
	return OperationResult::success();
}

OperationResult LinuxRuntime::launch_playlist(const std::string &directory,
	int &pid)
{
	pid = fork();
	if (pid < 0) return OperationResult::failure(std::strerror(errno));
	if (pid == 0) {
		if (chdir("/") < 0) _exit(126);
		const int input = open("/dev/null", O_RDONLY);
		const int console = open("/dev/console", O_WRONLY);
		if (input < 0 || console < 0 || dup2(input, STDIN_FILENO) < 0 ||
			dup2(console, STDOUT_FILENO) < 0 || dup2(console, STDERR_FILENO) < 0)
			_exit(126);
		if (input > STDERR_FILENO) close(input);
		if (console > STDERR_FILENO) close(console);
		char loops[] = "--loops";
		char count[] = "2";
		char *const arguments[] = {
			const_cast<char *>(paths_.playlist_binary.c_str()), loops, count,
			const_cast<char *>(directory.c_str()), nullptr};
		execv(paths_.playlist_binary.c_str(), arguments);
		_exit(127);
	}
	return OperationResult::success();
}

OperationResult LinuxRuntime::start_playlist(const std::string &directory,
	int &pid)
{
	OperationResult result = remove_controller_path(paths_.playlist_command, true);
	if (!result.ok) return result;
	result = remove_controller_path(paths_.playlist_status, false);
	if (!result.ok) return result;
	return launch_playlist(directory, pid);
}

OperationResult LinuxRuntime::verify_playlist(int pid)
{
	bool died = false;
	const bool ready = wait_for([&]() {
		if (!process_alive(pid)) {
			died = true;
			return true;
		}
		struct stat command = {};
		struct stat status = {};
		if (lstat(paths_.playlist_command.c_str(), &command) < 0 ||
			!S_ISFIFO(command.st_mode) ||
			lstat(paths_.playlist_status.c_str(), &status) < 0 ||
			!S_ISREG(status.st_mode)) return false;
		std::string content;
		std::string detail;
		return read_text_file(paths_.playlist_status, content, detail) &&
			content.find("state=") != std::string::npos &&
			content.find("session=") != std::string::npos;
	}, 10000);
	if (died) return OperationResult::failure("playlist controller exited during startup");
	return ready ? OperationResult::success() :
		OperationResult::failure("playlist FIFO/status did not appear");
}

OperationResult LinuxRuntime::stop_playlist(int pid)
{
	return stop_process(pid, "playlist controller");
}

OperationResult LinuxRuntime::cleanup_playlist_state()
{
	OperationResult command = remove_controller_path(paths_.playlist_command, true);
	OperationResult status = remove_controller_path(paths_.playlist_status, false);
	if (!command.ok) return command;
	return status;
}

OperationResult LinuxRuntime::stop_modified_main(int pid)
{
	return stop_process(pid, "modified Main");
}

OperationResult LinuxRuntime::stop_all_modified_mains(
	const std::string &modified_sha256)
{
	std::string last_failure;
	for (int round = 0; round != 4; ++round) {
		std::vector<int> matches = find_mains_by_sha256(modified_sha256, false);
		const std::vector<int> bound = find_mains_using_file(paths_.stock_main);
		matches.insert(matches.end(), bound.begin(), bound.end());
		std::sort(matches.begin(), matches.end());
		matches.erase(std::unique(matches.begin(), matches.end()), matches.end());
		if (matches.empty()) return OperationResult::success();
		for (int pid : matches) {
			const OperationResult stopped = stop_process(pid, "modified Main");
			if (!stopped.ok) last_failure = stopped.detail;
		}
	}
	std::vector<int> remaining = find_mains_by_sha256(modified_sha256, false);
	const std::vector<int> bound = find_mains_using_file(paths_.stock_main);
	remaining.insert(remaining.end(), bound.begin(), bound.end());
	std::sort(remaining.begin(), remaining.end());
	remaining.erase(std::unique(remaining.begin(), remaining.end()),
		remaining.end());
	if (remaining.empty()) return OperationResult::success();
	return OperationResult::failure(last_failure.empty() ?
		"verified modified Main processes remain alive" : last_failure);
}

OperationResult LinuxRuntime::unmount_modified_main()
{
#ifdef __linux__
	if (umount(paths_.stock_main.c_str()) < 0)
		return OperationResult::failure(std::strerror(errno));
	std::string detail;
	if (is_mountpoint(paths_.stock_main, detail))
		return OperationResult::failure("Main bind mount remains active");
	return detail.empty() ? OperationResult::success() :
		OperationResult::failure(detail);
#else
	return OperationResult::failure("unmount requires Linux");
#endif
}

OperationResult LinuxRuntime::verify_stock_path(const std::string &stock_sha256)
{
	std::string digest;
	std::string detail;
	if (!sha256_file(paths_.stock_main, digest, detail))
		return OperationResult::failure("stock Main hash failed: " + detail);
	if (digest != stock_sha256)
		return OperationResult::failure("stock Main SHA-256 mismatch after unmount");
	return OperationResult::success();
}

OperationResult LinuxRuntime::start_stock_main(int &pid)
{
	return launch_main(pid);
}

OperationResult LinuxRuntime::verify_stock_main(int pid,
	const std::string &stock_sha256)
{
	return verify_process(pid, stock_sha256, "stock Main");
}

bool LinuxRuntime::exit_requested()
{
	return control_.exit_requested();
}

} // namespace megavgm_supervisor
