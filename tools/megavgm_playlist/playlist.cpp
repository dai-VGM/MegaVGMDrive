#include "playlist.h"

#include <algorithm>
#include <cerrno>
#include <cstring>
#include <dirent.h>
#include <iomanip>
#include <sys/stat.h>

namespace megavgm_playlist {
namespace {

using megavgm_autoplay2::PlaybackState;
using megavgm_autoplay2::PlaybackStatus;
using megavgm_autoplay2::Runtime;
using megavgm_autoplay2::StatusReadResult;

bool bytewise_less(const Track &left, const Track &right)
{
	return std::lexicographical_compare(
		left.name.begin(), left.name.end(), right.name.begin(), right.name.end(),
		[](char a, char b) {
			return static_cast<unsigned char>(a) < static_cast<unsigned char>(b);
		});
}

bool has_exact_vgm_suffix(const std::string &name)
{
	return name.size() > 4 &&
		name.compare(name.size() - 4, 4, ".vgm") == 0;
}

std::string join_path(const std::string &directory, const std::string &name)
{
	if (!directory.empty() && directory.back() == '/') return directory + name;
	return directory + '/' + name;
}

PlaylistResult map_status_read_result(StatusReadResult result)
{
	switch (result) {
	case StatusReadResult::Missing: return PlaylistResult::StatusFileMissing;
	case StatusReadResult::Malformed: return PlaylistResult::MalformedStatus;
	case StatusReadResult::UnsupportedVersion:
		return PlaylistResult::UnsupportedVersion;
	case StatusReadResult::IoError: return PlaylistResult::StatusIoError;
	default: return PlaylistResult::StatusIoError;
	}
}

class Monitor {
public:
	Monitor(Runtime &runtime, const PlaylistConfig &config, std::ostream &log)
		: runtime_(runtime), config_(config), log_(log),
		  next_main_probe_(runtime.monotonic_ms())
	{
	}

	PlaylistResult read(PlaybackStatus &status)
	{
		const std::uint64_t now = runtime_.monotonic_ms();
		if (now >= next_main_probe_) {
			std::string detail;
			if (!runtime_.main_available(detail)) {
				log_ << "ACTIVE_MAIN_UNAVAILABLE";
				if (!detail.empty()) log_ << ": " << detail;
				log_ << '\n';
				return PlaylistResult::ActiveMainUnavailable;
			}
			next_main_probe_ = now + config_.main_probe_interval_ms;
		}

		std::string detail;
		const StatusReadResult result = runtime_.read_status(status, detail);
		if (result == StatusReadResult::Ok) return PlaylistResult::Complete;
		const PlaylistResult mapped = map_status_read_result(result);
		log_ << playlist_result_name(mapped);
		if (!detail.empty()) log_ << ": " << detail;
		log_ << '\n';
		return mapped;
	}

	void sleep()
	{
		runtime_.sleep_ms(config_.poll_interval_ms);
	}

private:
	Runtime &runtime_;
	const PlaylistConfig &config_;
	std::ostream &log_;
	std::uint64_t next_main_probe_;
};

bool deadline_reached(Runtime &runtime, std::uint64_t deadline,
		std::uint64_t timeout_ms)
{
	return timeout_ms != 0 && runtime.monotonic_ms() >= deadline;
}

bool is_fatal(const PlaybackStatus &status)
{
	return status.state == PlaybackState::Fatal || status.error != 0;
}

void log_status(std::ostream &log, const PlaybackStatus &status,
		PlaybackStatus &last, bool &last_valid)
{
	if (last_valid && last.session == status.session &&
	    last.state == status.state && last.error == status.error &&
	    last.loop_valid == status.loop_valid &&
	    last.loop_count == status.loop_count)
		return;
	log << "session=" << status.session << ' '
	    << megavgm_autoplay2::state_name(status.state);
	if (status.error != 0) {
		log << " error=" << std::uppercase << std::hex << std::setw(2)
		    << std::setfill('0') << static_cast<unsigned int>(status.error)
		    << std::dec << std::nouppercase << std::setfill(' ');
	}
	if (status.version >= 2) {
		log << " loop_valid=" << (status.loop_valid ? 1 : 0)
		    << " loop_count=" << status.loop_count;
	}
	log << '\n';
	last = status;
	last_valid = true;
}

void log_fatal(std::ostream &log, std::size_t index, std::size_t count,
		const Track &track, const PlaybackStatus &status)
{
	log << '[' << index + 1 << '/' << count << "] FATAL session="
	    << status.session << " error=" << std::uppercase << std::hex
	    << std::setw(2) << std::setfill('0')
	    << static_cast<unsigned int>(status.error)
	    << std::dec << std::nouppercase << std::setfill(' ')
	    << " path=" << track.path << " -- skipping\n";
}

PlaylistResult suspend(std::ostream &log)
{
	log << "PLAYLIST SUSPENDED: manual/external load detected\n";
	return PlaylistResult::Suspended;
}

} // namespace

const char *discovery_result_name(DiscoveryResult result)
{
	switch (result) {
	case DiscoveryResult::Ok: return "OK";
	case DiscoveryResult::OpenFailed: return "DIRECTORY_OPEN_FAILED";
	case DiscoveryResult::ReadFailed: return "DIRECTORY_READ_FAILED";
	case DiscoveryResult::Empty: return "NO_VGM_FILES";
	}
	return "DIRECTORY_ERROR";
}

const char *playlist_result_name(PlaylistResult result)
{
	switch (result) {
	case PlaylistResult::Complete: return "PLAYLIST COMPLETE";
	case PlaylistResult::Suspended: return "PLAYLIST SUSPENDED";
	case PlaylistResult::StatusFileMissing: return "STATUS_FILE_MISSING";
	case PlaylistResult::MalformedStatus: return "MALFORMED_STATUS";
	case PlaylistResult::UnsupportedVersion: return "INVALID_VERSION";
	case PlaylistResult::StatusIoError: return "STATUS_IO_ERROR";
	case PlaylistResult::ActiveMainUnavailable: return "ACTIVE_MAIN_UNAVAILABLE";
	case PlaylistResult::InvalidTrackPath: return "INVALID_TRACK_PATH";
	case PlaylistResult::CommandWriteFailed: return "COMMAND_WRITE_FAILED";
	case PlaylistResult::TrackSessionTimeout: return "TRACK_SESSION_TIMEOUT";
	case PlaylistResult::TrackNeverPlaying: return "TRACK_NEVER_PLAYING";
	case PlaylistResult::TrackEndTimeout: return "TRACK_END_TIMEOUT";
	}
	return "PLAYLIST_ERROR";
}

DiscoveryResult discover_directory(const std::string &directory,
		std::vector<Track> &tracks, std::string &detail)
{
	tracks.clear();
	DIR *stream = opendir(directory.c_str());
	if (!stream) {
		detail = std::strerror(errno);
		return DiscoveryResult::OpenFailed;
	}

	const int directory_fd = dirfd(stream);
	if (directory_fd < 0) {
		detail = std::strerror(errno);
		closedir(stream);
		return DiscoveryResult::ReadFailed;
	}
	int read_errno = 0;
	for (;;) {
		errno = 0;
		struct dirent *entry = readdir(stream);
		if (!entry) {
			read_errno = errno;
			break;
		}
		const std::string name(entry->d_name);
		if (name.empty() || name.front() == '.' || !has_exact_vgm_suffix(name))
			continue;

		struct stat attributes = {};
		if (fstatat(directory_fd, entry->d_name, &attributes, 0) < 0) {
			if (errno == ENOENT) continue;
			detail = std::string(entry->d_name) + ": " + std::strerror(errno);
			closedir(stream);
			return DiscoveryResult::ReadFailed;
		}
		if (!S_ISREG(attributes.st_mode)) continue;
		tracks.push_back({name, join_path(directory, name)});
	}

	if (closedir(stream) < 0 && read_errno == 0) {
		detail = std::strerror(errno);
		return DiscoveryResult::ReadFailed;
	}
	if (read_errno != 0) {
		detail = std::strerror(read_errno);
		return DiscoveryResult::ReadFailed;
	}

	std::sort(tracks.begin(), tracks.end(), bytewise_less);
	if (tracks.empty()) {
		detail = "directory contains no direct regular files ending in .vgm";
		return DiscoveryResult::Empty;
	}
	detail.clear();
	return DiscoveryResult::Ok;
}

PlaylistResult run(Runtime &runtime, const PlaylistConfig &config,
		const std::vector<Track> &tracks, std::ostream &log)
{
	Monitor monitor(runtime, config, log);
	PlaybackStatus status;
	PlaylistResult result = monitor.read(status);
	if (result != PlaylistResult::Complete) return result;
	std::uint32_t baseline_session = status.session;
	std::size_t skipped = 0;

	for (std::size_t index = 0; index < tracks.size(); ++index) {
		const Track &track = tracks[index];
		log << '\n' << '[' << index + 1 << '/' << tracks.size() << "] "
		    << track.name << '\n';

		std::string command;
		std::string detail;
		if (!megavgm_autoplay2::build_load_command(track.path, command, detail)) {
			log << "INVALID_TRACK_PATH: " << detail << '\n';
			return PlaylistResult::InvalidTrackPath;
		}
		if (!runtime.issue_load(track.path, detail)) {
			log << "COMMAND_WRITE_FAILED: " << detail << '\n';
			return PlaylistResult::CommandWriteFailed;
		}

		PlaybackStatus last_logged;
		bool last_logged_valid = false;
		bool have_session = false;
		bool playing = false;
		bool ended = false;
		bool fatal = false;
		bool loop_limit_reached = false;
		std::uint32_t owned_session = 0;
		std::uint64_t deadline = runtime.monotonic_ms() + config.session_timeout_ms;

		while (!have_session) {
			result = monitor.read(status);
			if (result != PlaylistResult::Complete) return result;
			if (status.session != baseline_session) {
				owned_session = status.session;
				have_session = true;
				log_status(log, status, last_logged, last_logged_valid);
				fatal = is_fatal(status);
				playing = status.state == PlaybackState::Playing;
				ended = status.state == PlaybackState::Ended;
				loop_limit_reached = playing && status.loop_valid &&
					config.loop_limit != 0 &&
					status.loop_count >= config.loop_limit;
			}
			if (!have_session && deadline_reached(runtime, deadline,
					config.session_timeout_ms)) {
				log << "TRACK_SESSION_TIMEOUT\n";
				return PlaylistResult::TrackSessionTimeout;
			}
			if (!have_session) monitor.sleep();
		}

		deadline = runtime.monotonic_ms() + config.playing_timeout_ms;
		while (!playing && !fatal && !ended) {
			monitor.sleep();
			result = monitor.read(status);
			if (result != PlaylistResult::Complete) return result;
			if (status.session != owned_session) return suspend(log);
			log_status(log, status, last_logged, last_logged_valid);
			fatal = is_fatal(status);
			playing = status.state == PlaybackState::Playing;
			ended = status.state == PlaybackState::Ended;
			loop_limit_reached = playing && status.loop_valid &&
				config.loop_limit != 0 &&
				status.loop_count >= config.loop_limit;
			if (!playing && !fatal && !ended &&
			    deadline_reached(runtime, deadline, config.playing_timeout_ms)) {
				log << "TRACK_NEVER_PLAYING\n";
				return PlaylistResult::TrackNeverPlaying;
			}
		}

		if (fatal) {
			log_fatal(log, index, tracks.size(), track, status);
			baseline_session = owned_session;
			skipped++;
			continue;
		}
		if (ended && !playing) {
			log << "TRACK_NEVER_PLAYING: ENDED before PLAYING\n";
			return PlaylistResult::TrackNeverPlaying;
		}

		deadline = runtime.monotonic_ms() + config.end_timeout_ms;
		while (!ended && !fatal && !loop_limit_reached) {
			monitor.sleep();
			result = monitor.read(status);
			if (result != PlaylistResult::Complete) return result;
			if (status.session != owned_session) return suspend(log);
			log_status(log, status, last_logged, last_logged_valid);
			fatal = is_fatal(status);
			ended = status.state == PlaybackState::Ended;
			loop_limit_reached =
				(status.state == PlaybackState::Playing) &&
				status.loop_valid && config.loop_limit != 0 &&
				status.loop_count >= config.loop_limit;
			if (!ended && !fatal && !loop_limit_reached &&
			    deadline_reached(runtime, deadline,
					config.end_timeout_ms)) {
				log << "TRACK_END_TIMEOUT\n";
				return PlaylistResult::TrackEndTimeout;
			}
		}

		baseline_session = owned_session;
		if (fatal) {
			log_fatal(log, index, tracks.size(), track, status);
			skipped++;
		}
		else if (loop_limit_reached) {
			log << "loop limit reached=" << config.loop_limit << '\n';
		}
	}

	log << '\n' << "PLAYLIST COMPLETE\n";
	if (skipped != 0) log << "skipped=" << skipped << '\n';
	return PlaylistResult::Complete;
}

} // namespace megavgm_playlist
