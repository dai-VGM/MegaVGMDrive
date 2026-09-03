#include "playlist_control.h"

#include <cerrno>
#include <cstdio>
#include <cstring>
#include <fcntl.h>
#include <sstream>
#include <set>
#include <limits.h>
#include <sys/stat.h>
#include <unistd.h>
#include <utility>

namespace megavgm_playlist {
namespace {

constexpr std::size_t kMaximumControlBuffer = 4096;
constexpr std::size_t kMaximumSnapshotSize = 1024 * 1024;
const char kSnapshotPathPrefix[] = "/tmp/megavgm_playlist.snapshot-";

bool has_control(const std::string &value)
{
	for (unsigned char byte : value)
		if (byte < 0x20 || byte == 0x7f) return true;
	return false;
}

bool parse_size(const std::string &value, std::size_t &result)
{
	if (value.empty()) return false;
	result = 0;
	for (unsigned char byte : value) {
		if (byte < '0' || byte > '9') return false;
		const std::size_t digit = byte - '0';
		if (result > (static_cast<std::size_t>(-1) - digit) / 10) return false;
		result = result * 10 + digit;
	}
	return true;
}

bool within_root(const std::string &root, const std::string &path)
{
	return path == root || (path.size() > root.size() &&
		path.compare(0, root.size(), root) == 0 && path[root.size()] == '/');
}

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
	     << "loop_count=" << snapshot.loop_count << '\n'
	     << "context=" << snapshot.context << '\n'
	     << "playlist=" << snapshot.playlist << '\n'
	     << "repeat=" << repeat_mode_name(snapshot.repeat) << '\n'
	     << "shuffle=" << (snapshot.shuffle ? 1 : 0) << '\n'
	     << "traversal=" << snapshot.traversal << '\n';
	return text.str();
}

} // namespace

const char *control_command_name(ControlCommandType command)
{
	switch (command) {
	case ControlCommandType::Next: return "NEXT";
	case ControlCommandType::Previous: return "PREV";
	case ControlCommandType::Stop: return "STOP";
	case ControlCommandType::Play: return "PLAY";
	case ControlCommandType::Playlist: return "PLAYLIST";
	case ControlCommandType::Repeat: return "REPEAT";
	case ControlCommandType::Shuffle: return "SHUFFLE";
	}
	return "UNKNOWN";
}

PosixControllerIo::PosixControllerIo(std::string command_path,
		std::string status_path, std::string preferences_path)
	: command_path_(std::move(command_path)), status_path_(std::move(status_path)),
	  preferences_path_(std::move(preferences_path))
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
		ControlCommand &command, std::string &detail)
{
	const std::size_t newline = input_buffer_.find('\n');
	if (newline == std::string::npos) {
		if (input_buffer_.size() <= kMaximumControlBuffer)
			return ControlPollResult::None;
		input_buffer_.clear();
		detail = "command exceeds 4096 bytes";
		return ControlPollResult::Invalid;
	}
	std::string line = input_buffer_.substr(0, newline);
	input_buffer_.erase(0, newline + 1);
	if (!line.empty() && line.back() == '\r') line.pop_back();
	command.path.clear();
	command.repeat = RepeatMode::Off;
	command.shuffle = false;
	if (line == "NEXT") command.type = ControlCommandType::Next;
	else if (line == "PREV") command.type = ControlCommandType::Previous;
	else if (line == "STOP") command.type = ControlCommandType::Stop;
	else if (line.compare(0, 5, "PLAY ") == 0 && line.size() > 5) {
		command.type = ControlCommandType::Play;
		command.path = line.substr(5);
		if (command.path.size() > 4090 || command.path.front() != '/') {
			detail = "invalid PLAY path";
			return ControlPollResult::Invalid;
		}
	}
	else if (line.compare(0, 9, "PLAYLIST ") == 0 && line.size() > 9) {
		command.type = ControlCommandType::Playlist;
		command.path = line.substr(9);
		if (command.path.size() > 240 || has_control(command.path) ||
		    command.path.compare(0, sizeof(kSnapshotPathPrefix) - 1,
			kSnapshotPathPrefix) != 0) {
			detail = "invalid PLAYLIST snapshot path";
			return ControlPollResult::Invalid;
		}
	}
	else if (line.compare(0, 7, "REPEAT ") == 0 && line.size() > 7) {
		command.type = ControlCommandType::Repeat;
		if (!parse_repeat_mode(line.substr(7), command.repeat)) {
			detail = "invalid REPEAT mode";
			return ControlPollResult::Invalid;
		}
	}
	else if (line == "SHUFFLE ON" || line == "SHUFFLE OFF") {
		command.type = ControlCommandType::Shuffle;
		command.shuffle = line == "SHUFFLE ON";
	}
	else {
		detail = "unknown command: " + line;
		return ControlPollResult::Invalid;
	}
	detail.clear();
	return ControlPollResult::Command;
}

ControlPollResult PosixControllerIo::poll_command(ControlCommand &command,
		std::string &detail)
{
	if (!retained_commands_.empty()) {
		command = retained_commands_.front();
		retained_commands_.pop_front();
		detail.clear();
		return ControlPollResult::Command;
	}
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
	char buffer[128];
	for (;;) {
		const ssize_t bytes = read(command_fd_, buffer, sizeof(buffer));
		if (bytes > 0) {
			input_buffer_.append(buffer, static_cast<std::size_t>(bytes));
			continue;
		}
		if (bytes < 0 && errno == EINTR) continue;
		if (bytes < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) break;
		if (bytes == 0) break;
		detail = std::strerror(errno);
		return false;
	}
	for (;;) {
		ControlCommand command;
		std::string ignored;
		const ControlPollResult result = parse_buffered_command(command, ignored);
		if (result == ControlPollResult::None) break;
		if (result == ControlPollResult::Command &&
		    (command.type == ControlCommandType::Stop ||
		     command.type == ControlCommandType::Repeat ||
		     command.type == ControlCommandType::Shuffle))
			retained_commands_.push_back(command);
	}
	// A partial navigation command cannot be safely associated with a later
	// load window. Mode commands are always short atomic FIFO writes.
	input_buffer_.clear();
	detail.clear();
	return true;
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

bool PosixControllerIo::load_preferences(PlaybackPreferences &preferences,
		std::string &detail)
{
	return load_playback_preferences(preferences_path_, preferences, detail);
}

bool PosixControllerIo::save_preferences(
		const PlaybackPreferences &preferences, std::string &detail)
{
	return save_playback_preferences(preferences_path_, preferences, detail);
}

bool send_navigation_command(const std::string &command_path,
		ControlCommandType command, std::string &detail)
{
	if (command != ControlCommandType::Next &&
	    command != ControlCommandType::Previous) {
		detail = "PLAY requires a path";
		return false;
	}
	const int fd = open(command_path.c_str(), O_WRONLY | O_NONBLOCK | O_CLOEXEC);
	if (fd < 0) {
		detail = std::strerror(errno);
		return false;
	}
	const std::string text = std::string(control_command_name(command)) + '\n';
	bool ok = write_all(fd, text.data(), text.size(), detail);
	if (close(fd) < 0 && ok) {
		detail = std::strerror(errno);
		ok = false;
	}
	return ok;
}

bool send_stop_command(const std::string &command_path, std::string &detail)
{
	const int fd = open(command_path.c_str(),
			O_WRONLY | O_NONBLOCK | O_CLOEXEC);
	if (fd < 0) {
		detail = std::strerror(errno);
		return false;
	}
	const char text[] = "STOP\n";
	const ssize_t count = write(fd, text, sizeof(text) - 1);
	const int write_errno = errno;
	if (close(fd) < 0 && count == static_cast<ssize_t>(sizeof(text) - 1)) {
		detail = std::strerror(errno);
		return false;
	}
	if (count != static_cast<ssize_t>(sizeof(text) - 1)) {
		detail = count < 0 ? std::strerror(write_errno) : "short command write";
		return false;
	}
	detail.clear();
	return true;
}

bool send_repeat_command(const std::string &command_path, RepeatMode mode,
		std::string &detail)
{
	const int fd = open(command_path.c_str(), O_WRONLY | O_NONBLOCK | O_CLOEXEC);
	if (fd < 0) {
		detail = std::strerror(errno);
		return false;
	}
	const std::string text = std::string("REPEAT ") + repeat_mode_name(mode) + '\n';
	bool ok = write_all(fd, text.data(), text.size(), detail);
	if (close(fd) < 0 && ok) {
		detail = std::strerror(errno);
		ok = false;
	}
	return ok;
}

bool send_shuffle_command(const std::string &command_path, bool enabled,
		std::string &detail)
{
	const int fd = open(command_path.c_str(), O_WRONLY | O_NONBLOCK | O_CLOEXEC);
	if (fd < 0) {
		detail = std::strerror(errno);
		return false;
	}
	const std::string text = enabled ? "SHUFFLE ON\n" : "SHUFFLE OFF\n";
	bool ok = write_all(fd, text.data(), text.size(), detail);
	if (close(fd) < 0 && ok) {
		detail = std::strerror(errno);
		ok = false;
	}
	return ok;
}

bool send_playlist_command(const std::string &command_path,
		const std::string &snapshot_path, std::string &detail)
{
	if (snapshot_path.empty() || snapshot_path.size() > 240 ||
	    has_control(snapshot_path) ||
	    snapshot_path.compare(0, sizeof(kSnapshotPathPrefix) - 1,
		kSnapshotPathPrefix) != 0) {
		detail = "invalid PLAYLIST snapshot path";
		return false;
	}
	const int fd = open(command_path.c_str(), O_WRONLY | O_NONBLOCK | O_CLOEXEC);
	if (fd < 0) {
		detail = std::strerror(errno);
		return false;
	}
	const std::string text = "PLAYLIST " + snapshot_path + '\n';
	bool ok = write_all(fd, text.data(), text.size(), detail);
	if (close(fd) < 0 && ok) {
		detail = std::strerror(errno);
		ok = false;
	}
	return ok;
}

bool load_playlist_snapshot(const std::string &snapshot_path,
		const std::string &approved_root, PlaylistSnapshot &snapshot,
		std::string &detail, bool consume)
{
	snapshot = PlaylistSnapshot{};
	const int fd = open(snapshot_path.c_str(), O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
	if (fd < 0) {
		detail = std::strerror(errno);
		return false;
	}
	struct stat attributes = {};
	bool ok = fstat(fd, &attributes) == 0 && S_ISREG(attributes.st_mode) &&
		attributes.st_size >= 0 &&
		static_cast<std::size_t>(attributes.st_size) <= kMaximumSnapshotSize;
	std::string content;
	if (ok) {
		content.resize(static_cast<std::size_t>(attributes.st_size));
		std::size_t offset = 0;
		while (offset < content.size()) {
			const ssize_t bytes = read(fd, &content[offset], content.size() - offset);
			if (bytes > 0) offset += static_cast<std::size_t>(bytes);
			else if (bytes < 0 && errno == EINTR) continue;
			else { ok = false; break; }
		}
	}
	if (!ok) detail = "invalid or unreadable snapshot file";
	close(fd);
	if (consume) unlink(snapshot_path.c_str());
	if (!ok) return false;

	std::istringstream lines(content);
	std::string line;
	if (!std::getline(lines, line) || line != "MEGAVGM_PLAYLIST_V1") {
		detail = "invalid snapshot header";
		return false;
	}
	if (!std::getline(lines, line) || line.compare(0, 5, "NAME ") != 0) {
		detail = "missing snapshot name";
		return false;
	}
	snapshot.name = line.substr(5);
	if (snapshot.name.empty() || snapshot.name.size() > 80 || has_control(snapshot.name)) {
		detail = "invalid snapshot name";
		return false;
	}
	if (!std::getline(lines, line) || line.compare(0, 6, "START ") != 0 ||
	    !parse_size(line.substr(6), snapshot.start_index)) {
		detail = "invalid snapshot start";
		return false;
	}
	std::size_t count = 0;
	if (!std::getline(lines, line) || line.compare(0, 6, "COUNT ") != 0 ||
	    !parse_size(line.substr(6), count) || count == 0 || count > 10000) {
		detail = "invalid snapshot count";
		return false;
	}
	char root_buffer[PATH_MAX];
	if (!realpath(approved_root.c_str(), root_buffer)) {
		detail = "approved root unavailable";
		return false;
	}
	const std::string canonical_root(root_buffer);
	std::set<std::string> seen;
	for (std::size_t index = 0; index < count; ++index) {
		if (!std::getline(lines, line) || line.compare(0, 5, "PATH ") != 0) {
			detail = "snapshot path count mismatch";
			return false;
		}
		const std::string requested = line.substr(5);
		char path_buffer[PATH_MAX];
		struct stat path_attributes = {};
		if (requested.empty() || has_control(requested) ||
		    requested.size() < 4 || requested.compare(requested.size() - 4, 4, ".vgm") != 0 ||
		    !realpath(requested.c_str(), path_buffer) ||
		    !within_root(canonical_root, path_buffer) ||
		    stat(path_buffer, &path_attributes) < 0 || !S_ISREG(path_attributes.st_mode)) {
			detail = "unavailable or invalid snapshot path";
			return false;
		}
		const std::string canonical(path_buffer);
		if (!seen.insert(canonical).second) {
			detail = "duplicate snapshot path";
			return false;
		}
		snapshot.paths.push_back(canonical);
	}
	if (std::getline(lines, line) && !line.empty()) {
		detail = "unexpected snapshot content";
		return false;
	}
	if (snapshot.start_index >= snapshot.paths.size()) {
		detail = "snapshot start outside playlist";
		return false;
	}
	detail.clear();
	return true;
}

bool send_play_command(const std::string &command_path,
		const std::string &path, std::string &detail)
{
	if (path.empty() || path.size() > 4090 || path.front() != '/' ||
	    path.find('\n') != std::string::npos ||
	    path.find('\r') != std::string::npos) {
		detail = "invalid PLAY path";
		return false;
	}
	const int fd = open(command_path.c_str(), O_WRONLY | O_NONBLOCK | O_CLOEXEC);
	if (fd < 0) {
		detail = std::strerror(errno);
		return false;
	}
	const std::string text = "PLAY " + path + '\n';
	bool ok = write_all(fd, text.data(), text.size(), detail);
	if (close(fd) < 0 && ok) {
		detail = std::strerror(errno);
		ok = false;
	}
	return ok;
}

} // namespace megavgm_playlist
