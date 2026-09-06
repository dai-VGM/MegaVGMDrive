#include "linux_runtime.h"
#include "runtime_support.h"
#include "sha256.h"
#include "supervisor.h"
#include "test_profile.h"
#ifdef MEGAVGM_PHASE2A
#include "phase2a.h"
#include <memory>
#endif

#include <cerrno>
#include <csignal>
#include <cstring>
#include <fcntl.h>
#include <iostream>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

namespace {

volatile sig_atomic_t stop_requested = 0;

void request_stop(int)
{
	stop_requested = 1;
}

bool write_message(int fd, const std::string &message)
{
	const char *data = message.data();
	std::size_t size = message.size();
	while (size != 0) {
		const ssize_t written = write(fd, data, size);
		if (written > 0) {
			data += written;
			size -= static_cast<std::size_t>(written);
			continue;
		}
		if (written < 0 && errno == EINTR) continue;
		return false;
	}
	return true;
}

void redirect_supervisor_log(const std::string &path)
{
	const int input = open("/dev/null", O_RDONLY);
	const int log = open(path.c_str(), O_WRONLY | O_CREAT | O_APPEND, 0644);
	if (input >= 0) {
		dup2(input, STDIN_FILENO);
		if (input > STDERR_FILENO) close(input);
	}
	if (log >= 0) {
		dup2(log, STDOUT_FILENO);
		dup2(log, STDERR_FILENO);
		if (log > STDERR_FILENO) close(log);
	}
}

int run_daemon(const megavgm_supervisor::Paths &paths,
	const std::string &playlist, const std::string &start_file,
	const std::string &playlist_snapshot, int notify_fd)
{
	if (setsid() < 0) {
		write_message(notify_fd, "ENTER_FAILED: setsid: " +
			std::string(std::strerror(errno)) + "\n");
		return 1;
	}
	if (chdir("/") < 0) {
		write_message(notify_fd, "ENTER_FAILED: chdir: " +
			std::string(std::strerror(errno)) + "\n");
		return 1;
	}
	umask(022);
	redirect_supervisor_log(paths.supervisor_log);
	signal(SIGTERM, request_stop);
	signal(SIGINT, request_stop);
	signal(SIGHUP, SIG_IGN);

	megavgm_supervisor::ControlServer control;
	megavgm_supervisor::OperationResult result =
		control.open(paths.supervisor_socket);
	if (!result.ok) {
		write_message(notify_fd, "ENTER_FAILED: control socket: " +
			result.detail + "\n");
		return 1;
	}
	megavgm_supervisor::AtomicStatusPublisher publisher(paths.supervisor_status);
	megavgm_supervisor::LinuxRuntime runtime(paths, control);
	megavgm_supervisor::Supervisor supervisor(runtime, publisher, paths.rbf_profile);
	result = supervisor.enter(playlist, start_file, playlist_snapshot);
	if (!result.ok) {
		write_message(notify_fd, "ENTER_FAILED: " + result.detail + "\n");
		close(notify_fd);
		return 1;
	}
	write_message(notify_fd, "MEGAVGM MODE ACTIVE\n");
	close(notify_fd);

#ifdef MEGAVGM_PHASE2A
	std::unique_ptr<megavgm_supervisor::Phase2Service> phase2;
	if (paths.phase2a) phase2.reset(new megavgm_supervisor::Phase2Service(paths, supervisor));
#endif
	for (;;) {
		if (stop_requested) {
			result = supervisor.exit("supervisor signal");
			break;
		}
		result = supervisor.monitor_once();
		if (!result.ok || !supervisor.active()) break;
#ifdef MEGAVGM_PHASE2A
		if (paths.phase2a) {
			result = phase2->tick();
			if (!result.ok) { supervisor.exit("PHASE2A: " + result.detail); break; }
		}
#endif
		usleep(200000);
	}
	if (!result.ok) std::cerr << result.detail << '\n';
	else std::cout << "STOCK MISTER RESTORED\n";
	return result.ok ? 0 : 1;
}

int enter_mode(megavgm_supervisor::Paths paths,
	const std::string &playlist, const std::string &start_file,
	const std::string &playlist_snapshot = {})
{
	megavgm_supervisor::InstanceLock lock;
	megavgm_supervisor::OperationResult result = lock.acquire(paths.supervisor_lock);
	if (!result.ok) {
		std::cerr << result.detail << '\n';
		return result.detail == "ALREADY_RUNNING" ? 3 : 1;
	}
	result = megavgm_supervisor::apply_test_profile(paths);
	if (!result.ok) {
		std::cerr << "TEST_PROFILE_FAILED: " << result.detail << '\n';
		return 1;
	}
#ifdef MEGAVGM_PHASE2A
	if (paths.phase2a) {
		result = megavgm_supervisor::phase2a_preflight(paths, playlist, start_file, playlist_snapshot);
		if (!result.ok) { std::cerr << "PHASE2A_PREFLIGHT_FAILED: " << result.detail << '\n'; return 1; }
	}
#endif
	int notification[2] = {-1, -1};
	if (pipe(notification) < 0) {
		std::cerr << "pipe: " << std::strerror(errno) << '\n';
		return 1;
	}
	const pid_t child = fork();
	if (child < 0) {
		std::cerr << "fork: " << std::strerror(errno) << '\n';
		close(notification[0]);
		close(notification[1]);
		return 1;
	}
	if (child == 0) {
		close(notification[0]);
		const int result_code = run_daemon(paths, playlist, start_file,
			playlist_snapshot,
			notification[1]);
		close(notification[1]);
		_exit(result_code);
	}
	close(notification[1]);
	std::string message;
	char buffer[256];
	for (;;) {
		const ssize_t bytes = read(notification[0], buffer, sizeof(buffer));
		if (bytes > 0) {
			message.append(buffer, static_cast<std::size_t>(bytes));
			continue;
		}
		if (bytes < 0 && errno == EINTR) continue;
		break;
	}
	close(notification[0]);
	if (message.empty()) message = "ENTER_FAILED: supervisor exited without status\n";
	std::cout << message;
	return message == "MEGAVGM MODE ACTIVE\n" ? 0 : 1;
}

int exit_mode(const megavgm_supervisor::Paths &paths)
{
	megavgm_supervisor::OperationResult result =
		megavgm_supervisor::request_exit_or_classify(paths.supervisor_socket,
			paths.supervisor_status);
	if (!result.ok) {
		std::cerr << "EXIT_FAILED: " << result.detail << '\n';
		return 1;
	}
	if (result.detail == "RESTORE_IN_PROGRESS") {
		std::cout << "RESTORE_IN_PROGRESS\n";
		return 0;
	}
	if (result.detail == "ALREADY_STOPPED") {
		std::cout << "ALREADY_STOPPED: STOCK MISTER RESTORED\n";
		return 0;
	}
	for (int elapsed = 0; elapsed <= 30000; elapsed += 100) {
		std::string status;
		std::string detail;
		if (megavgm_supervisor::read_text_file(paths.supervisor_status,
			status, detail) && megavgm_supervisor::status_is_stock(status)) {
			std::cout << "STOCK MISTER RESTORED\n";
			return 0;
		}
		usleep(100000);
	}
	std::cerr << "EXIT_FAILED: timed out waiting for stock Main restoration\n";
	return 1;
}

int show_status(const megavgm_supervisor::Paths &paths)
{
	std::string status;
	std::string detail;
	if (!megavgm_supervisor::read_text_file(paths.supervisor_status,
		status, detail)) {
		std::cerr << "STATUS_UNAVAILABLE: " << detail << '\n';
		return 1;
	}
	std::cout << status;
	return 0;
}

int hash_main(const megavgm_supervisor::Paths &paths)
{
	struct stat attributes = {};
	const int stat_result = stat(paths.modified_main.c_str(), &attributes);
	const int stat_errno = stat_result == 0 ? 0 : errno;
	std::string actual;
	std::string detail;
	int hash_errno = 0;
	const bool success = megavgm_supervisor::sha256_file(paths.modified_main,
		actual, detail, &hash_errno);
	std::cout << "modified_main_path=" << paths.modified_main << '\n'
		<< "modified_main_size=";
	if (stat_result == 0) std::cout << attributes.st_size;
	else std::cout << "STAT_FAILED: " << stat_errno << ": "
		<< std::strerror(stat_errno);
	std::cout << '\n'
		<< "modified_main_sha_expected=" << paths.expected_modified_sha256 << '\n'
		<< "modified_main_sha_actual=" << actual << '\n'
		<< "modified_main_sha256_file_success=" << (success ? "YES" : "NO") << '\n'
		<< "modified_main_sha_errno=" << (success ? "0" :
			std::to_string(hash_errno) + ": " + detail) << '\n';
	return success && actual == paths.expected_modified_sha256 ? 0 : 1;
}

void usage()
{
	std::cerr << "Usage:\n"
	          << "  megavgm_supervisor enter [--start-file PATH | "
	          << "--playlist-snapshot PATH] <playlist-directory>\n"
	          << "  megavgm_supervisor exit\n"
	          << "  megavgm_supervisor status\n"
	          << "  megavgm_supervisor hash-main\n";
	std::cerr << "  megavgm_supervisor test-profile [default|ym2610b-phase1b|fade-only-a|fade-only-b]\n";
#ifdef MEGAVGM_PHASE2A
	std::cerr << "  megavgm_supervisor test-profile phase2a  (opt-in A/B automatic test route)\n";
#endif
}

} // namespace

int main(int argc, char **argv)
{
	megavgm_supervisor::Paths paths;
	if ((argc == 2 || argc == 3) && std::string(argv[1]) == "test-profile") {
		if (argc == 3) {
			if (geteuid() != 0) { std::cerr << "root privileges required\n"; return 1; }
			const auto result = megavgm_supervisor::set_test_profile(paths, argv[2]);
			if (!result.ok) { std::cerr << "TEST_PROFILE_FAILED: " << result.detail << '\n'; return 1; }
		}
		const auto result = megavgm_supervisor::apply_test_profile(paths);
		if (!result.ok) { std::cerr << "TEST_PROFILE_FAILED: " << result.detail << '\n'; return 1; }
		std::cout << "test_profile=" << paths.rbf_profile << '\n';
#ifdef MEGAVGM_PHASE2A
		if (paths.phase2a) {
			std::cout << "rbf=AUTO_CLASSIFY_SELECTED_VGM\n"
			          << "profile_a=" << megavgm_profile::rbf(megavgm_profile::Profile::A) << '\n'
			          << "profile_b=" << megavgm_profile::rbf(megavgm_profile::Profile::B) << '\n';
		} else
#endif
		std::cout << "rbf=" << paths.rbf << '\n';
		return 0;
	}
	if (argc == 3 && std::string(argv[1]) == "enter")
		return enter_mode(paths, argv[2], {}, {});
	if (argc == 5 && std::string(argv[1]) == "enter" &&
	    std::string(argv[2]) == "--start-file")
		return enter_mode(paths, argv[4], argv[3], {});
	if (argc == 5 && std::string(argv[1]) == "enter" &&
	    std::string(argv[2]) == "--playlist-snapshot")
		return enter_mode(paths, argv[4], {}, argv[3]);
	if (argc == 2 && std::string(argv[1]) == "exit") return exit_mode(paths);
	if (argc == 2 && std::string(argv[1]) == "status") return show_status(paths);
	if (argc == 2 && std::string(argv[1]) == "hash-main") return hash_main(paths);
	usage();
	return 2;
}
