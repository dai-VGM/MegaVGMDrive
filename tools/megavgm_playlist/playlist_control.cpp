#include "playlist_control.h"

#include <cerrno>
#include <cstdio>
#include <cstring>
#include <fcntl.h>
#include <sstream>
#include <sys/stat.h>
#include <unistd.h>
#include <utility>

namespace megavgm_playlist {
namespace {

constexpr std::size_t kMaximumControlBuffer = 256;

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

std::string snapshot_text(const ControllerSnapshot &snapshot)
{
	std::ostringstream text;
	text << "state=" << snapshot.state << '\n'
	     << "index=" << snapshot.index << '\n'
	     << "count=" << snapshot.count << '\n'
	     << "path=" << snapshot.path << '\n'
	     << "session=" << snapshot.session << '\n'
	     << "loop_count=" << snapshot.loop_count << '\n';
	return text.str();
}

} // namespace

const char *navigation_command_name(NavigationCommand command)
{
	return command == NavigationCommand::Next ? "NEXT" : "PREV";
}

PosixControllerIo::PosixControllerIo(std::string command_path,
		std::string status_path)
	: command_path_(std::move(command_path)), status_path_(std::move(status_path))
{
}

PosixControllerIo::~PosixControllerIo()
{
	if (command_fd_ >= 0) close(command_fd_);
	struct stat attributes = {};
	if (command_owned_ && lstat(command_path_.c_str(), &attributes) == 0 &&
	    static_cast<std::uint64_t>(attributes.st_dev) == command_device_ &&
	    static_cast<std::uint64_t>(attributes.st_ino) == command_inode_)
		unlink(command_path_.c_str());
}

bool PosixControllerIo::start(std::string &detail)
{
	struct stat attributes = {};
	if (lstat(command_path_.c_str(), &attributes) == 0) {
		if (!S_ISFIFO(attributes.st_mode)) {
			detail = "control path exists and is not a FIFO";
			return false;
		}
		if (unlink(command_path_.c_str()) < 0) {
			detail = std::strerror(errno);
			return false;
		}
	} else if (errno != ENOENT) {
		detail = std::strerror(errno);
		return false;
	}

	if (mkfifo(command_path_.c_str(), 0600) < 0) {
		detail = std::strerror(errno);
		return false;
	}
	command_fd_ = open(command_path_.c_str(), O_RDWR | O_NONBLOCK | O_CLOEXEC);
	if (command_fd_ < 0) {
		detail = std::strerror(errno);
		unlink(command_path_.c_str());
		return false;
	}
	const int stat_result = fstat(command_fd_, &attributes);
	if (stat_result < 0 || !S_ISFIFO(attributes.st_mode)) {
		detail = stat_result < 0 ? std::strerror(errno) :
			"control path is not a FIFO";
		close(command_fd_);
		command_fd_ = -1;
		unlink(command_path_.c_str());
		return false;
	}
	command_device_ = static_cast<std::uint64_t>(attributes.st_dev);
	command_inode_ = static_cast<std::uint64_t>(attributes.st_ino);
	command_owned_ = true;
	detail.clear();
	return true;
}

ControlPollResult PosixControllerIo::parse_buffered_command(
		NavigationCommand &command, std::string &detail)
{
	const std::size_t newline = input_buffer_.find('\n');
	if (newline == std::string::npos) {
		if (input_buffer_.size() <= kMaximumControlBuffer)
			return ControlPollResult::None;
		input_buffer_.clear();
		detail = "command exceeds 256 bytes";
		return ControlPollResult::Invalid;
	}
	std::string line = input_buffer_.substr(0, newline);
	input_buffer_.erase(0, newline + 1);
	if (!line.empty() && line.back() == '\r') line.pop_back();
	if (line == "NEXT") command = NavigationCommand::Next;
	else if (line == "PREV") command = NavigationCommand::Previous;
	else {
		detail = "unknown command: " + line;
		return ControlPollResult::Invalid;
	}
	detail.clear();
	return ControlPollResult::Command;
}

ControlPollResult PosixControllerIo::poll_command(NavigationCommand &command,
		std::string &detail)
{
	ControlPollResult result = parse_buffered_command(command, detail);
	if (result != ControlPollResult::None) return result;

	char buffer[128];
	for (;;) {
		const ssize_t bytes = read(command_fd_, buffer, sizeof(buffer));
		if (bytes > 0) {
			input_buffer_.append(buffer, static_cast<std::size_t>(bytes));
			result = parse_buffered_command(command, detail);
			if (result != ControlPollResult::None) return result;
			continue;
		}
		if (bytes < 0 && errno == EINTR) continue;
		if (bytes < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
			detail.clear();
			return ControlPollResult::None;
		}
		if (bytes == 0) {
			detail.clear();
			return ControlPollResult::None;
		}
		detail = std::strerror(errno);
		return ControlPollResult::IoError;
	}
}

bool PosixControllerIo::drain_fd(std::string &detail)
{
	char buffer[128];
	for (;;) {
		const ssize_t bytes = read(command_fd_, buffer, sizeof(buffer));
		if (bytes > 0) continue;
		if (bytes < 0 && errno == EINTR) continue;
		if (bytes < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
			detail.clear();
			return true;
		}
		if (bytes == 0) {
			detail.clear();
			return true;
		}
		detail = std::strerror(errno);
		return false;
	}
}

bool PosixControllerIo::discard_commands(std::string &detail)
{
	input_buffer_.clear();
	return drain_fd(detail);
}

bool PosixControllerIo::publish(const ControllerSnapshot &snapshot,
		std::string &detail)
{
	const std::string content = snapshot_text(snapshot);
	if (content == last_status_content_) {
		detail.clear();
		return true;
	}
	const std::string temporary = status_path_ + ".tmp." +
		std::to_string(static_cast<unsigned long>(getpid()));
	const int fd = open(temporary.c_str(),
		O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0644);
	if (fd < 0) {
		detail = std::strerror(errno);
		return false;
	}
	bool ok = write_all(fd, content.data(), content.size(), detail);
	if (ok && fsync(fd) < 0) {
		detail = std::strerror(errno);
		ok = false;
	}
	if (close(fd) < 0 && ok) {
		detail = std::strerror(errno);
		ok = false;
	}
	if (ok && rename(temporary.c_str(), status_path_.c_str()) < 0) {
		detail = std::strerror(errno);
		ok = false;
	}
	if (!ok) {
		unlink(temporary.c_str());
		return false;
	}
	last_status_content_ = content;
	detail.clear();
	return true;
}

bool send_navigation_command(const std::string &command_path,
		NavigationCommand command, std::string &detail)
{
	const int fd = open(command_path.c_str(), O_WRONLY | O_NONBLOCK | O_CLOEXEC);
	if (fd < 0) {
		detail = std::strerror(errno);
		return false;
	}
	const std::string text = std::string(navigation_command_name(command)) + '\n';
	bool ok = write_all(fd, text.data(), text.size(), detail);
	if (close(fd) < 0 && ok) {
		detail = std::strerror(errno);
		ok = false;
	}
	return ok;
}

} // namespace megavgm_playlist
