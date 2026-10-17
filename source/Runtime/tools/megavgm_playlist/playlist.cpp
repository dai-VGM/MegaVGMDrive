#include "playlist.h"
#include "playback_deadline.h"
#include "../megavgm_rbf_bench/latency_log.h"

#include <algorithm>
#include <cerrno>
#include <cstring>
#include <dirent.h>
#include <iomanip>
#include <iostream>
#include <sys/stat.h>

namespace megavgm_playlist {
namespace {

// Keep this exact, case-sensitive set synchronized with
// megavgm_profile/track_file.h and Remote supportedTrackName.
bool has_exact_track_suffix(const std::string &name)
{
	return (name.size() > 4 && name.compare(name.size() - 4, 4, ".vgm") == 0) ||
		(name.size() > 8 && name.compare(name.size() - 8, 8, ".mvgmsid") == 0) ||
		is_raw_sid_name(name) || is_native_container_name(name);
}

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
		if (name.empty() || name.front() == '.' || !has_exact_track_suffix(name))
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
		detail = "directory contains no direct regular .vgm, .mvgmsid or .sid files";
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
	std::string active_playlist_name = config.initial_playlist_name;
	if (active_tracks.empty() || config.start_index >= active_tracks.size())
		return PlaylistResult::InvalidTrackPath;
	std::size_t index = config.start_index;
	// Origin belongs to Controller queue intent, not file/engine classification.
	// A direct selection never inherits automatic error recovery.
	bool automatic_selection = false;
	std::vector<bool> capacity_rejected(active_tracks.size(), false);
	std::size_t capacity_attempts = 0;
	auto reset_capacity_chain = [&](bool automatic) {
		automatic_selection = automatic;
		capacity_rejected.assign(active_tracks.size(), false);
		capacity_attempts = 0;
	};
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
	std::string classified_path, classified_chips;
	std::string load_error, load_error_detail;
	megavgm_profile::SidMetadata classified_sid;
	megavgm_profile::PlaybackTiming classified_timing;
 PreparedPlaybackTiming classified_deadline;
	std::string elapsed_path;
	std::uint32_t elapsed_session = 0;
	std::uint64_t playing_started_ms = 0;
	std::uint64_t elapsed_ms = 0;
	bool elapsed_running = false;
	auto publish = [&](const char *state, const Track &track,
			std::uint32_t session, std::uint16_t loop_count) -> bool {
		if (!controller) return true;
		const std::string state_value(state);
		const std::uint64_t now = runtime.monotonic_ms();
		if (track.path != elapsed_path || state_value == "PREPARING" ||
		    state_value == "LOADING") {
			elapsed_path = track.path;
			elapsed_session = session;
			playing_started_ms = 0;
			elapsed_ms = 0;
			elapsed_running = false;
		}
		if (state_value == "PLAYING") {
			if (!elapsed_running || elapsed_session != session) {
				elapsed_session = session;
				playing_started_ms = now;
				elapsed_ms = 0;
				elapsed_running = true;
			}
			elapsed_ms = now - playing_started_ms;
		} else if (elapsed_running) {
			elapsed_ms = now - playing_started_ms;
			elapsed_running = false;
		}
		if (state_value == "STOPPED") elapsed_ms = 0;
		ControllerSnapshot snapshot;
		snapshot.state = state;
		if (state_value == "STOPPED") {
			snapshot.load_error = load_error;
			snapshot.load_error_detail = load_error_detail;
		}
		snapshot.index = index < active_tracks.size() ? index + 1 : active_tracks.size();
		snapshot.count = active_tracks.size();
		snapshot.path = track.path;
		// Same atomic record as path/session; never carry metadata to another target.
		if (track.path == classified_path) {
			snapshot.sound_chips = classified_chips;
			snapshot.sid_format_version = classified_sid.format_version;
			snapshot.sid_model = classified_sid.model;
			snapshot.sid_timing = classified_sid.timing;
			snapshot.sid_subtune = classified_sid.subtune;
			snapshot.sid_capture_limited = classified_sid.capture_limited;
			snapshot.sid_source_sha256 = classified_sid.source_sha256;
		}
		snapshot.session = session;
		snapshot.loop_count = loop_count;
		snapshot.elapsed_ms = elapsed_ms;
		if (preferences.repeat == RepeatMode::One) {
			snapshot.planned_duration = "INFINITE";
			snapshot.duration_source = "REPEAT_ONE";
		} else if (track.path == classified_path && classified_deadline.valid) {
   snapshot.planned_duration = "FINITE";
   // Remote requires a positive finite duration; sub-100ms targets still
   // incur the unchanged transport tail. Preserve raw target in timer/logs.
   snapshot.planned_duration_ms = std::max<std::uint64_t>(classified_deadline.target_ms, 100);
   snapshot.duration_source = "NATIVE_METADATA_END_TARGET_100MS_FADE_APPROXIMATION";
  } else if (track.path == classified_path && classified_timing.loop_valid) {
			if (config.loop_limit == 0) {
				snapshot.planned_duration = "INFINITE";
				snapshot.duration_source = "NATIVE_LOOP";
			} else if (classified_timing.duration_valid &&
			           classified_timing.loop_duration_ms != 0 &&
			           config.loop_limit <= (UINT64_MAX -
			               classified_timing.duration_ms) /
			               classified_timing.loop_duration_ms + 1u) {
				snapshot.planned_duration = "FINITE";
				snapshot.planned_duration_ms = classified_timing.duration_ms +
					(static_cast<std::uint64_t>(config.loop_limit) - 1u) *
					classified_timing.loop_duration_ms;
				snapshot.duration_source = classified_timing.source +
					(config.loop_limit == 2 ? "+TWO_LOOPS" : "+LOOP_LIMIT");
			}
		} else if (track.path == classified_path &&
		           classified_timing.duration_valid &&
		           classified_timing.duration_ms <= UINT64_MAX - 100u) {
			// Production Transport owns a 100 ms fade after natural non-loop EOF.
			snapshot.planned_duration = "FINITE";
			snapshot.planned_duration_ms = classified_timing.duration_ms + 100u;
			snapshot.duration_source = classified_timing.source +
				"+NATURAL_FADE_100MS";
		}
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
	// A mode change may arrive after the native two-loop window has passed.
	// Defer recovery until a fresh owned PLAYING status is observed.
#ifdef MEGAVGM_PHASE2A
    struct ProofLifetime {
        megavgm_profile::Client *client;
        ~ProofLifetime() { if(client) client->forget_session(); }
    } proof_lifetime{config.profile_client};
#endif
	bool repeat_recovery_pending = false;
	auto apply_mode_command = [&](const ControlCommand &command,
			const Track &track, const char *state, std::uint32_t session,
			std::uint16_t loop_count, bool publish_update) -> bool {
		if (command.type != ControlCommandType::Repeat &&
		    command.type != ControlCommandType::Shuffle)
			return false;
		if (command.type == ControlCommandType::Repeat) {
			std::string policy_detail;
			const bool two_loop_limit = config.loop_limit == 2 &&
				command.repeat != RepeatMode::One;
			if (!runtime.issue_transition(two_loop_limit ?
					megavgm_autoplay2::TransitionReason::LoopLimitTwoLoops :
					megavgm_autoplay2::TransitionReason::LoopLimitDisabled,
					policy_detail)) {
				log << "LOOP_LIMIT_POLICY_FAILED";
				if (!policy_detail.empty()) log << ": " << policy_detail;
				log << '\n';
				return false;
			}
#ifdef MEGAVGM_PHASE2A
            if (config.profile_client) config.profile_client->note_policy_control();
#endif
			if (command.repeat == RepeatMode::One || std::string(state) != "PLAYING")
				repeat_recovery_pending = false;
			else if (preferences.repeat == RepeatMode::One && two_loop_limit)
				repeat_recovery_pending = true;
			preferences.repeat = command.repeat;
		} else
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
		return !publish_update || publish(state, track, session, loop_count);
	};
	auto loop_limit_applies = [&](const PlaybackStatus &value) -> bool {
		return value.loop_valid &&
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

	std::uint64_t load_generation = 0;
#ifdef MEGAVGM_PHASE2A
	megavgm_profile::Reply lease;
#endif
	while (index < active_tracks.size()) {
		repeat_recovery_pending = false;
#ifdef MEGAVGM_PHASE2A
        if (config.profile_client) config.profile_client->forget_session();
#endif
		PreparedPlaybackTiming prepared_timing;
  classified_deadline = {};
		PlaybackDeadline metadata_deadline;
		std::string load_path = (is_raw_sid_name(active_tracks[index].name) || is_native_container_name(active_tracks[index].name)) ?
			std::string{} : active_tracks[index].path;
#ifdef MEGAVGM_PHASE2A
		if (config.profile_client) {
			// Cooperative park: no raw ENDED->next handling and no Main writes
			// here. The already-reserved index and traversal stay in this process.
			bool send = true, stopped = false, finish_after_stop = false, stop_confirmed = false;
			bool preparing_sid = false;
            bool capacity_skip_pending = false;
            // Reject only before Main/index1. Release the old resident through
            // the existing owner and wait for a real STOPPED lease. Do not
            // manufacture a new FPGA session. Only an automatic capacity
            // rejection may select another candidate after the real STOPPED lease.
            auto reject_track = [&](const std::string &code, std::string detail) {
                for (char &c : detail) if (static_cast<unsigned char>(c) < 32 || c == 127) c = ' ';
                load_error = code;
                load_error_detail = detail.substr(0, 512);
                classified_path.clear(); classified_chips.clear();
                classified_sid = {}; classified_timing = {}; classified_deadline = {};
                stopped = true; send = true; finish_after_stop = false;
                capacity_skip_pending = automatic_selection &&
                    code == "resource_capacity_exceeded";
                log << "TRACK_LOAD_REJECTED path=" << active_tracks[index].path
                    << " reason=" << code << " detail=" << load_error_detail << '\n';
            };
            SidPreparer *active_preparer = nullptr;
			std::uint64_t sid_prepare_generation = 0, active_sid_prepare_generation = 0;
			megavgm_profile::Request request;
			std::string last_profile_reply = "NONE";
			auto prepare_deadline = runtime.monotonic_ms() + config.session_timeout_ms;
			auto cancel_sid_prepare = [&](const char *reason) {
				prepared_timing = {};
                classified_deadline = {};
				if (!preparing_sid) { load_path.clear(); return; }
				const auto invalidated = active_sid_prepare_generation;
				preparing_sid = false; active_sid_prepare_generation = 0;
				++sid_prepare_generation; load_path.clear();
				const std::string cleanup_detail = active_preparer ?
					active_preparer->cancel() : std::string{};
				log << "SID_PREPARE_CANCEL generation=" << invalidated
				    << " reason=" << reason << '\n';
				if (!cleanup_detail.empty())
					log << "SID_TEMP_CLEANUP_FAILED generation=" << invalidated
					    << " detail=" << cleanup_detail << '\n';
			};
			for (;;) {
				std::string d;
				if (controller) {
					ControlCommand c;
					const auto polled = controller->poll_command(c, d);
					if (polled == ControlPollResult::IoError) return control_error("profile park", d);
					if (polled == ControlPollResult::Command) {
						if (c.type == ControlCommandType::Repeat || c.type == ControlCommandType::Shuffle) {
                            const PlaybackPreferences previous = preferences;
							// Defer policy transfer until the new lease. Never write to
							// an RBF while the Supervisor owns its teardown.
							if (c.type == ControlCommandType::Repeat) preferences.repeat = c.repeat;
							else preferences.shuffle = c.shuffle;
                            if (previous.repeat != preferences.repeat || previous.shuffle != preferences.shuffle)
                                reset_capacity_chain(automatic_selection);
							traversal.set_preferences(preferences, index);
							controller->save_preferences(preferences, d);
						} else if (c.type == ControlCommandType::Stop) {
							cancel_sid_prepare("STOP");
                            reset_capacity_chain(false); capacity_skip_pending = false;
							stopped = true; send = true; finish_after_stop = false;
						} else if (c.type == ControlCommandType::Next || c.type == ControlCommandType::Previous) {
							cancel_sid_prepare(c.type == ControlCommandType::Next ? "NEXT" : "PREVIOUS");
                            reset_capacity_chain(false); capacity_skip_pending = false;
							std::size_t selected = index;
							if (c.type == ControlCommandType::Next) {
								if (traversal.next(index, false, false, selected) == TraversalResult::Complete) {
									// Cancel pending load first; normal completion follows STOPPED.
								stopped = true;
								finish_after_stop = true;
								} else { index = selected; stopped = false; }
							} else { traversal.previous(index, selected); index = selected; stopped = false; }
							send = true;
						} else if (c.type == ControlCommandType::Play || c.type == ControlCommandType::Playlist) {
							std::vector<Track> replacement;
							std::size_t selected = 0;
							std::string playlist_name;
							bool ok = false;
							if (c.type == ControlCommandType::Play) {
								ok = discover_directory(parent_path(c.path), replacement, d) == DiscoveryResult::Ok &&
									find_track(replacement, c.path, selected);
							} else {
								PlaylistSnapshot snapshot;
								ok = load_playlist_snapshot(c.path, config.approved_root, snapshot, d, true);
								if (ok) {
									for (const auto &p : snapshot.paths) replacement.push_back({p.substr(p.find_last_of('/')+1), p});
									selected = snapshot.start_index; playlist_name = snapshot.name;
								}
							}
							if (ok) {
								cancel_sid_prepare(c.type == ControlCommandType::Play ? "PLAY" : "PLAYLIST");
								active_tracks = std::move(replacement); index = selected;
								active_playlist_name = playlist_name;
								traversal.reset(active_tracks.size(), index, preferences);
                                reset_capacity_chain(false);
                                capacity_skip_pending = false;
								stopped = false; send = true;
							} else log << "PROFILE_SELECTION_REJECTED " << d << '\n';
						}
						// Drain all already-arrived user intents before accepting a lease.
						continue;
					}
				}
				if (preparing_sid) {
					const auto prepared = active_preparer->poll(load_path, d);
					if (prepared == SidPreparePollResult::Running) {
						if (runtime.monotonic_ms() >= prepare_deadline) {
							cancel_sid_prepare("TIMEOUT");
							return PlaylistResult::TrackSessionTimeout;
						}
						runtime.sleep_ms(config.poll_interval_ms);
						continue;
					}
					preparing_sid = false; active_sid_prepare_generation = 0;
					if (prepared == SidPreparePollResult::Failed) {
						log << "SID_PREPARE_FAILED path=" << active_tracks[index].path
						    << " detail=" << d << '\n';
                        if (!controller) return PlaylistResult::InvalidTrackPath;
                        reject_track("track_prepare_failed", d);
                        continue;
					}
					prepared_timing = active_preparer->playback_timing();
                    classified_deadline = prepared_timing;
					log << "SID_PREPARE_READY source=" << active_tracks[index].path
					    << " artifact=" << load_path << '\n';
				}
				if (send) {
                    if (!stopped) { load_error.clear(); load_error_detail.clear(); }
					stop_confirmed = false;
					prepare_deadline = runtime.monotonic_ms() + config.session_timeout_ms;
					if (!stopped && load_path.empty() &&
					    (is_raw_sid_name(active_tracks[index].name) || is_native_container_name(active_tracks[index].name))) {
						active_preparer = is_native_container_name(active_tracks[index].name) ? config.native_preparer : config.sid_preparer;
                        if (!active_preparer) return control_error("container prepare", "preparer unavailable");
						if (!publish("PREPARING", active_tracks[index], baseline_session, 0))
							return PlaylistResult::ControlIoError;
						active_sid_prepare_generation = ++sid_prepare_generation;
						if (!active_preparer->start(active_tracks[index].path, d)) {
							active_sid_prepare_generation = 0;
							return control_error("SID prepare", d);
						}
						preparing_sid = true;
						prepare_deadline = runtime.monotonic_ms() +
							config.sid_prepare_timeout_ms;
						log << "SID_PREPARE_START generation=" << active_sid_prepare_generation
						    << " path=" << active_tracks[index].path << '\n';
						runtime.sleep_ms(config.poll_interval_ms);
						continue;
					}
					if (!stopped && load_path.empty()) load_path = active_tracks[index].path;
					const auto classified = stopped ? megavgm_profile::Classification{} :
						megavgm_profile::classify_file(load_path,
							is_raw_sid_name(active_tracks[index].name) ?
							config.sid_cache_root : (is_native_container_name(active_tracks[index].name) ? config.native_cache_root : config.approved_root));
					log << "PROFILE_CLASSIFY path=" << active_tracks[index].path << " result="
					    << megavgm_profile::name(classified.profile) << " detail=" << classified.detail << '\n';
					if (!stopped && classified.profile != megavgm_profile::Profile::A &&
					    classified.profile != megavgm_profile::Profile::B &&
					    classified.profile != megavgm_profile::Profile::C &&
					    classified.profile != megavgm_profile::Profile::D && classified.profile != megavgm_profile::Profile::E && classified.profile != megavgm_profile::Profile::F)
                    {
                        if (!controller) return PlaylistResult::InvalidTrackPath;
                        reject_track(classified.resource_capacity_exceeded ? "resource_capacity_exceeded" :
                            classified.profile == megavgm_profile::Profile::Error ? "invalid_track" : "unsupported_track",
                            classified.detail);
                        continue;
                    }
					classified_path = stopped ? "" : active_tracks[index].path;
					classified_chips = classified.sound_chips;
					classified_sid = stopped ? megavgm_profile::SidMetadata{} : classified.sid;
					classified_timing = stopped ? megavgm_profile::PlaybackTiming{} :
						classified.timing;
					request = {++load_generation, lease.domain, baseline_session, classified.profile, stopped,
						stopped ? active_tracks[index].path : load_path};
						if (!config.profile_client->begin(request, d)) return control_error("profile request", d);
						megavgm_rbf_bench::event("t0_controller_request_accepted",
							request.generation, megavgm_profile::status_name(lease.profile),
							megavgm_profile::status_name(request.profile));
					log << "PROFILE_PARK generation=" << request.generation << " domain=" << request.domain
					    << " reserved_index=" << index << " count=" << active_tracks.size() << '\n';
					if (!publish("LOADING", active_tracks[index], baseline_session, 0))
						return PlaylistResult::ControlIoError;
					send = false;
				}
                bool just_stopped = false;
				megavgm_profile::Reply response;
				if (config.profile_client->poll(response, d)) {
					if (response.generation == request.generation) {
						const std::string reply_trace = "generation=" +
							std::to_string(response.generation) + " domain=" +
							std::to_string(response.domain) + " state=" + response.state +
							" profile=" + std::to_string(static_cast<int>(response.profile)) +
							" baseline=" + std::to_string(response.baseline) +
							" detail=" + response.detail;
						if (reply_trace != last_profile_reply) {
							log << "PROFILE_REPLY " << reply_trace << '\n';
							last_profile_reply = reply_trace;
						}
						if (response.state == "FAILED") return control_error("profile prepare", response.detail);
						if (response.state == "READY" && !stopped && response.profile == request.profile) {
							lease = response; baseline_session = response.baseline;
							log << "PROFILE_REBIND generation=" << lease.generation << " domain=" << lease.domain
							    << " baseline=" << baseline_session << " Main=" << lease.main_identity << '\n';
							break;
						}
						if (response.state == "STOPPED" && stopped) {
							lease = response; baseline_session = response.baseline;
                            just_stopped = !stop_confirmed;
							if (!stop_confirmed && !publish("STOPPED", active_tracks[index], baseline_session, 0))
								return PlaylistResult::ControlIoError;
							stop_confirmed = true;
							if (finish_after_stop) return complete(active_tracks[index], baseline_session, 0);
						}
					}
				} else if (!d.empty()) return control_error("profile reply", d);
                if (stop_confirmed && !load_error.empty()) {
                    // A recoverable input error never excuses real owner loss.
                    PlaybackStatus parked;
                    const auto checked = monitor.read(parked);
                    if (checked != PlaylistResult::Complete) return checked;
                    if (parked.session != baseline_session || is_fatal(parked) ||
                        (parked.state != PlaybackState::Ended && parked.state != PlaybackState::Idle) ||
                        !config.profile_client->owns_parked(lease, d))
                        return control_error("rejected track owner", d);
                    if (capacity_skip_pending && just_stopped) continue;
                    if (capacity_skip_pending) {
                        // Consume once, after correlated STOPPED and live owner proof.
                        // No index1 upload/session/ENDED is invented for a refusal.
                        capacity_skip_pending = false;
                        capacity_rejected[index] = true;
                        ++capacity_attempts;
                        const bool all_rejected = std::all_of(capacity_rejected.begin(),
                            capacity_rejected.end(), [](bool value) { return value; });
                        traversal.reject_unplayed(index);
                        std::size_t selected = index;
                        const bool exhausted = all_rejected ||
                            capacity_attempts / 2 >= active_tracks.size() ||
                            traversal.next(index, true, false, selected) != TraversalResult::Track ||
                            (selected == index && preferences.repeat == RepeatMode::One);
                        log << "TRACK_LOAD_SKIPPED generation=" << request.generation
                            << " session=" << baseline_session << " index=" << index + 1
                            << " path=" << active_tracks[index].path
                            << " reason=resource_capacity_exceeded";
                        ++skipped;
                        if (exhausted) {
                            automatic_selection = false;
                            load_error_detail = "No playable candidate under current queue policy; " +
                                load_error_detail.substr(0, 440);
                            log << " action=STOPPED\nTRACK_SKIP_EXHAUSTED attempts="
                                << capacity_attempts << " count=" << active_tracks.size() << '\n';
                            if (!publish("STOPPED", active_tracks[index], baseline_session, 0))
                                return PlaylistResult::ControlIoError;
                        } else {
                            log << " action=LOAD to=" << selected + 1 << '\n';
                            cancel_sid_prepare("CAPACITY_SKIP");
                            index = selected;
                            stopped = false; send = true; stop_confirmed = false;
                            continue;
                        }
                    }
                }
				if (!stop_confirmed && runtime.monotonic_ms() >= prepare_deadline) {
					log << "PROFILE_PARK_TIMEOUT generation=" << request.generation
					    << " domain=" << request.domain
					    << " requested_profile=" << static_cast<int>(request.profile)
					    << " baseline=" << request.session
					    << " last_reply=" << last_profile_reply << '\n';
					return PlaylistResult::TrackSessionTimeout;
				}
				runtime.sleep_ms(config.poll_interval_ms);
			}
		}
#endif
		const Track track = active_tracks[index];
		const std::uint64_t request_generation =
#ifdef MEGAVGM_PHASE2A
			config.profile_client ? lease.generation :
#endif
			++load_generation;
		log << '\n' << '[' << index + 1 << '/' << active_tracks.size() << "] "
		    << track.name << '\n';
		const std::uint64_t request_started_ms = runtime.monotonic_ms();
		log << "LOAD_FILE_REQUEST path=" << track.path
		    << " baseline_session=" << baseline_session
		    << " generation=" << request_generation
		    << " timestamp_ms=" << request_started_ms << '\n';

		std::string command;
		std::string detail;
		if (!megavgm_autoplay2::build_load_command(load_path, command, detail)) {
			log << "INVALID_TRACK_PATH: " << detail << '\n';
			return PlaylistResult::InvalidTrackPath;
		}
		const bool two_loop_limit = config.loop_limit == 2 &&
			preferences.repeat != RepeatMode::One;
		if (!runtime.issue_transition(two_loop_limit ?
				megavgm_autoplay2::TransitionReason::LoopLimitTwoLoops :
				megavgm_autoplay2::TransitionReason::LoopLimitDisabled,
				detail)) {
			log << "LOOP_LIMIT_POLICY_FAILED";
			if (!detail.empty()) log << ": " << detail;
			log << '\n';
			return PlaylistResult::CommandWriteFailed;
		}
		// This is the stale-command boundary. It is deliberately after policy
		// setup and immediately before the owned index-1 load. Navigation that
		// existed before this point is discarded. From issue_load_generated()
		// onward, no cleanup may discard PLAY/PLAYLIST arriving while this load
		// reaches PLAYING.
		if (!discard_commands()) return PlaylistResult::ControlIoError;
		if (!runtime.issue_load_generated(load_path, request_generation, detail)) {
			log << "COMMAND_WRITE_FAILED: " << detail << '\n';
			return PlaylistResult::CommandWriteFailed;
		}
		log << "MISTER_CMD_WRITE=SUCCESS path=" << load_path
		    << " generation=" << request_generation
		    << " timestamp_ms=" << runtime.monotonic_ms() << '\n';
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
		bool stop_claimed = false;
		bool deferred_navigation = false;
		bool navigation_claimed = false;
		ControlCommand control_command;
		std::vector<ControlCommand> deferred_mode_commands;
		std::size_t applied_mode_commands = 0;
		std::vector<Track> replacement_tracks;
		std::size_t replacement_index = 0;
		std::string replacement_playlist_name;

		auto stage_direct_navigation = [&](const ControlCommand &command) {
			std::vector<Track> candidate_tracks;
			std::size_t candidate_index = 0;
			std::string candidate_playlist_name;
			std::string control_detail;
			bool valid = false;
			if (command.type == ControlCommandType::Play) {
				valid = discover_directory(parent_path(command.path),
					candidate_tracks, control_detail) == DiscoveryResult::Ok &&
					find_track(candidate_tracks, command.path, candidate_index);
				if (!valid) {
					log << "CONTROL_IGNORED: invalid PLAY selection";
					if (!control_detail.empty()) log << ": " << control_detail;
					log << '\n';
				}
			} else {
				PlaylistSnapshot snapshot;
				valid = load_playlist_snapshot(command.path, config.approved_root,
					snapshot, control_detail, true);
				if (!valid) {
					log << "CONTROL_IGNORED: invalid PLAYLIST snapshot";
					if (!control_detail.empty()) log << ": " << control_detail;
					log << '\n';
				} else {
					for (const std::string &path : snapshot.paths) {
						const std::size_t separator = path.find_last_of('/');
						candidate_tracks.push_back({separator == std::string::npos ?
							path : path.substr(separator + 1), path});
					}
					candidate_index = snapshot.start_index;
					candidate_playlist_name = snapshot.name;
				}
			}
			if (!valid) return;
			const bool replaced = deferred_navigation;
			control_command = command;
			replacement_tracks = std::move(candidate_tracks);
			replacement_index = candidate_index;
			replacement_playlist_name = std::move(candidate_playlist_name);
			deferred_navigation = true;
			log << "CONTROL_DEFERRED navigation="
			    << control_command_name(command.type)
			    << " path=" << command.path
			    << " latest_replaced=" << (replaced ? 1 : 0) << '\n';
		};
		auto collect_owned_load_commands = [&]() -> bool {
			if (!controller || stop_claimed) return true;
			for (;;) {
				ControlCommand command;
				std::string control_detail;
				const ControlPollResult control_result =
					controller->poll_command(command, control_detail);
				if (control_result == ControlPollResult::None) return true;
				if (control_result == ControlPollResult::IoError) {
					control_error("command read", control_detail);
					return false;
				}
				if (control_result == ControlPollResult::Invalid) {
					log << "CONTROL_IGNORED";
					if (!control_detail.empty()) log << ": " << control_detail;
					log << '\n';
					continue;
				}
				if (command.type == ControlCommandType::Stop) {
					// STOP owns the transport. An earlier deferred selection must
					// not start another load before the stop completes. Commands
					// after STOP remain queued for the STOPPED command loop.
					stop_claimed = true;
					deferred_navigation = false;
					return true;
				}
				if (command.type == ControlCommandType::Repeat ||
				    command.type == ControlCommandType::Shuffle) {
					deferred_mode_commands.push_back(command);
					continue;
				}
				if (command.type == ControlCommandType::Play ||
				    command.type == ControlCommandType::Playlist) {
					stage_direct_navigation(command);
					continue;
				}
				// Preserve the existing load-window contract for NEXT/PREV.
				// The UI gates those controls on navigation-ready PLAYING.
				log << "CONTROL_IGNORED: "
				    << control_command_name(command.type)
				    << " during owned load\n";
			}
		};
		auto apply_deferred_modes = [&](bool publish_update) -> bool {
			while (applied_mode_commands < deferred_mode_commands.size()) {
				const ControlCommand &command =
					deferred_mode_commands[applied_mode_commands++];
				if (!apply_mode_command(command, track, "PLAYING",
						owned_session, status.loop_count, publish_update))
					return false;
			}
			return true;
		};

		while (!have_session) {
			if (!collect_owned_load_commands())
				return PlaylistResult::ControlIoError;
			result = monitor.read(status);
			if (result != PlaylistResult::Complete) return result;
			bool session_matches = status.session != baseline_session;
#ifdef MEGAVGM_PHASE2A
			if (config.profile_client) session_matches =
				status.session == static_cast<std::uint32_t>(baseline_session + 1u) &&
					config.profile_client->load_acknowledged(lease, load_path, detail);
#endif
			if (session_matches) {
				owned_session = status.session;
				have_session = true;
				log_status(log, status, last_logged, last_logged_valid);
				fatal = is_fatal(status);
				playing = status.state == PlaybackState::Playing;
				ended = status.state == PlaybackState::Ended;
				loop_limit_reached = loop_limit_applies(status);
				// PLAYING is not externally command-ready until the final stale
				// navigation cleanup below has completed.
				if (status.state != PlaybackState::Playing &&
				    !publish(megavgm_autoplay2::state_name(status.state), track,
							status.session, status.loop_count))
					return PlaylistResult::ControlIoError;
			}
			if (!have_session && deadline_reached(runtime, deadline,
					config.session_timeout_ms)) {
				log << "TRACK_SESSION_TIMEOUT initial_session="
				    << baseline_session << " fpga_session_after="
				    << status.session << " elapsed_ms="
				    << (runtime.monotonic_ms() - request_started_ms)
				    << " path=" << track.path
				    << " generation=" << request_generation << '\n';
				return PlaylistResult::TrackSessionTimeout;
			}
			if (!have_session) monitor.sleep();
		}

		std::uint64_t owned_playing_start = playing ? runtime.monotonic_ms() : 0;
		deadline = runtime.monotonic_ms() + config.playing_timeout_ms;
		while (!playing && !fatal && !ended && !stop_claimed) {
			monitor.sleep();
			if (!collect_owned_load_commands())
				return PlaylistResult::ControlIoError;
			result = monitor.read(status);
			if (result != PlaylistResult::Complete) return result;
			if (status.session != owned_session) {
				if (!publish("SUSPENDED", track, status.session,
						status.loop_count))
					return PlaylistResult::ControlIoError;
				return suspend(log);
			}
			log_status(log, status, last_logged, last_logged_valid);
			if (status.state != PlaybackState::Playing &&
			    !publish(megavgm_autoplay2::state_name(status.state), track,
					status.session, status.loop_count))
				return PlaylistResult::ControlIoError;
			fatal = is_fatal(status);
			playing = status.state == PlaybackState::Playing;
			if (playing) owned_playing_start = runtime.monotonic_ms();
			ended = status.state == PlaybackState::Ended;
			loop_limit_reached = loop_limit_applies(status);
			if (!playing && !fatal && !ended &&
			    deadline_reached(runtime, deadline, config.playing_timeout_ms)) {
				log << "TRACK_NEVER_PLAYING\n";
				return PlaylistResult::TrackNeverPlaying;
			}
		}

		auto advance_next = [&](bool automatic, bool native_looping,
				const char *source, std::size_t &selected) -> TraversalResult {
			const TraversalResult transition = traversal.next(index, automatic,
				native_looping, selected);
			log << "TRACK_TRANSITION source=" << source << " from=" << index + 1;
			if (transition == TraversalResult::Complete)
				log << " action=COMPLETE";
			else if (transition == TraversalResult::Stay)
				log << " action=STAY";
			else
				log << " action=" << (selected == index ? "RELOAD" : "LOAD")
				    << " to=" << selected + 1;
			log << '\n';
			return transition;
		};

#ifdef MEGAVGM_PHASE2A
        if (fatal && config.profile_client) {
            log << "FPGA_FATAL_NO_AUTOMATIC_SKIP session=" << owned_session
                << " error=" << unsigned(status.error) << " path=" << track.path << '\n';
            return control_error("FPGA fatal", "not a recoverable pre-transfer refusal");
        }
#endif
		if (fatal) {
			log_fatal(log, index, active_tracks.size(), track, status);
			baseline_session = owned_session;
			skipped++;
			std::size_t selected = index;
			if (advance_next(false, false, "FATAL", selected) ==
					TraversalResult::Complete)
				return complete(track, owned_session, status.loop_count);
			index = selected;
			continue;
		}
		if (ended && !playing
#ifdef MEGAVGM_PHASE2A
		    && !config.profile_client
#endif
		) {
			log << "TRACK_NEVER_PLAYING: ENDED before PLAYING\n";
			return PlaylistResult::TrackNeverPlaying;
		}
#ifdef MEGAVGM_PHASE2A
		if (ended && !playing && config.profile_client)
			log << "PROFILE_SHORT_TRACK_COMPLETED: Main generation acknowledged, owned session already ENDED\n";
#endif

        reset_capacity_chain(automatic_selection);
		// Capture commands that arrived with the PLAYING status update before
		// exposing navigation readiness. Unlike the pre-load cleanup, this poll
		// is ownership-aware and retains valid direct selection.
		if (!collect_owned_load_commands()) return PlaylistResult::ControlIoError;
		if (!apply_deferred_modes(false)) return PlaylistResult::ControlIoError;
		loop_limit_reached = loop_limit_applies(status);
		if (playing && !publish("PLAYING", track, owned_session,
				status.loop_count))
			return PlaylistResult::ControlIoError;
		// Preserve 3d7a6c2's public readiness guarantee and also collect any
		// direct intent emitted synchronously in response to public PLAYING.
		if (!collect_owned_load_commands()) return PlaylistResult::ControlIoError;
		if (!apply_deferred_modes(true)) return PlaylistResult::ControlIoError;
		loop_limit_reached = loop_limit_applies(status);
		if (!stop_claimed && deferred_navigation)
			navigation_claimed = true;
  if (playing && prepared_timing.valid) {
   metadata_deadline.arm(request_generation, owned_session, owned_playing_start, prepared_timing.target_ms);
   log << "METADATA_TIMER_ARM session=" << owned_session << " generation=" << request_generation
       << " target_ms=" << prepared_timing.target_ms << " transport_fade_ms=100 policy=END_TARGET_APPROXIMATION"
       << " physical=" << prepared_timing.physical << " source_sha256=" << prepared_timing.source_sha256
       << " execution_sha256=" << prepared_timing.execution_sha256 << '\n';
  }
		// Metadata and late Repeat recovery share the existing Controller fade
		// request. Track-local state is discarded by every Reload/retarget.
		bool automatic_fade_requested = false;
		std::uint64_t automatic_request_ms = 0;
		auto maybe_automatic_end = [&]() -> bool {
			if (stop_claimed || navigation_claimed || fatal || ended ||
			    automatic_fade_requested || status.session != owned_session ||
			    status.state != PlaybackState::Playing)
				return true;
			const bool metadata_due = metadata_deadline.due(
				request_generation, status.session, runtime.monotonic_ms());
			const bool repeat_due = repeat_recovery_pending &&
				preferences.repeat != RepeatMode::One && config.loop_limit == 2 &&
				status.loop_valid && status.loop_count >= config.loop_limit;
			if (!metadata_due && !repeat_due) return true;
#ifdef MEGAVGM_PHASE2A
			std::string ownership_detail;
			if (config.profile_client &&
			    !config.profile_client->owns_session(lease, load_path, status, ownership_detail)) {
				metadata_deadline.cancel();
				repeat_recovery_pending = false;
				log << (metadata_due ? "METADATA_TIMER_OWNER_LOST" :
					"REPEAT_RECOVERY_OWNER_LOST") << " detail=" << ownership_detail << '\n';
				return false;
			}
#endif
			std::string fade_detail;
			// The immutable MV02/02 record retains the single Transport owner.
			// Neither loop_count nor the request itself fabricates ENDED.
			if (!runtime.issue_stop(fade_detail)) {
				log << (metadata_due ? "METADATA_FADE_FAILED " :
					"REPEAT_RECOVERY_FADE_FAILED ") << fade_detail << '\n';
				return false;
			}
			automatic_fade_requested = true;
			automatic_request_ms = runtime.monotonic_ms();
			repeat_recovery_pending = false;
			if (metadata_due) metadata_deadline.requested();
			log << (metadata_due ? "METADATA_FADE_ONLY" : "REPEAT_RECOVERY_FADE_ONLY")
			    << " session=" << owned_session << " generation=" << request_generation
			    << " elapsed_ms=" << runtime.monotonic_ms() - owned_playing_start
			    << " loop_count=" << status.loop_count << '\n';
			return true;
		};
		if (!maybe_automatic_end()) return PlaylistResult::CommandWriteFailed;
		deadline = runtime.monotonic_ms() + config.end_timeout_ms;
		while (!ended && !fatal && !stop_claimed && !navigation_claimed) {
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
								owned_session, status.loop_count, true))
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
			if (!maybe_automatic_end()) return PlaylistResult::CommandWriteFailed;
			if (!ended && !fatal && automatic_fade_requested &&
			    config.stop_timeout_ms != 0 &&
			    runtime.monotonic_ms() - automatic_request_ms >= config.stop_timeout_ms) {
				log << (metadata_deadline.fading() ? "METADATA_END_TIMEOUT" :
					"REPEAT_RECOVERY_END_TIMEOUT") << " session=" << owned_session << '\n';
				return PlaylistResult::StopTimeout;
			}
			if (!ended && !fatal &&
			    deadline_reached(runtime, deadline,
					config.end_timeout_ms)) {
				log << "TRACK_END_TIMEOUT\n";
				return PlaylistResult::TrackEndTimeout;
			}
		}

		metadata_deadline.cancel();
		std::uint32_t next_baseline_session = owned_session;
		if (ended) {
			log << "TRACK_COMPLETE generation=" << request_generation
			    << " session=" << owned_session
			    << " timestamp_ms=" << runtime.monotonic_ms()
			    << " path=" << track.path << '\n';
		}
		if (stop_claimed) {
#ifdef MEGAVGM_PHASE2A
            if (config.profile_client) config.profile_client->forget_session();
#endif
			std::string stop_detail;
			if (!automatic_fade_requested && !runtime.issue_stop(stop_detail)) {
				log << "STOP_COMMAND_FAILED";
				if (!stop_detail.empty()) log << ": " << stop_detail;
				log << '\n';
				return PlaylistResult::StopCommandFailed;
			}
			log << (automatic_fade_requested ? "STOP_JOINS_AUTOMATIC_FADE path=" :
				"MISTER_CMD_STOP=SUCCESS path=") << track.path << '\n';
			const std::uint64_t stop_deadline =
				runtime.monotonic_ms() + config.stop_timeout_ms;
			for (;;) {
				result = monitor.read(status);
				if (result != PlaylistResult::Complete) return result;
				log_status(log, status, last_logged, last_logged_valid);
				if (status.session != owned_session) {
					log << "STOP_SESSION_CHANGED\n";
					return suspend(log);
				}
				if (is_fatal(status)) return PlaylistResult::StopCommandFailed;
				if (status.state == PlaybackState::Ended) break;
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
			// FPGA's same-session ENDED state. Keep the selected source and traversal
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
								owned_session, status.loop_count, true))
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
				    status.state != PlaybackState::Ended) {
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
            reset_capacity_chain(false);
			log << "navigation=" << control_command_name(control_command.type);
			if (control_command.type == ControlCommandType::Play ||
			    control_command.type == ControlCommandType::Playlist)
				log << " path=" << control_command.path;
			log << '\n';
			const char *navigation_state =
				control_command.type == ControlCommandType::Playlist ? "PLAY" :
				control_command_name(control_command.type);
			if (!publish(navigation_state, track,
					owned_session, status.loop_count))
				return PlaylistResult::ControlIoError;
			if (control_command.type == ControlCommandType::Play) {
				active_tracks = std::move(replacement_tracks);
				index = replacement_index;
				active_playlist_name.clear();
				traversal.reset(active_tracks.size(), index, preferences);
                reset_capacity_chain(false);
			} else if (control_command.type == ControlCommandType::Playlist) {
				active_tracks = std::move(replacement_tracks);
				index = replacement_index;
				active_playlist_name = replacement_playlist_name;
				traversal.reset(active_tracks.size(), index, preferences);
                reset_capacity_chain(false);
			} else if (control_command.type == ControlCommandType::Next) {
				std::size_t selected = index;
				if (advance_next(false, false, "MANUAL_NEXT", selected) ==
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
#ifdef MEGAVGM_PHASE2A
        if (fatal && config.profile_client) {
            log << "FPGA_FATAL_NO_AUTOMATIC_SKIP session=" << owned_session
                << " error=" << unsigned(status.error) << " path=" << track.path << '\n';
            return control_error("FPGA fatal", "not a recoverable pre-transfer refusal");
        }
#endif
		if (fatal) {
			log_fatal(log, index, active_tracks.size(), track, status);
			skipped++;
		}
		else if (loop_limit_reached) {
			log << "loop limit reached=" << config.loop_limit << '\n';
		}
		std::size_t selected = index;
		const char *automatic_source = fatal ? "FATAL" :
			loop_limit_reached ? "LOOP_LIMIT" : metadata_deadline.fading() ? "METADATA_END" : "EOF";
		const TraversalResult advance = advance_next(true, status.loop_valid,
			automatic_source, selected);
		if (advance == TraversalResult::Complete)
			return complete(track, owned_session, status.loop_count);
        automatic_selection = true;
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
