#include "runtime_support.h"

#include <cerrno>
#include <cstring>
#include <fcntl.h>
#include <sstream>
#include <sys/file.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>

namespace megavgm_supervisor {
namespace {

bool write_all(int fd, const char *data, std::size_t size, std::string &detail)
{
	while (size != 0) {
		const ssize_t written = write(fd, data, size);
		if (written > 0) {
			data += written;
			size -= static_cast<std::size_t>(written);
			continue;
		}
		if (written < 0 && errno == EINTR) continue;
		detail = written < 0 ? std::strerror(errno) : "short write";
		return false;
	}
	return true;
}

bool safe_status_value(const std::string &value)
{
	return value.find('\n') == std::string::npos &&
		value.find('\r') == std::string::npos &&
		value.find('\0') == std::string::npos;
}

std::string snapshot_text(const Snapshot &snapshot)
{
	std::ostringstream text;
	text << "mode=" << snapshot.mode << '\n'
	     << "main=" << snapshot.main << '\n'
	     << "controller=" << snapshot.controller << '\n'
	     << "rbf=" << snapshot.rbf << '\n'
	     << "playlist=" << snapshot.playlist << '\n'
	     << "stock_sha256=" << snapshot.stock_sha256 << '\n'
	     << "modified_sha256=" << snapshot.modified_sha256 << '\n'
	     << "controller_pid=" << snapshot.controller_pid << '\n'
	     << "controller_exec=" << snapshot.controller_exec << '\n'
	     << "controller_exit=" << snapshot.controller_exit << '\n'
	     << "controller_stderr=" << snapshot.controller_stderr << '\n'
	     << "megavgm_status_at_controller_launch="
	     << snapshot.megavgm_status_at_controller_launch << '\n'
	     << "playlist_command_seen=" << snapshot.playlist_command_seen << '\n'
	     << "playlist_status_seen=" << snapshot.playlist_status_seen << '\n'
	     << "active_main_sha256=" << snapshot.active_main_sha256 << '\n'
	     << "active_rbf_argv=" << snapshot.active_rbf_argv << '\n'
	     << "detail=" << snapshot.detail << '\n';
	return text.str();
}

} // namespace

InstanceLock::~InstanceLock()
{
	if (fd_ >= 0) close(fd_);
}

OperationResult InstanceLock::acquire(const std::string &path)
{
	if (fd_ >= 0) return OperationResult::failure("lock already acquired");
	fd_ = open(path.c_str(), O_RDWR | O_CREAT | O_CLOEXEC, 0600);
	if (fd_ < 0) return OperationResult::failure(std::strerror(errno));
	if (flock(fd_, LOCK_EX | LOCK_NB) < 0) {
		const int saved = errno;
		close(fd_);
		fd_ = -1;
		if (saved == EWOULDBLOCK || saved == EAGAIN)
			return OperationResult::failure("ALREADY_RUNNING");
		return OperationResult::failure(std::strerror(saved));
	}
	return OperationResult::success();
}

AtomicStatusPublisher::AtomicStatusPublisher(std::string path)
	: path_(std::move(path))
{
}

OperationResult AtomicStatusPublisher::publish(const Snapshot &snapshot)
{
	for (const std::string *value : {&snapshot.mode, &snapshot.main,
		&snapshot.controller, &snapshot.rbf, &snapshot.playlist,
		&snapshot.stock_sha256, &snapshot.modified_sha256,
		&snapshot.controller_pid, &snapshot.controller_exec,
		&snapshot.controller_exit, &snapshot.controller_stderr,
		&snapshot.megavgm_status_at_controller_launch,
		&snapshot.playlist_command_seen, &snapshot.playlist_status_seen,
		&snapshot.active_main_sha256, &snapshot.active_rbf_argv,
		&snapshot.detail}) {
		if (!safe_status_value(*value))
			return OperationResult::failure("status value contains a line break");
	}
	const std::string temporary = path_ + ".tmp." +
		std::to_string(static_cast<long>(getpid()));
	const int fd = open(temporary.c_str(),
		O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0644);
	if (fd < 0) return OperationResult::failure(std::strerror(errno));
	const std::string content = snapshot_text(snapshot);
	std::string detail;
	bool ok = write_all(fd, content.data(), content.size(), detail);
	if (ok && fsync(fd) < 0) {
		detail = std::strerror(errno);
		ok = false;
	}
	if (close(fd) < 0 && ok) {
		detail = std::strerror(errno);
		ok = false;
	}
	if (ok && rename(temporary.c_str(), path_.c_str()) < 0) {
		detail = std::strerror(errno);
		ok = false;
	}
	if (!ok) {
		unlink(temporary.c_str());
		return OperationResult::failure(detail);
	}
	return OperationResult::success();
}

ControlServer::~ControlServer()
{
	if (fd_ >= 0) close(fd_);
	if (!path_.empty()) unlink(path_.c_str());
}

OperationResult ControlServer::open(const std::string &path)
{
	struct stat attributes = {};
	if (lstat(path.c_str(), &attributes) == 0) {
		if (!S_ISSOCK(attributes.st_mode))
			return OperationResult::failure("control path exists and is not a socket");
		if (unlink(path.c_str()) < 0)
			return OperationResult::failure(std::strerror(errno));
	} else if (errno != ENOENT) {
		return OperationResult::failure(std::strerror(errno));
	}

	fd_ = socket(AF_UNIX, SOCK_STREAM, 0);
	if (fd_ < 0) return OperationResult::failure(std::strerror(errno));
	const int flags = fcntl(fd_, F_GETFL, 0);
	if (flags < 0 || fcntl(fd_, F_SETFL, flags | O_NONBLOCK) < 0) {
		const std::string detail = std::strerror(errno);
		close(fd_);
		fd_ = -1;
		return OperationResult::failure(detail);
	}
	struct sockaddr_un address = {};
	address.sun_family = AF_UNIX;
	if (path.size() >= sizeof(address.sun_path)) {
		close(fd_);
		fd_ = -1;
		return OperationResult::failure("control socket path is too long");
	}
	std::strcpy(address.sun_path, path.c_str());
	if (bind(fd_, reinterpret_cast<struct sockaddr *>(&address),
		sizeof(address)) < 0 || listen(fd_, 4) < 0 || chmod(path.c_str(), 0600) < 0) {
		const std::string detail = std::strerror(errno);
		close(fd_);
		fd_ = -1;
		unlink(path.c_str());
		return OperationResult::failure(detail);
	}
	path_ = path;
	return OperationResult::success();
}

bool ControlServer::exit_requested()
{
	if (fd_ < 0) return false;
	bool requested = false;
	for (;;) {
		const int client = accept(fd_, nullptr, nullptr);
		if (client < 0 && errno == EINTR) continue;
		if (client < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) break;
		if (client < 0) break;
		const int client_flags = fcntl(client, F_GETFL, 0);
		if (client_flags >= 0) fcntl(client, F_SETFL, client_flags | O_NONBLOCK);
		char command[32] = {};
		const ssize_t size = read(client, command, sizeof(command) - 1);
		if (size > 0) {
			std::string line(command, static_cast<std::size_t>(size));
			if (line == "EXIT\n" || line == "EXIT\r\n") requested = true;
		}
		close(client);
	}
	return requested;
}

OperationResult send_exit_request(const std::string &path)
{
	const int fd = socket(AF_UNIX, SOCK_STREAM, 0);
	if (fd < 0) return OperationResult::failure(std::strerror(errno));
	struct sockaddr_un address = {};
	address.sun_family = AF_UNIX;
	if (path.size() >= sizeof(address.sun_path)) {
		close(fd);
		return OperationResult::failure("control socket path is too long");
	}
	std::strcpy(address.sun_path, path.c_str());
	if (connect(fd, reinterpret_cast<struct sockaddr *>(&address),
		sizeof(address)) < 0) {
		const std::string detail = std::strerror(errno);
		close(fd);
		return OperationResult::failure(detail);
	}
	std::string detail;
	const bool ok = write_all(fd, "EXIT\n", 5, detail);
	close(fd);
	return ok ? OperationResult::success() : OperationResult::failure(detail);
}

bool status_is_restoring(const std::string &content)
{
	const std::string restoring = "mode=SHUTTING_DOWN\n";
	return content.compare(0, restoring.size(), restoring) == 0;
}

OperationResult request_exit_or_classify(const std::string &socket_path,
	const std::string &status_path)
{
	auto classify = [&]() -> OperationResult {
		std::string status;
		std::string detail;
		if (!read_text_file(status_path, status, detail))
			return OperationResult::failure("status unavailable: " + detail);
		if (status_is_stock(status)) return {true, "ALREADY_STOPPED"};
		if (status_is_restoring(status)) return {true, "RESTORE_IN_PROGRESS"};
		return OperationResult::failure("restore is not already in progress");
	};

	OperationResult state = classify();
	if (state.ok) return state;
	OperationResult sent = send_exit_request(socket_path);
	if (sent.ok) return {true, "EXIT_REQUESTED"};
	state = classify();
	if (state.ok) return state;
	return OperationResult::failure("supervisor control unavailable: " + sent.detail);
}

bool read_text_file(const std::string &path, std::string &content,
	std::string &detail, std::size_t maximum_size)
{
	const int fd = open(path.c_str(), O_RDONLY | O_CLOEXEC);
	if (fd < 0) {
		detail = std::strerror(errno);
		return false;
	}
	content.clear();
	char buffer[4096];
	for (;;) {
		const ssize_t bytes = read(fd, buffer, sizeof(buffer));
		if (bytes > 0) {
			content.append(buffer, static_cast<std::size_t>(bytes));
			if (content.size() > maximum_size) {
				detail = "file exceeds size limit";
				close(fd);
				return false;
			}
			continue;
		}
		if (bytes < 0 && errno == EINTR) continue;
		if (bytes < 0) {
			detail = std::strerror(errno);
			close(fd);
			return false;
		}
		break;
	}
	close(fd);
	detail.clear();
	return true;
}

bool status_is_stock(const std::string &content)
{
	return content.find("mode=STOCK\n") != std::string::npos &&
		content.find("main=STOCK\n") != std::string::npos &&
		content.find("controller=STOPPED\n") != std::string::npos;
}

} // namespace megavgm_supervisor
