#include "playback_mode.h"

#include <algorithm>
#include <cerrno>
#include <cstring>
#include <fcntl.h>
#include <fstream>
#include <iterator>
#include <sstream>
#include <sys/stat.h>
#include <unistd.h>

namespace megavgm_playlist {
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

std::string parent_path(const std::string &path)
{
	const std::size_t separator = path.find_last_of('/');
	if (separator == std::string::npos) return ".";
	return separator == 0 ? "/" : path.substr(0, separator);
}

bool ensure_directory(const std::string &path, std::string &detail)
{
	if (path.empty() || path == "/" || path == ".") return true;
	struct stat attributes = {};
	if (stat(path.c_str(), &attributes) == 0) {
		if (S_ISDIR(attributes.st_mode)) return true;
		detail = "configuration parent is not a directory";
		return false;
	}
	if (errno != ENOENT) {
		detail = std::strerror(errno);
		return false;
	}
	if (!ensure_directory(parent_path(path), detail)) return false;
	if (mkdir(path.c_str(), 0755) == 0 || errno == EEXIST) return true;
	detail = std::strerror(errno);
	return false;
}

} // namespace

const char *repeat_mode_name(RepeatMode mode)
{
	switch (mode) {
	case RepeatMode::Off: return "OFF";
	case RepeatMode::One: return "ONE";
	case RepeatMode::All: return "ALL";
	}
	return "OFF";
}

bool parse_repeat_mode(const std::string &value, RepeatMode &mode)
{
	if (value == "off" || value == "OFF") mode = RepeatMode::Off;
	else if (value == "one" || value == "ONE") mode = RepeatMode::One;
	else if (value == "all" || value == "ALL") mode = RepeatMode::All;
	else return false;
	return true;
}

XorShiftRandom::XorShiftRandom(std::uint32_t seed)
	: state_(seed == 0 ? 0x6d2b79f5u : seed)
{
}

std::uint32_t XorShiftRandom::uniform(std::uint32_t upper_exclusive)
{
	if (upper_exclusive <= 1) return 0;
	state_ ^= state_ << 13;
	state_ ^= state_ >> 17;
	state_ ^= state_ << 5;
	return state_ % upper_exclusive;
}

PlaybackTraversal::PlaybackTraversal(RandomSource &random) : random_(random) {}

void PlaybackTraversal::build_bag(std::size_t current, bool include_current)
{
	remaining_.clear();
	for (std::size_t index = 0; index < count_; ++index)
		if (include_current || index != current) remaining_.push_back(index);
	for (std::size_t size = remaining_.size(); size > 1; --size) {
		const std::size_t other = random_.uniform(static_cast<std::uint32_t>(size));
		std::swap(remaining_[size - 1], remaining_[other]);
	}
	// The next item is popped from the back. A repeated shuffle cycle contains
	// every index, but cannot begin by replaying the just-finished track.
	if (include_current && remaining_.size() > 1 &&
	    remaining_.back() == current) {
		for (std::size_t index = 0; index + 1 < remaining_.size(); ++index) {
			if (remaining_[index] != current) {
				std::swap(remaining_[index], remaining_.back());
				break;
			}
		}
	}
}

void PlaybackTraversal::reset(std::size_t count, std::size_t current,
		const PlaybackPreferences &preferences)
{
	count_ = count;
	preferences_ = preferences;
	remaining_.clear();
	history_.clear();
	history_position_ = 0;
	if (count_ == 0 || current >= count_) return;
	history_.push_back(current);
	if (preferences_.shuffle) build_bag(current, false);
}

void PlaybackTraversal::set_preferences(
		const PlaybackPreferences &preferences, std::size_t current)
{
	const bool shuffle_changed = preferences_.shuffle != preferences.shuffle;
	preferences_ = preferences;
	if (!shuffle_changed) return;
	remaining_.clear();
	history_.clear();
	history_position_ = 0;
	if (count_ == 0 || current >= count_) return;
	history_.push_back(current);
	if (preferences_.shuffle) build_bag(current, false);
}

void PlaybackTraversal::append_history(std::size_t index)
{
	if (history_position_ + 1 < history_.size())
		history_.erase(history_.begin() + history_position_ + 1, history_.end());
	if (history_.empty() || history_.back() != index) history_.push_back(index);
	history_position_ = history_.empty() ? 0 : history_.size() - 1;
}

void PlaybackTraversal::select(std::size_t current)
{
	if (!preferences_.shuffle || current >= count_) return;
	remaining_.erase(std::remove(remaining_.begin(), remaining_.end(), current),
		remaining_.end());
	append_history(current);
}

bool PlaybackTraversal::take_bag(std::size_t current, std::size_t &selected)
{
	if (remaining_.empty()) {
		if (preferences_.repeat != RepeatMode::All) return false;
		build_bag(current, true);
	}
	selected = remaining_.back();
	remaining_.pop_back();
	append_history(selected);
	return true;
}

TraversalResult PlaybackTraversal::next(std::size_t current, bool automatic,
		bool native_looping, std::size_t &selected)
{
	if (count_ == 0 || current >= count_) return TraversalResult::Complete;
	if (automatic && preferences_.repeat == RepeatMode::One) {
		selected = current;
		return native_looping ? TraversalResult::Stay : TraversalResult::Track;
	}
	if (preferences_.shuffle) {
		if (history_position_ + 1 < history_.size()) {
			selected = history_[++history_position_];
			return TraversalResult::Track;
		}
		return take_bag(current, selected) ? TraversalResult::Track :
			TraversalResult::Complete;
	}
	if (current + 1 < count_) {
		selected = current + 1;
		return TraversalResult::Track;
	}
	if (preferences_.repeat == RepeatMode::All) {
		selected = 0;
		return TraversalResult::Track;
	}
	return TraversalResult::Complete;
}

TraversalResult PlaybackTraversal::previous(std::size_t current,
		std::size_t &selected)
{
	if (count_ == 0 || current >= count_) return TraversalResult::Complete;
	if (preferences_.shuffle) {
		if (history_position_ != 0) {
			selected = history_[--history_position_];
			return TraversalResult::Track;
		}
		selected = current;
		return TraversalResult::Track;
	}
	if (current != 0) selected = current - 1;
	else if (preferences_.repeat == RepeatMode::All) selected = count_ - 1;
	else selected = current;
	return TraversalResult::Track;
}

bool load_playback_preferences(const std::string &path,
		PlaybackPreferences &preferences, std::string &detail)
{
	preferences = PlaybackPreferences{};
	std::ifstream stream(path);
	if (!stream.good()) {
		detail = errno == ENOENT ? "missing; using defaults" : std::strerror(errno);
		return false;
	}
	std::string magic;
	std::string repeat_line;
	std::string shuffle_line;
	std::string extra;
	if (!std::getline(stream, magic) || !std::getline(stream, repeat_line) ||
	    !std::getline(stream, shuffle_line) || std::getline(stream, extra) ||
	    magic != "MEGAVGM_PLAYBACK_MODE_V1" ||
	    repeat_line.compare(0, 7, "repeat=") != 0 ||
	    shuffle_line.compare(0, 8, "shuffle=") != 0 ||
	    !parse_repeat_mode(repeat_line.substr(7), preferences.repeat) ||
	    (shuffle_line.substr(8) != "0" && shuffle_line.substr(8) != "1")) {
		preferences = PlaybackPreferences{};
		detail = "malformed; using defaults";
		return false;
	}
	preferences.shuffle = shuffle_line.substr(8) == "1";
	detail.clear();
	return true;
}

bool save_playback_preferences(const std::string &path,
		const PlaybackPreferences &preferences, std::string &detail)
{
	const std::string directory = parent_path(path);
	if (!ensure_directory(directory, detail)) return false;
	std::ostringstream content;
	content << "MEGAVGM_PLAYBACK_MODE_V1\nrepeat="
	        << repeat_mode_name(preferences.repeat) << "\nshuffle="
	        << (preferences.shuffle ? 1 : 0) << '\n';
	const std::string temporary = path + ".tmp." +
		std::to_string(static_cast<unsigned long>(getpid()));
	const int fd = open(temporary.c_str(),
		O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0644);
	if (fd < 0) {
		detail = std::strerror(errno);
		return false;
	}
	const std::string text = content.str();
	bool ok = write_all(fd, text.data(), text.size(), detail);
	if (ok && fsync(fd) < 0) {
		detail = std::strerror(errno);
		ok = false;
	}
	if (close(fd) < 0 && ok) {
		detail = std::strerror(errno);
		ok = false;
	}
	if (ok && rename(temporary.c_str(), path.c_str()) < 0) {
		detail = std::strerror(errno);
		ok = false;
	}
	if (ok) {
		const int directory_fd = open(directory.c_str(), O_RDONLY | O_CLOEXEC);
		if (directory_fd >= 0) {
			if (fsync(directory_fd) < 0) {
				detail = std::strerror(errno);
				ok = false;
			}
			close(directory_fd);
		}
	}
	if (!ok) unlink(temporary.c_str());
	else detail.clear();
	return ok;
}

} // namespace megavgm_playlist
