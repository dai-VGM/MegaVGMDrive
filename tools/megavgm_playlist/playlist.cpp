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

std::string parent_path(const std::string &path)
{
	const std::size_t separator = path.find_last_of('/');
	if (separator == std::string::npos) return {};
	return separator == 0 ? "/" : path.substr(0, separator);
}

bool find_track(const std::vector<Track> &tracks, const std::string &path,
		std::size_t &index)
{
	for (std::size_t candidate = 0; candidate < tracks.size(); ++candidate) {
		if (tracks[candidate].path == path) {
			index = candidate;
			return true;
		}
	}
	return false;
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
	case PlaylistResult::StopCommandFailed: return "STOP_COMMAND_FAILED";
	case PlaylistResult::StopTimeout: return "STOP_TIMEOUT";
	case PlaylistResult::ControlIoError: return "CONTROL_IO_ERROR";
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
		const std::vector<Track> &tracks, std::ostream &log,
		ControllerIo *controller)
{
	Monitor monitor(runtime, config, log);
	PlaybackStatus status;
	PlaylistResult result = monitor.read(status);
	if (result != PlaylistResult::Complete) return result;
	std::uint32_t baseline_session = status.session;
	log << "INITIAL_FPGA_SESSION=" << baseline_session << '\n';
	std::size_t skipped = 0;
	std::vector<Track> active_tracks = tracks;
	std::string active_playlist_name;
	if (active_tracks.empty() || config.start_index >= active_tracks.size())
		return PlaylistResult::InvalidTrackPath;
	std::size_t index = config.start_index;
	PlaybackPreferences preferences;
	if (controller) {
		std::string preference_detail;
		if (!controller->load_preferences(preferences, preference_detail)) {
			log << "PLAYBACK_MODE_DEFAULTS";
			if (!preference_detail.empty()) log << ": " << preference_detail;
			log << '\n';
		}
	}
	XorShiftRandom default_random(static_cast<std::uint32_t>(
		runtime.monotonic_ms() ^ baseline_session ^ 0xa511e9b3u));
	RandomSource &random = config.random_source ? *config.random_source : default_random;
	PlaybackTraversal traversal(random);
	traversal.reset(active_tracks.size(), index, preferences);

	auto control_error = [&](const char *operation,
			const std::string &detail) -> PlaylistResult {
		log << "CONTROL_IO_ERROR: " << operation;
		if (!detail.empty()) log << ": " << detail;
		log << '\n';
		return PlaylistResult::ControlIoError;
	};
	auto publish = [&](const char *state, const Track &track,
			std::uint32_t session, std::uint16_t loop_count) -> bool {
		if (!controller) return true;
		ControllerSnapshot snapshot;
		snapshot.state = state;
		snapshot.index = index < active_tracks.size() ? index + 1 : active_tracks.size();
		snapshot.count = active_tracks.size();
		snapshot.path = track.path;
		snapshot.session = session;
		snapshot.loop_count = loop_count;
		snapshot.context = active_playlist_name.empty() ? "DIRECTORY" : "PLAYLIST";
		snapshot.playlist = active_playlist_name;
		snapshot.repeat = preferences.repeat;
		snapshot.shuffle = preferences.shuffle;
		snapshot.traversal = preferences.shuffle ? "SHUFFLE" : "ORDERED";
		std::string detail;
		if (controller->publish(snapshot, detail)) return true;
		control_error("status publish", detail);
		return false;
	};
	auto discard_commands = [&]() -> bool {
		if (!controller) return true;
		std::string detail;
		if (controller->discard_commands(detail)) return true;
		control_error("command discard", detail);
		return false;
	};
	auto apply_mode_command = [&](const ControlCommand &command,
			const Track &track, const char *state, std::uint32_t session,
			std::uint16_t loop_count) -> bool {
		if (command.type != ControlCommandType::Repeat &&
		    command.type != ControlCommandType::Shuffle)
			return false;
		if (command.type == ControlCommandType::Repeat)
			preferences.repeat = command.repeat;
		else
			preferences.shuffle = command.shuffle;
		traversal.set_preferences(preferences, index);
		log << "playback_mode repeat=" << repeat_mode_name(preferences.repeat)
		    << " shuffle=" << (preferences.shuffle ? 1 : 0) << '\n';
		if (controller) {
			std::string save_detail;
			if (!controller->save_preferences(preferences, save_detail)) {
				log << "PLAYBACK_MODE_PERSIST_FAILED";
				if (!save_detail.empty()) log << ": " << save_detail;
				log << '\n';
			}
		}
		return publish(state, track, session, loop_count);
	};
	auto loop_limit_applies = [&](const PlaybackStatus &value) -> bool {
		return value.state == PlaybackState::Playing && value.loop_valid &&
			config.loop_limit != 0 && value.loop_count >= config.loop_limit &&
			preferences.repeat != RepeatMode::One;
	};
	auto complete = [&](const Track &track, std::uint32_t session,
			std::uint16_t loop_count) -> PlaylistResult {
		if (!publish("COMPLETE", track, session, loop_count))
			return PlaylistResult::ControlIoError;
		log << '\n' << "PLAYLIST COMPLETE\n";
		if (skipped != 0) log << "skipped=" << skipped << '\n';
		return PlaylistResult::Complete;
	};

	while (index < active_tracks.size()) {
		const Track track = active_tracks[index];
		log << '\n' << '[' << index + 1 << '/' << active_tracks.size() << "] "
		    << track.name << '\n';
		const std::uint64_t request_started_ms = runtime.monotonic_ms();
		log << "LOAD_FILE_REQUEST path=" << track.path
		    << " baseline_session=" << baseline_session << '\n';

		std::string command;
		std::string detail;
		if (!megavgm_autoplay2::build_load_command(track.path, command, detail)) {
			log << "INVALID_TRACK_PATH: " << detail << '\n';
			return PlaylistResult::InvalidTrackPath;
		}
		// Commands received before or during an owned load are ignored. This
		// prevents rapid commands from creating overlapping Main transfers.
		if (!discard_commands()) return PlaylistResult::ControlIoError;
		if (!runtime.issue_load(track.path, detail)) {
			log << "COMMAND_WRITE_FAILED: " << detail << '\n';
			return PlaylistResult::CommandWriteFailed;
		}
		log << "MISTER_CMD_WRITE=SUCCESS path=" << track.path << '\n';
		if (!publish("LOADING", track, baseline_session, 0))
			return PlaylistResult::ControlIoError;

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
			if (!discard_commands()) return PlaylistResult::ControlIoError;
			result = monitor.read(status);
			if (result != PlaylistResult::Complete) return result;
			if (status.session != baseline_session) {
				owned_session = status.session;
				have_session = true;
				log_status(log, status, last_logged, last_logged_valid);
				fatal = is_fatal(status);
				playing = status.state == PlaybackState::Playing;
				ended = status.state == PlaybackState::Ended;
				loop_limit_reached = loop_limit_applies(status);
				if (!publish(megavgm_autoplay2::state_name(status.state), track,
						status.session, status.loop_count))
					return PlaylistResult::ControlIoError;
			}
			if (!have_session && deadline_reached(runtime, deadline,
					config.session_timeout_ms)) {
				log << "TRACK_SESSION_TIMEOUT initial_session="
				    << baseline_session << " fpga_session_after="
				    << status.session << " elapsed_ms="
				    << (runtime.monotonic_ms() - request_started_ms)
				    << " path=" << track.path << '\n';
				return PlaylistResult::TrackSessionTimeout;
			}
			if (!have_session) monitor.sleep();
		}

		deadline = runtime.monotonic_ms() + config.playing_timeout_ms;
		while (!playing && !fatal && !ended) {
			monitor.sleep();
			if (!discard_commands()) return PlaylistResult::ControlIoError;
			result = monitor.read(status);
			if (result != PlaylistResult::Complete) return result;
			if (status.session != owned_session) {
				if (!publish("SUSPENDED", track, status.session,
						status.loop_count))
					return PlaylistResult::ControlIoError;
				return suspend(log);
			}
			log_status(log, status, last_logged, last_logged_valid);
			if (!publish(megavgm_autoplay2::state_name(status.state), track,
					status.session, status.loop_count))
				return PlaylistResult::ControlIoError;
			fatal = is_fatal(status);
			playing = status.state == PlaybackState::Playing;
			ended = status.state == PlaybackState::Ended;
			loop_limit_reached = loop_limit_applies(status);
			if (!playing && !fatal && !ended &&
			    deadline_reached(runtime, deadline, config.playing_timeout_ms)) {
				log << "TRACK_NEVER_PLAYING\n";
				return PlaylistResult::TrackNeverPlaying;
			}
		}

		if (fatal) {
			log_fatal(log, index, active_tracks.size(), track, status);
			baseline_session = owned_session;
			skipped++;
			std::size_t selected = index;
			if (traversal.next(index, false, false, selected) ==
					TraversalResult::Complete)
				return complete(track, owned_session, status.loop_count);
			index = selected;
			continue;
		}
		if (ended && !playing) {
			log << "TRACK_NEVER_PLAYING: ENDED before PLAYING\n";
			return PlaylistResult::TrackNeverPlaying;
		}

		// A command already waiting when PLAYING is first observed belongs to
		// the just-finished load window and is intentionally discarded. Mode
		// commands and STOP are retained by ControllerIo because they must not
		// be lost at the PLAYING publication boundary.
		if (!discard_commands()) return PlaylistResult::ControlIoError;
		bool stop_claimed = false;
		ControlCommand control_command;
		if (controller) {
			for (;;) {
				ControlCommand retained;
				std::string retained_detail;
				const ControlPollResult retained_result =
					controller->poll_command(retained, retained_detail);
				if (retained_result == ControlPollResult::None) break;
				if (retained_result == ControlPollResult::IoError)
					return control_error("command read", retained_detail);
				if (retained_result == ControlPollResult::Invalid) {
					log << "CONTROL_IGNORED";
					if (!retained_detail.empty()) log << ": " << retained_detail;
					log << '\n';
					continue;
				}
				if (retained.type == ControlCommandType::Stop) {
					control_command = retained;
					stop_claimed = true;
					break;
				} else if (retained.type == ControlCommandType::Repeat ||
				    retained.type == ControlCommandType::Shuffle) {
					if (!apply_mode_command(retained, track, "PLAYING",
							owned_session, status.loop_count))
						return PlaylistResult::ControlIoError;
				} else {
					// A navigation command cannot survive discard_commands().
					log << "CONTROL_IGNORED: stale navigation after load\n";
				}
			}
			loop_limit_reached = loop_limit_applies(status);
		}
		bool navigation_claimed = false;
		std::vector<Track> replacement_tracks;
		std::size_t replacement_index = 0;
		std::string replacement_playlist_name;
		deadline = runtime.monotonic_ms() + config.end_timeout_ms;
		while (!ended && !fatal && !loop_limit_reached && !stop_claimed) {
			monitor.sleep();
			if (controller) {
				std::string control_detail;
				const ControlPollResult control_result =
					controller->poll_command(control_command, control_detail);
				if (control_result == ControlPollResult::IoError)
					return control_error("command read", control_detail);
				if (control_result == ControlPollResult::Invalid) {
					log << "CONTROL_IGNORED";
					if (!control_detail.empty()) log << ": " << control_detail;
					log << '\n';
				} else if (control_result == ControlPollResult::Command) {
					if (control_command.type == ControlCommandType::Stop) {
						stop_claimed = true;
						break;
					}
					if (control_command.type == ControlCommandType::Repeat ||
					    control_command.type == ControlCommandType::Shuffle) {
						if (!apply_mode_command(control_command, track, "PLAYING",
								owned_session, status.loop_count))
							return PlaylistResult::ControlIoError;
						loop_limit_reached = loop_limit_applies(status);
						continue;
					}
					if (control_command.type == ControlCommandType::Play) {
						const DiscoveryResult discovery = discover_directory(
							parent_path(control_command.path), replacement_tracks,
							control_detail);
						if (discovery != DiscoveryResult::Ok ||
						    !find_track(replacement_tracks, control_command.path,
								replacement_index)) {
							log << "CONTROL_IGNORED: invalid PLAY selection";
							if (!control_detail.empty()) log << ": " << control_detail;
							log << '\n';
							continue;
						}
						replacement_playlist_name.clear();
					} else if (control_command.type == ControlCommandType::Playlist) {
						PlaylistSnapshot snapshot;
						if (!load_playlist_snapshot(control_command.path,
								config.approved_root, snapshot,
								control_detail, true)) {
							log << "CONTROL_IGNORED: invalid PLAYLIST snapshot";
							if (!control_detail.empty()) log << ": " << control_detail;
							log << '\n';
							continue;
						}
						replacement_tracks.clear();
						for (const std::string &path : snapshot.paths) {
							const std::size_t separator = path.find_last_of('/');
							replacement_tracks.push_back({
								separator == std::string::npos ? path : path.substr(separator + 1), path});
						}
						replacement_index = snapshot.start_index;
						replacement_playlist_name = snapshot.name;
						if (replacement_tracks[replacement_index].path == track.path) {
							active_tracks = std::move(replacement_tracks);
							index = replacement_index;
							active_playlist_name = replacement_playlist_name;
							traversal.reset(active_tracks.size(), index, preferences);
							log << "navigation=PLAYLIST adopt_current=1 name="
							    << active_playlist_name << " index=" << index + 1 << '\n';
							if (!publish("PLAYING", track, owned_session,
									status.loop_count))
								return PlaylistResult::ControlIoError;
							continue;
						}
					}
					navigation_claimed = true;
					break;
				}
			}
			result = monitor.read(status);
			if (result != PlaylistResult::Complete) return result;
			if (status.session != owned_session) {
				if (!publish("SUSPENDED", track, status.session,
						status.loop_count))
					return PlaylistResult::ControlIoError;
				return suspend(log);
			}
			log_status(log, status, last_logged, last_logged_valid);
			if (!publish(megavgm_autoplay2::state_name(status.state), track,
					status.session, status.loop_count))
				return PlaylistResult::ControlIoError;
			fatal = is_fatal(status);
			ended = status.state == PlaybackState::Ended;
			loop_limit_reached = loop_limit_applies(status);
			if (!ended && !fatal && !loop_limit_reached &&
			    deadline_reached(runtime, deadline,
					config.end_timeout_ms)) {
				log << "TRACK_END_TIMEOUT\n";
				return PlaylistResult::TrackEndTimeout;
			}
		}

		std::uint32_t next_baseline_session = owned_session;
		if (stop_claimed) {
			std::string stop_detail;
			if (!runtime.issue_stop(stop_detail)) {
				log << "STOP_COMMAND_FAILED";
				if (!stop_detail.empty()) log << ": " << stop_detail;
				log << '\n';
				return PlaylistResult::StopCommandFailed;
			}
			log << "MISTER_CMD_STOP=SUCCESS path=" << track.path << '\n';
			const std::uint64_t stop_deadline =
				runtime.monotonic_ms() + config.stop_timeout_ms;
			for (;;) {
				result = monitor.read(status);
				if (result != PlaylistResult::Complete) return result;
				log_status(log, status, last_logged, last_logged_valid);
				if (status.state == PlaybackState::Idle) break;
				if (deadline_reached(runtime, stop_deadline,
						config.stop_timeout_ms)) {
					log << "STOP_TIMEOUT fpga_session=" << status.session
					    << " state=" << megavgm_autoplay2::state_name(status.state)
					    << '\n';
					return PlaylistResult::StopTimeout;
				}
				monitor.sleep();
			}
			next_baseline_session = status.session;
			if (!publish("STOPPED", track, owned_session, status.loop_count))
				return PlaylistResult::ControlIoError;
			log << "PLAYBACK STOPPED retained_session=" << owned_session
			    << " fpga_session=" << status.session
			    << " path=" << track.path << '\n';

			// STOPPED is a controller-owned transport state layered on top of the
			// FPGA's reset IDLE state. Keep the selected source and traversal
			// context, and do not advance until an explicit transport command.
			for (;;) {
				std::string control_detail;
				const ControlPollResult control_result = controller->poll_command(
					control_command, control_detail);
				if (control_result == ControlPollResult::IoError)
					return control_error("command read", control_detail);
				if (control_result == ControlPollResult::Invalid) {
					log << "CONTROL_IGNORED";
					if (!control_detail.empty()) log << ": " << control_detail;
					log << '\n';
				} else if (control_result == ControlPollResult::Command) {
					if (control_command.type == ControlCommandType::Repeat ||
					    control_command.type == ControlCommandType::Shuffle) {
						if (!apply_mode_command(control_command, track, "STOPPED",
								owned_session, status.loop_count))
							return PlaylistResult::ControlIoError;
						continue;
					}
					if (control_command.type == ControlCommandType::Stop) {
						// STOP is deliberately idempotent while already stopped.
						continue;
					}
					if (control_command.type == ControlCommandType::Play) {
						const DiscoveryResult discovery = discover_directory(
							parent_path(control_command.path), replacement_tracks,
							control_detail);
						if (discovery != DiscoveryResult::Ok ||
						    !find_track(replacement_tracks, control_command.path,
								replacement_index)) {
							log << "CONTROL_IGNORED: invalid PLAY selection";
							if (!control_detail.empty()) log << ": " << control_detail;
							log << '\n';
							continue;
						}
						replacement_playlist_name.clear();
					} else if (control_command.type == ControlCommandType::Playlist) {
						PlaylistSnapshot snapshot;
						if (!load_playlist_snapshot(control_command.path,
								config.approved_root, snapshot,
								control_detail, true)) {
							log << "CONTROL_IGNORED: invalid PLAYLIST snapshot";
							if (!control_detail.empty()) log << ": " << control_detail;
							log << '\n';
							continue;
						}
						replacement_tracks.clear();
						for (const std::string &path : snapshot.paths) {
							const std::size_t separator = path.find_last_of('/');
							replacement_tracks.push_back({separator == std::string::npos ?
								path : path.substr(separator + 1), path});
						}
						replacement_index = snapshot.start_index;
						replacement_playlist_name = snapshot.name;
					}
					navigation_claimed = true;
					break;
				}

				result = monitor.read(status);
				if (result != PlaylistResult::Complete) return result;
				if (status.session != next_baseline_session ||
				    status.state != PlaybackState::Idle) {
					if (!publish("SUSPENDED", track, status.session,
							status.loop_count))
						return PlaylistResult::ControlIoError;
					return suspend(log);
				}
				monitor.sleep();
			}
		}

		baseline_session = next_baseline_session;
		if (navigation_claimed) {
			log << "navigation=" << control_command_name(control_command.type);
			if (control_command.type == ControlCommandType::Play ||
			    control_command.type == ControlCommandType::Playlist)
				log << " path=" << control_command.path;
			log << '\n';
			if (!publish(control_command_name(control_command.type), track,
					owned_session, status.loop_count))
				return PlaylistResult::ControlIoError;
			if (control_command.type == ControlCommandType::Play) {
				active_tracks = std::move(replacement_tracks);
				index = replacement_index;
				active_playlist_name.clear();
				traversal.reset(active_tracks.size(), index, preferences);
			} else if (control_command.type == ControlCommandType::Playlist) {
				active_tracks = std::move(replacement_tracks);
				index = replacement_index;
				active_playlist_name = replacement_playlist_name;
				traversal.reset(active_tracks.size(), index, preferences);
			} else if (control_command.type == ControlCommandType::Next) {
				std::size_t selected = index;
				if (traversal.next(index, false, false, selected) ==
						TraversalResult::Complete)
					return complete(track, owned_session, status.loop_count);
				index = selected;
			} else {
				std::size_t selected = index;
				traversal.previous(index, selected);
				index = selected;
			}
			continue;
		}
		if (fatal) {
			log_fatal(log, index, active_tracks.size(), track, status);
			skipped++;
		}
		else if (loop_limit_reached) {
			log << "loop limit reached=" << config.loop_limit << '\n';
		}
		std::size_t selected = index;
		const TraversalResult advance = traversal.next(index, true,
			status.loop_valid, selected);
		if (advance == TraversalResult::Complete)
			return complete(track, owned_session, status.loop_count);
		// Repeat One with a native loop never reaches here because its loop limit
		// is suppressed. Stay is retained as a defensive no-reload outcome.
		if (advance == TraversalResult::Stay) continue;
		index = selected;
	}

	return active_tracks.empty() ? PlaylistResult::InvalidTrackPath :
		complete(active_tracks[index < active_tracks.size() ? index :
			active_tracks.size() - 1], baseline_session, status.loop_count);
}

} // namespace megavgm_playlist
