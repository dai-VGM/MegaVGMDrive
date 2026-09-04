#include "playlist.h"

#include <cassert>
#include <cerrno>
#include <fcntl.h>
#include <fstream>
#include <iostream>
#include <limits.h>
#include <set>
#include <sstream>
#include <string>
#include <sys/stat.h>
#include <unistd.h>
#include <utility>
#include <vector>

using namespace megavgm_playlist;
using megavgm_autoplay2::PlaybackState;
using megavgm_autoplay2::PlaybackStatus;
using megavgm_autoplay2::Runtime;
using megavgm_autoplay2::StatusReadResult;

namespace {

struct Frame {
	StatusReadResult result;
	PlaybackStatus status;
	const char *detail;
	bool main_available;
};

PlaybackStatus status(std::uint32_t session, PlaybackState state,
		std::uint8_t error = 0)
{
	return {1, session, state, error};
}

Frame ok(std::uint32_t session, PlaybackState state, std::uint8_t error = 0,
		bool main_available = true)
{
	return {StatusReadResult::Ok, status(session, state, error), "",
		main_available};
}

Frame loop_status(std::uint32_t session, PlaybackState state,
		bool loop_valid, std::uint16_t loop_count, std::uint8_t error = 0)
{
	return {StatusReadResult::Ok,
		{2, session, state, error, loop_valid, loop_count}, "", true};
}

class ScriptRuntime final : public Runtime {
public:
	explicit ScriptRuntime(std::vector<Frame> frames)
		: frames_(std::move(frames))
	{
		assert(!frames_.empty());
	}

	StatusReadResult read_status(PlaybackStatus &value,
			std::string &detail) override
	{
		const Frame &frame = current();
		value = frame.status;
		detail = frame.detail;
		read_count++;
		if (position_ + 1 < frames_.size()) position_++;
		return frame.result;
	}

	bool main_available(std::string &detail) override
	{
		if (!current().main_available) {
			detail = "simulated Main exit";
			return false;
		}
		detail.clear();
		return true;
	}

	bool issue_load(const std::string &path, std::string &detail) override
	{
		std::string command;
		if (!megavgm_autoplay2::build_load_command(path, command, detail))
			return false;
		commands.push_back(command);
		return true;
	}

	bool issue_stop(std::string &detail) override
	{
		if (!stop_ok) {
			detail = "simulated reset_core write failure";
			return false;
		}
		commands.push_back("reset_core\n");
		detail.clear();
		return true;
	}

	std::uint64_t monotonic_ms() override { return now_ms_; }

	void sleep_ms(std::uint32_t milliseconds) override
	{
		now_ms_ += milliseconds;
	}

	std::vector<std::string> commands;
	std::size_t read_count = 0;
	bool stop_ok = true;

private:
	const Frame &current() const
	{
		return frames_[position_ < frames_.size() ? position_ : frames_.size() - 1];
	}

	std::vector<Frame> frames_;
	std::size_t position_ = 0;
	std::uint64_t now_ms_ = 0;
};

struct ControlEvent {
	std::size_t after_reads;
	ControlCommandType type;
	std::string path;
	RepeatMode repeat = RepeatMode::Off;
	bool shuffle = false;
};

class ScriptController final : public ControllerIo {
public:
	ScriptController(ScriptRuntime &runtime, std::vector<ControlEvent> events,
			PlaybackPreferences preferences = {})
		: initial_preferences(preferences), runtime_(runtime),
		  events_(std::move(events))
	{
	}

	ControlPollResult poll_command(ControlCommand &command,
			std::string &detail) override
	{
		if (!retained_.empty()) {
			const ControlEvent event = retained_.front();
			retained_.erase(retained_.begin());
			command.type = event.type;
			command.path = event.path;
			command.repeat = event.repeat;
			command.shuffle = event.shuffle;
			detail.clear();
			return ControlPollResult::Command;
		}
		if (position_ >= events_.size() ||
		    events_[position_].after_reads > runtime_.read_count) {
			detail.clear();
			return ControlPollResult::None;
		}
		const ControlEvent &event = events_[position_++];
		command.type = event.type;
		command.path = event.path;
		command.repeat = event.repeat;
		command.shuffle = event.shuffle;
		detail.clear();
		return ControlPollResult::Command;
	}

	bool discard_commands(std::string &detail) override
	{
		while (position_ < events_.size() &&
		       events_[position_].after_reads <= runtime_.read_count) {
			if (events_[position_].type == ControlCommandType::Stop ||
			    events_[position_].type == ControlCommandType::Repeat ||
			    events_[position_].type == ControlCommandType::Shuffle)
				retained_.push_back(events_[position_]);
			else
				discarded++;
			position_++;
		}
		detail.clear();
		return true;
	}

	bool load_preferences(PlaybackPreferences &preferences,
			std::string &detail) override
	{
		preferences = initial_preferences;
		detail.clear();
		return true;
	}

	bool save_preferences(const PlaybackPreferences &preferences,
			std::string &detail) override
	{
		saved_preferences.push_back(preferences);
		detail.clear();
		return true;
	}

	bool publish(const ControllerSnapshot &snapshot,
			std::string &detail) override
	{
		snapshots.push_back(snapshot);
		detail.clear();
		return true;
	}

	std::size_t discarded = 0;
	std::vector<ControllerSnapshot> snapshots;
	PlaybackPreferences initial_preferences;
	std::vector<PlaybackPreferences> saved_preferences;

private:
	ScriptRuntime &runtime_;
	std::vector<ControlEvent> events_;
	std::size_t position_ = 0;
	std::vector<ControlEvent> retained_;
};

PlaylistConfig fast_config()
{
	PlaylistConfig config;
	config.session_timeout_ms = 5;
	config.playing_timeout_ms = 5;
	config.stop_timeout_ms = 5;
	config.end_timeout_ms = 5;
	config.poll_interval_ms = 1;
	config.main_probe_interval_ms = 1;
	return config;
}

std::vector<Track> three_tracks()
{
	return {
		{"01 Opening [JP].vgm", "/music/01 Opening [JP].vgm"},
		{"02 Stage (Arcade).vgm", "/music/02 Stage (Arcade).vgm"},
		{"03 æ¥æ¬èª Ending.vgm", "/music/03 æ¥æ¬èª Ending.vgm"}
	};
}

PlaylistResult execute(std::vector<Frame> frames, std::vector<Track> tracks,
		ScriptRuntime **out_runtime = nullptr, std::string *out_log = nullptr,
		std::uint16_t loop_limit = 2,
		std::vector<ControlEvent> control_events = {},
		ScriptController **out_controller = nullptr,
		std::size_t start_index = 0,
		const std::string &approved_root = {},
		PlaybackPreferences preferences = {}, RandomSource *random = nullptr,
		const std::string &initial_playlist_name = {})
{
	auto *runtime = new ScriptRuntime(std::move(frames));
	auto *controller = new ScriptController(*runtime, std::move(control_events),
		preferences);
	std::ostringstream log;
	PlaylistConfig config = fast_config();
	config.loop_limit = loop_limit;
	config.start_index = start_index;
	config.initial_playlist_name = initial_playlist_name;
	if (!approved_root.empty()) config.approved_root = approved_root;
	config.random_source = random;
	const PlaylistResult result = run(*runtime, config, tracks, log, controller);
	if (out_log) *out_log = log.str();
	if (out_controller) *out_controller = controller;
	else delete controller;
	if (out_runtime) *out_runtime = runtime;
	else delete runtime;
	return result;
}

void create_file(const std::string &path);

void test_native_loop_limit_and_stale_reset()
{
	ScriptRuntime *runtime = nullptr;
	std::string log;
	const std::vector<Track> tracks = {
		{"01 Native Loop.vgm", "/music/01 Native Loop.vgm"},
		{"02 Normal End.vgm", "/music/02 Normal End.vgm"}
	};
	const PlaylistResult result = execute({
		loop_status(9, PlaybackState::Ended, false, 0),
		loop_status(10, PlaybackState::Loading, false, 0),
		loop_status(10, PlaybackState::Playing, true, 0),
		loop_status(10, PlaybackState::Playing, true, 1),
		loop_status(10, PlaybackState::Playing, true, 2),
		loop_status(10, PlaybackState::Playing, true, 2),
		loop_status(10, PlaybackState::Playing, true, 2),
		loop_status(11, PlaybackState::Loading, false, 0),
		loop_status(11, PlaybackState::Playing, false, 0),
		loop_status(11, PlaybackState::Ended, false, 0)
	}, tracks, &runtime, &log);

	assert(result == PlaylistResult::Complete);
	assert(runtime->commands.size() == 2);
	assert(runtime->commands[0] == "load_file 1 " + tracks[0].path + "\n");
	assert(runtime->commands[1] == "load_file 1 " + tracks[1].path + "\n");
	assert(log.find("session=10 PLAYING loop_valid=1 loop_count=0") !=
		std::string::npos);
	assert(log.find("session=10 PLAYING loop_valid=1 loop_count=1") !=
		std::string::npos);
	assert(log.find("session=10 PLAYING loop_valid=1 loop_count=2") !=
		std::string::npos);
	assert(log.find("session=11 LOADING loop_valid=0 loop_count=0") !=
		std::string::npos);
	assert(log.find("loop limit reached=2") != std::string::npos);
	delete runtime;
}

void test_loop_counter_saturation_policy()
{
	ScriptRuntime *runtime = nullptr;
	const std::vector<Track> tracks = {
		{"01 Saturated Loop.vgm", "/music/01 Saturated Loop.vgm"},
		{"02 Next.vgm", "/music/02 Next.vgm"}
	};
	const PlaylistResult result = execute({
		loop_status(50, PlaybackState::Ended, false, 0),
		loop_status(51, PlaybackState::Playing, true, 65534),
		loop_status(51, PlaybackState::Playing, true, 65535),
		loop_status(51, PlaybackState::Playing, true, 65535),
		loop_status(52, PlaybackState::Playing, false, 0),
		loop_status(52, PlaybackState::Ended, false, 0)
	}, tracks, &runtime, nullptr, 65535);
	assert(result == PlaylistResult::Complete);
	assert(runtime->commands.size() == 2);
	delete runtime;
}

void test_loop_limit_zero_is_infinite()
{
	const std::vector<Track> tracks = {
		{"01 Loop.vgm", "/music/01 Loop.vgm"}
	};
	assert(execute({
		loop_status(60, PlaybackState::Ended, false, 0),
		loop_status(61, PlaybackState::Playing, true, 0),
		loop_status(61, PlaybackState::Playing, true, 1),
		loop_status(61, PlaybackState::Playing, true, 2),
		loop_status(61, PlaybackState::Playing, true, 3)
	}, tracks, nullptr, nullptr, 0) == PlaylistResult::TrackEndTimeout);
}

void test_next_during_track_two_and_stale_end()
{
	ScriptRuntime *runtime = nullptr;
	ScriptController *controller = nullptr;
	std::string log;
	const std::vector<Track> tracks = three_tracks();
	const PlaylistResult result = execute({
		ok(9, PlaybackState::Ended),
		ok(10, PlaybackState::Playing),
		ok(10, PlaybackState::Ended),
		ok(11, PlaybackState::Playing),
		ok(11, PlaybackState::Playing),
		ok(11, PlaybackState::Ended), // stale after NEXT is claimed
		ok(12, PlaybackState::Playing),
		ok(12, PlaybackState::Ended)
	}, tracks, &runtime, &log, 2,
		{{5, ControlCommandType::Next, {}}}, &controller);
	assert(result == PlaylistResult::Complete);
	assert(runtime->commands.size() == 3);
	assert(runtime->commands[1] == "load_file 1 " + tracks[1].path + "\n");
	assert(runtime->commands[2] == "load_file 1 " + tracks[2].path + "\n");
	assert(log.find("navigation=NEXT") != std::string::npos);
	assert(log.find("PLAYLIST SUSPENDED") == std::string::npos);
	bool saw_track_three = false;
	for (const ControllerSnapshot &snapshot : controller->snapshots) {
		if (snapshot.state == "PLAYING" && snapshot.index == 3 &&
		    snapshot.session == 12 && snapshot.path == tracks[2].path)
			saw_track_three = true;
	}
	assert(saw_track_three);
	assert(!controller->snapshots.empty());
	assert(controller->snapshots.back().state == "COMPLETE");
	assert(controller->snapshots.back().index == 3);
	assert(controller->snapshots.back().count == 3);
	delete controller;
	delete runtime;
}

void test_previous_during_track_three()
{
	ScriptRuntime *runtime = nullptr;
	const std::vector<Track> tracks = three_tracks();
	const PlaylistResult result = execute({
		ok(9, PlaybackState::Ended),
		ok(10, PlaybackState::Playing),
		ok(10, PlaybackState::Ended),
		ok(11, PlaybackState::Playing),
		ok(11, PlaybackState::Ended),
		ok(12, PlaybackState::Playing),
		ok(12, PlaybackState::Playing),
		ok(12, PlaybackState::Ended),
		ok(13, PlaybackState::Playing),
		ok(13, PlaybackState::Ended),
		ok(14, PlaybackState::Playing),
		ok(14, PlaybackState::Ended)
	}, tracks, &runtime, nullptr, 2,
		{{7, ControlCommandType::Previous, {}}});
	assert(result == PlaylistResult::Complete);
	assert(runtime->commands.size() == 5);
	assert(runtime->commands[2] == "load_file 1 " + tracks[2].path + "\n");
	assert(runtime->commands[3] == "load_file 1 " + tracks[1].path + "\n");
	assert(runtime->commands[4] == "load_file 1 " + tracks[2].path + "\n");
	delete runtime;
}

void test_previous_restarts_first_track()
{
	ScriptRuntime *runtime = nullptr;
	const std::vector<Track> tracks = {
		{"01 [日本語] First.vgm", "/music/01 [日本語] First.vgm"}
	};
	const PlaylistResult result = execute({
		ok(9, PlaybackState::Ended),
		ok(10, PlaybackState::Playing),
		ok(10, PlaybackState::Playing),
		ok(10, PlaybackState::Ended),
		ok(11, PlaybackState::Playing),
		ok(11, PlaybackState::Ended)
	}, tracks, &runtime, nullptr, 2,
		{{3, ControlCommandType::Previous, {}}});
	assert(result == PlaylistResult::Complete);
	assert(runtime->commands.size() == 2);
	assert(runtime->commands[0] == runtime->commands[1]);
	delete runtime;
}

void test_next_at_last_track_completes()
{
	ScriptRuntime *runtime = nullptr;
	const std::vector<Track> tracks = {
		{"Only.vgm", "/music/Only.vgm"}
	};
	const PlaylistResult result = execute({
		ok(9, PlaybackState::Ended),
		ok(10, PlaybackState::Playing),
		ok(10, PlaybackState::Playing)
	}, tracks, &runtime, nullptr, 2,
		{{3, ControlCommandType::Next, {}}});
	assert(result == PlaylistResult::Complete);
	assert(runtime->commands.size() == 1);
	delete runtime;
}

void test_single_track_natural_end_completes_once()
{
	ScriptRuntime *runtime = nullptr;
	std::string log;
	const std::vector<Track> tracks = {
		{"Only.vgm", "/music/Only.vgm"}
	};
	assert(execute({
		ok(9, PlaybackState::Ended),
		ok(10, PlaybackState::Playing),
		ok(10, PlaybackState::Ended)
	}, tracks, &runtime, &log) == PlaylistResult::Complete);
	assert(runtime->commands.size() == 1);
	assert(log.find("TRACK_TRANSITION source=EOF from=1 action=COMPLETE") !=
		std::string::npos);
	delete runtime;
}

void test_next_wins_loop_limit_race()
{
	ScriptRuntime *runtime = nullptr;
	const std::vector<Track> tracks = {
		{"01 Loop.vgm", "/music/01 Loop.vgm"},
		{"02 Normal.vgm", "/music/02 Normal.vgm"}
	};
	const PlaylistResult result = execute({
		loop_status(9, PlaybackState::Ended, false, 0),
		loop_status(10, PlaybackState::Playing, true, 0),
		loop_status(10, PlaybackState::Playing, true, 1),
		loop_status(10, PlaybackState::Playing, true, 2),
		loop_status(11, PlaybackState::Playing, false, 0),
		loop_status(11, PlaybackState::Ended, false, 0)
	}, tracks, &runtime, nullptr, 2,
		{{3, ControlCommandType::Next, {}}});
	assert(result == PlaylistResult::Complete);
	assert(runtime->commands.size() == 2);
	delete runtime;
}

void test_manual_and_automatic_next_share_one_transition_owner()
{
	ScriptRuntime *runtime = nullptr;
	std::string log;
	const std::vector<Track> tracks = three_tracks();
	const PlaylistResult result = execute({
		ok(9, PlaybackState::Ended),
		ok(10, PlaybackState::Playing),
		ok(10, PlaybackState::Playing),
		ok(11, PlaybackState::Playing),
		ok(11, PlaybackState::Ended),
		ok(12, PlaybackState::Playing),
		ok(12, PlaybackState::Ended)
	}, tracks, &runtime, &log, 2,
		{{3, ControlCommandType::Next, {}}});
	assert(result == PlaylistResult::Complete);
	assert(runtime->commands.size() == 3);
	assert(runtime->commands[0] == "load_file 1 " + tracks[0].path + "\n");
	assert(runtime->commands[1] == "load_file 1 " + tracks[1].path + "\n");
	assert(runtime->commands[2] == "load_file 1 " + tracks[2].path + "\n");
	assert(log.find("TRACK_TRANSITION source=MANUAL_NEXT from=1 action=LOAD to=2") !=
		std::string::npos);
	assert(log.find("TRACK_TRANSITION source=EOF from=2 action=LOAD to=3") !=
		std::string::npos);
	assert(log.find("TRACK_TRANSITION_IGNORED") == std::string::npos);
	for (const std::string &command : runtime->commands)
		assert(command != "reset_core\n");
	delete runtime;
}

void test_loop_limit_uses_guarded_transition_once()
{
	ScriptRuntime *runtime = nullptr;
	std::string log;
	const std::vector<Track> tracks = {
		{"Loop.vgm", "/music/Loop.vgm"},
		{"Next.vgm", "/music/Next.vgm"}
	};
	assert(execute({
		loop_status(4, PlaybackState::Ended, false, 0),
		loop_status(5, PlaybackState::Playing, true, 0),
		loop_status(5, PlaybackState::Playing, true, 2),
		loop_status(5, PlaybackState::Playing, true, 2),
		loop_status(5, PlaybackState::Playing, true, 2),
		loop_status(6, PlaybackState::Playing, false, 0),
		loop_status(6, PlaybackState::Ended, false, 0)
	}, tracks, &runtime, &log) == PlaylistResult::Complete);
	assert(runtime->commands.size() == 2);
	assert(log.find("TRACK_TRANSITION source=LOOP_LIMIT from=1 action=LOAD to=2") !=
		std::string::npos);
	assert(log.find("TRACK_TRANSITION_IGNORED") == std::string::npos);
	delete runtime;
}

void test_rapid_next_is_ignored_during_owned_load()
{
	ScriptRuntime *runtime = nullptr;
	ScriptController *controller = nullptr;
	const std::vector<Track> tracks = three_tracks();
	const PlaylistResult result = execute({
		ok(9, PlaybackState::Ended),
		ok(10, PlaybackState::Playing),
		ok(10, PlaybackState::Playing),
		ok(10, PlaybackState::Ended),
		ok(11, PlaybackState::Playing),
		ok(11, PlaybackState::Ended),
		ok(12, PlaybackState::Playing),
		ok(12, PlaybackState::Ended)
	}, tracks, &runtime, nullptr, 2,
		{{3, ControlCommandType::Next, {}},
		 {3, ControlCommandType::Next, {}}},
		&controller);
	assert(result == PlaylistResult::Complete);
	assert(runtime->commands.size() == 3);
	assert(runtime->commands[1] == "load_file 1 " + tracks[1].path + "\n");
	assert(controller->discarded == 1);
	delete controller;
	delete runtime;
}

void test_three_tracks_and_duplicate_end()
{
	ScriptRuntime *runtime = nullptr;
	std::string log;
	const std::vector<Track> tracks = three_tracks();
	const PlaylistResult result = execute({
		ok(9, PlaybackState::Ended),
		ok(10, PlaybackState::Loading),
		ok(10, PlaybackState::Playing),
		ok(10, PlaybackState::Ended),
		ok(10, PlaybackState::Ended),
		ok(10, PlaybackState::Ended),
		ok(11, PlaybackState::Loading),
		ok(11, PlaybackState::Playing),
		ok(11, PlaybackState::Ended),
		ok(11, PlaybackState::Ended),
		ok(12, PlaybackState::Playing),
		ok(12, PlaybackState::Ended)
	}, tracks, &runtime, &log);

	assert(result == PlaylistResult::Complete);
	assert(runtime->commands.size() == 3);
	for (std::size_t i = 0; i < tracks.size(); ++i)
		assert(runtime->commands[i] == "load_file 1 " + tracks[i].path + "\n");
	assert(log.find("session=10 PLAYING") != std::string::npos);
	assert(log.find("session=10 ENDED") != std::string::npos);
	assert(log.find("session=11 ENDED") != std::string::npos);
	assert(log.find("session=12 ENDED") != std::string::npos);
	assert(log.find("PLAYLIST COMPLETE") != std::string::npos);
	delete runtime;
}

void test_manual_suspension()
{
	ScriptRuntime *runtime = nullptr;
	std::string log;
	const PlaylistResult result = execute({
		ok(20, PlaybackState::Ended),
		ok(21, PlaybackState::Playing),
		ok(22, PlaybackState::Loading)
	}, three_tracks(), &runtime, &log);
	assert(result == PlaylistResult::Suspended);
	assert(runtime->commands.size() == 1);
	assert(log.find("PLAYLIST SUSPENDED: manual/external load detected") !=
		std::string::npos);
	delete runtime;
}

void test_fatal_skips_to_next()
{
	ScriptRuntime *runtime = nullptr;
	std::string log;
	const std::vector<Track> tracks = {
		{"01 Bad.vgm", "/music/01 Bad.vgm"},
		{"02 Good.vgm", "/music/02 Good.vgm"}
	};
	const PlaylistResult result = execute({
		ok(30, PlaybackState::Ended),
		ok(31, PlaybackState::Loading),
		ok(31, PlaybackState::Fatal, 0x0c),
		ok(31, PlaybackState::Fatal, 0x0c),
		ok(32, PlaybackState::Playing),
		ok(32, PlaybackState::Ended)
	}, tracks, &runtime, &log);
	assert(result == PlaylistResult::Complete);
	assert(runtime->commands.size() == 2);
	assert(log.find("FATAL session=31 error=0C path=/music/01 Bad.vgm -- skipping") !=
		std::string::npos);
	assert(log.find("skipped=1") != std::string::npos);
	delete runtime;
}

void test_fatal_before_loop_limit()
{
	ScriptRuntime *runtime = nullptr;
	const std::vector<Track> tracks = {
		{"01 Loop Fails.vgm", "/music/01 Loop Fails.vgm"},
		{"02 Next.vgm", "/music/02 Next.vgm"}
	};
	const PlaylistResult result = execute({
		loop_status(70, PlaybackState::Ended, false, 0),
		loop_status(71, PlaybackState::Playing, true, 0),
		loop_status(71, PlaybackState::Playing, true, 1),
		loop_status(71, PlaybackState::Fatal, false, 0, 0x0d),
		loop_status(72, PlaybackState::Playing, false, 0),
		loop_status(72, PlaybackState::Ended, false, 0)
	}, tracks, &runtime);
	assert(result == PlaylistResult::Complete);
	assert(runtime->commands.size() == 2);
	delete runtime;
}

void test_missing_and_timeout()
{
	assert(execute({
		{StatusReadResult::Missing, {}, "not found", true}
	}, three_tracks()) == PlaylistResult::StatusFileMissing);

	ScriptRuntime *runtime = nullptr;
	std::string log;
	const std::vector<Track> tracks = three_tracks();
	assert(execute({
		ok(40, PlaybackState::Ended)
	}, tracks, &runtime, &log) == PlaylistResult::TrackSessionTimeout);
	assert(runtime->commands.size() == 1);
	assert(log.find("INITIAL_FPGA_SESSION=40") != std::string::npos);
	assert(log.find("LOAD_FILE_REQUEST path=" + tracks[0].path +
		" baseline_session=40") != std::string::npos);
	assert(log.find("MISTER_CMD_WRITE=SUCCESS path=" + tracks[0].path) !=
		std::string::npos);
	assert(log.find("TRACK_SESSION_TIMEOUT initial_session=40 "
		"fpga_session_after=40 elapsed_ms=5 path=" + tracks[0].path) !=
		std::string::npos);
	delete runtime;

	assert(execute({
		ok(40, PlaybackState::Ended),
		ok(41, PlaybackState::Loading, 0, false)
	}, three_tracks()) == PlaylistResult::ActiveMainUnavailable);
}

void create_file(const std::string &path)
{
	const int fd = open(path.c_str(), O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0600);
	assert(fd >= 0);
	assert(close(fd) == 0);
}

void test_discovery_and_ordering()
{
	char directory_template[] = "/tmp/megavgm_playlist_test.XXXXXX";
	char *directory_name = mkdtemp(directory_template);
	assert(directory_name);
	const std::string directory(directory_name);
	const std::vector<std::string> files = {
		"10 Finale.vgm",
		"02 Stage (Arcade).vgm",
		"01 [Opening] æ¥æ¬èª.vgm",
		".hidden.vgm",
		"03 helper.vgm.tmp",
		"04 Upper.VGM"
	};
	for (const std::string &name : files) create_file(directory + '/' + name);
	assert(mkdir((directory + "/00 Directory.vgm").c_str(), 0700) == 0);

	std::vector<Track> tracks;
	std::string detail;
	assert(discover_directory(directory, tracks, detail) == DiscoveryResult::Ok);
	assert(tracks.size() == 3);
	assert(tracks[0].name == "01 [Opening] æ¥æ¬èª.vgm");
	assert(tracks[1].name == "02 Stage (Arcade).vgm");
	assert(tracks[2].name == "10 Finale.vgm");
	for (const Track &track : tracks)
		assert(track.path == directory + '/' + track.name);

	for (const std::string &name : files)
		assert(unlink((directory + '/' + name).c_str()) == 0);
	assert(rmdir((directory + "/00 Directory.vgm").c_str()) == 0);
	assert(rmdir(directory.c_str()) == 0);
}

void test_empty_directory()
{
	char directory_template[] = "/tmp/megavgm_playlist_empty.XXXXXX";
	char *directory_name = mkdtemp(directory_template);
	assert(directory_name);
	std::vector<Track> tracks;
	std::string detail;
	assert(discover_directory(directory_name, tracks, detail) ==
		DiscoveryResult::Empty);
	assert(!detail.empty());
	assert(rmdir(directory_name) == 0);
}

void test_playlist_snapshot_adopts_current_and_owns_auto_next()
{
	char root_template[] = "/tmp/megavgm_snapshot_run.XXXXXX";
	char *root_name = mkdtemp(root_template);
	assert(root_name);
	char canonical_root[PATH_MAX];
	assert(realpath(root_name, canonical_root));
	const std::string root(canonical_root);
	assert(mkdir((root + "/one").c_str(), 0700) == 0);
	assert(mkdir((root + "/two").c_str(), 0700) == 0);
	const std::string first = root + "/one/01 First.vgm";
	const std::string second = root + "/two/02 Second.vgm";
	create_file(first);
	create_file(second);
	const std::string snapshot_path = root + "/playlist.snapshot";
	{
		std::ofstream snapshot(snapshot_path);
		snapshot << "MEGAVGM_PLAYLIST_V1\nNAME Favorites\nSTART 0\nCOUNT 2\n"
		         << "PATH " << first << '\n' << "PATH " << second << '\n';
	}
	ScriptRuntime *runtime = nullptr;
	ScriptController *controller = nullptr;
	const PlaylistResult result = execute({
		ok(9, PlaybackState::Ended),
		ok(10, PlaybackState::Playing),
		ok(10, PlaybackState::Playing),
		ok(10, PlaybackState::Ended),
		ok(11, PlaybackState::Playing),
		ok(11, PlaybackState::Ended)
	}, {{"01 First.vgm", first}}, &runtime, nullptr, 2,
		{{3, ControlCommandType::Playlist, snapshot_path}}, &controller, 0, root);
	assert(result == PlaylistResult::Complete);
	assert(runtime->commands.size() == 2);
	assert(runtime->commands[0] == "load_file 1 " + first + "\n");
	assert(runtime->commands[1] == "load_file 1 " + second + "\n");
	bool adopted = false;
	bool second_owned = false;
	for (const ControllerSnapshot &snapshot : controller->snapshots) {
		if (snapshot.context == "PLAYLIST" && snapshot.playlist == "Favorites" &&
		    snapshot.index == 1 && snapshot.count == 2 && snapshot.path == first)
			adopted = true;
		if (snapshot.context == "PLAYLIST" && snapshot.playlist == "Favorites" &&
		    snapshot.index == 2 && snapshot.count == 2 && snapshot.path == second)
			second_owned = true;
	}
	assert(adopted && second_owned);
	assert(access(snapshot_path.c_str(), F_OK) != 0);
	delete controller;
	delete runtime;
	assert(unlink(first.c_str()) == 0);
	assert(unlink(second.c_str()) == 0);
	assert(rmdir((root + "/one").c_str()) == 0);
	assert(rmdir((root + "/two").c_str()) == 0);
	assert(rmdir(root.c_str()) == 0);
}

void test_post_start_playlist_command_can_lose_initial_playing_race()
{
	ScriptRuntime *runtime = nullptr;
	ScriptController *controller = nullptr;
	const std::vector<Track> folder_tracks = {
		{"2 Selected.vgm", "/album/2 Selected.vgm"},
		{"Folder Next.vgm", "/album/Folder Next.vgm"},
	};
	assert(execute({
		ok(9, PlaybackState::Ended),
		ok(10, PlaybackState::Playing), ok(10, PlaybackState::Ended),
		ok(11, PlaybackState::Playing), ok(11, PlaybackState::Ended)
	}, folder_tracks, &runtime, nullptr, 2,
		{{2, ControlCommandType::Playlist,
		  "/tmp/megavgm_playlist.snapshot-too-late"}},
		&controller) == PlaylistResult::Complete);
	assert(controller->discarded == 1);
	assert(runtime->commands.size() == 2);
	assert(runtime->commands[0] ==
		"load_file 1 /album/2 Selected.vgm\n");
	assert(runtime->commands[1] ==
		"load_file 1 /album/Folder Next.vgm\n");
	for (const ControllerSnapshot &snapshot : controller->snapshots)
		assert(snapshot.context == "DIRECTORY");
	delete controller;
	delete runtime;
}

void test_initial_playlist_snapshot_keeps_five_track_repeat_all_order()
{
	ScriptRuntime *runtime = nullptr;
	ScriptController *controller = nullptr;
	const std::vector<Track> tracks = {
		{"1.vgm", "/list/A/1.vgm"},
		{"2.vgm", "/list/B/2.vgm"},
		{"3.vgm", "/list/C/3.vgm"},
		{"4.vgm", "/list/D/4.vgm"},
		{"5.vgm", "/list/E/5.vgm"},
	};
	PlaybackPreferences preferences;
	preferences.repeat = RepeatMode::All;
	assert(execute({
		ok(9, PlaybackState::Ended),
		ok(10, PlaybackState::Playing), ok(10, PlaybackState::Ended),
		ok(11, PlaybackState::Playing), ok(11, PlaybackState::Ended),
		ok(12, PlaybackState::Playing), ok(12, PlaybackState::Ended),
		ok(13, PlaybackState::Playing), ok(13, PlaybackState::Ended),
		ok(14, PlaybackState::Playing), ok(99, PlaybackState::Playing)
	}, tracks, &runtime, nullptr, 2, {}, &controller, 1, {}, preferences,
		nullptr, "Cold Five") == PlaylistResult::Suspended);
	assert(runtime->commands.size() == 5);
	const std::size_t expected[] = {1, 2, 3, 4, 0};
	for (std::size_t index = 0; index < 5; ++index) {
		assert(runtime->commands[index] ==
			"load_file 1 " + tracks[expected[index]].path + "\n");
	}
	for (const ControllerSnapshot &snapshot : controller->snapshots) {
		assert(snapshot.context == "PLAYLIST");
		assert(snapshot.playlist == "Cold Five");
		assert(snapshot.count == 5);
	}
	delete controller;
	delete runtime;
}

class ZeroRandom final : public RandomSource {
public:
	std::uint32_t uniform(std::uint32_t) override { return 0; }
};

void test_repeat_one_non_loop_reloads_and_manual_next_works()
{
	ScriptRuntime *runtime = nullptr;
	PlaybackPreferences preferences;
	preferences.repeat = RepeatMode::One;
	const std::vector<Track> tracks = {{"Only.vgm", "/music/Only.vgm"}};
	assert(execute({
		ok(9, PlaybackState::Ended),
		ok(10, PlaybackState::Playing),
		ok(10, PlaybackState::Ended),
		ok(11, PlaybackState::Playing),
		ok(11, PlaybackState::Playing)
	}, tracks, &runtime, nullptr, 2,
		{{5, ControlCommandType::Next, {}}}, nullptr, 0, {}, preferences) ==
		PlaylistResult::Complete);
	assert(runtime->commands.size() == 2);
	assert(runtime->commands[0] == runtime->commands[1]);
	delete runtime;
}

void test_repeat_one_native_loop_never_reloads_at_limit()
{
	ScriptRuntime *runtime = nullptr;
	PlaybackPreferences preferences;
	preferences.repeat = RepeatMode::One;
	const std::vector<Track> tracks = {{"Loop.vgm", "/music/Loop.vgm"}};
	assert(execute({
		loop_status(9, PlaybackState::Ended, false, 0),
		loop_status(10, PlaybackState::Playing, true, 0),
		loop_status(10, PlaybackState::Playing, true, 2),
		loop_status(10, PlaybackState::Playing, true, 20)
	}, tracks, &runtime, nullptr, 2,
		{{3, ControlCommandType::Next, {}}}, nullptr, 0, {}, preferences) ==
		PlaylistResult::Complete);
	assert(runtime->commands.size() == 1);
	delete runtime;
}

void test_repeat_all_wrap_and_shuffle_bag()
{
	ScriptRuntime *runtime = nullptr;
	PlaybackPreferences preferences;
	preferences.repeat = RepeatMode::All;
	const std::vector<Track> tracks = three_tracks();
	assert(execute({
		ok(9, PlaybackState::Ended),
		ok(10, PlaybackState::Playing), ok(10, PlaybackState::Ended),
		ok(11, PlaybackState::Playing), ok(11, PlaybackState::Ended),
		ok(12, PlaybackState::Playing), ok(12, PlaybackState::Ended),
		ok(13, PlaybackState::Playing), ok(13, PlaybackState::Playing)
	}, tracks, &runtime, nullptr, 2, {}, nullptr, 0, {}, preferences) ==
		PlaylistResult::TrackEndTimeout);
	assert(runtime->commands.size() == 4);
	assert(runtime->commands[3] == runtime->commands[0]);
	delete runtime;

	ZeroRandom random;
	preferences.repeat = RepeatMode::Off;
	preferences.shuffle = true;
	assert(execute({
		ok(20, PlaybackState::Ended),
		ok(21, PlaybackState::Playing), ok(21, PlaybackState::Ended),
		ok(22, PlaybackState::Playing), ok(22, PlaybackState::Ended),
		ok(23, PlaybackState::Playing), ok(23, PlaybackState::Ended)
	}, tracks, &runtime, nullptr, 2, {}, nullptr, 0, {}, preferences, &random) ==
		PlaylistResult::Complete);
	assert(runtime->commands.size() == 3);
	std::set<std::string> unique(runtime->commands.begin(), runtime->commands.end());
	assert(unique.size() == 3);
	delete runtime;
}

void test_mode_command_survives_owned_load_discard()
{
	ScriptRuntime *runtime = nullptr;
	ScriptController *controller = nullptr;
	const std::vector<Track> tracks = {{"Loop.vgm", "/music/Loop.vgm"}};
	assert(execute({
		loop_status(9, PlaybackState::Ended, false, 0),
		loop_status(10, PlaybackState::Playing, true, 2),
		loop_status(10, PlaybackState::Playing, true, 3)
	}, tracks, &runtime, nullptr, 2,
		{{2, ControlCommandType::Repeat, {}, RepeatMode::One, false},
		 {3, ControlCommandType::Next, {}}}, &controller) ==
		PlaylistResult::Complete);
	assert(runtime->commands.size() == 1);
	assert(controller->saved_preferences.size() == 1);
	assert(controller->saved_preferences[0].repeat == RepeatMode::One);
	assert(controller->discarded == 0);
	delete controller;
	delete runtime;
}

void test_stop_retains_context_and_next_restarts_from_reset_baseline()
{
	ScriptRuntime *runtime = nullptr;
	ScriptController *controller = nullptr;
	std::string run_log;
	std::vector<Track> tracks = three_tracks();
	tracks.resize(2);
	const PlaylistResult result = execute({
		ok(9, PlaybackState::Ended),
		ok(10, PlaybackState::Playing),
		ok(0, PlaybackState::Idle),
		ok(1, PlaybackState::Playing),
		ok(1, PlaybackState::Ended)
	}, tracks, &runtime, &run_log, 2,
		{{2, ControlCommandType::Stop, {}},
		 {3, ControlCommandType::Next, {}}}, &controller);
	if (result != PlaylistResult::Complete) std::cerr << run_log;
	assert(result == PlaylistResult::Complete);
	assert(runtime->commands.size() == 3);
	assert(runtime->commands[0] == "load_file 1 " + tracks[0].path + "\n");
	assert(runtime->commands[1] == "reset_core\n");
	assert(runtime->commands[2] == "load_file 1 " + tracks[1].path + "\n");
	bool stopped = false;
	for (const ControllerSnapshot &snapshot : controller->snapshots) {
		if (snapshot.state == "STOPPED") {
			assert(snapshot.index == 1);
			assert(snapshot.count == tracks.size());
			assert(snapshot.path == tracks[0].path);
			assert(snapshot.session == 10);
			assert(snapshot.context == "DIRECTORY");
			stopped = true;
		}
	}
	assert(stopped);
	delete controller;
	delete runtime;
}

void test_stop_then_previous_and_repeat_one_do_not_auto_advance()
{
	ScriptRuntime *runtime = nullptr;
	ScriptController *controller = nullptr;
	PlaybackPreferences preferences;
	preferences.repeat = RepeatMode::One;
	const std::vector<Track> tracks = three_tracks();
	assert(execute({
		loop_status(7, PlaybackState::Ended, false, 0),
		loop_status(8, PlaybackState::Playing, true, 12),
		loop_status(0, PlaybackState::Idle, false, 0),
		loop_status(1, PlaybackState::Playing, false, 0),
		loop_status(1, PlaybackState::Playing, false, 0)
	}, tracks, &runtime, nullptr, 2,
		{{2, ControlCommandType::Stop, {}},
		 {3, ControlCommandType::Previous, {}}}, &controller, 1, {},
		preferences) == PlaylistResult::TrackEndTimeout);
	assert(runtime->commands.size() == 3);
	assert(runtime->commands[0] == "load_file 1 " + tracks[1].path + "\n");
	assert(runtime->commands[1] == "reset_core\n");
	assert(runtime->commands[2] == "load_file 1 " + tracks[0].path + "\n");
	for (std::size_t command = 1; command + 1 < runtime->commands.size(); ++command)
		assert(runtime->commands[command] == "reset_core\n");
	delete controller;
	delete runtime;
}

void test_stop_command_failure_and_timeout()
{
	ScriptRuntime *runtime = nullptr;
	ScriptController *controller = nullptr;
	const std::vector<Track> tracks = {three_tracks()[0]};
	auto *failing_runtime = new ScriptRuntime({
		ok(1, PlaybackState::Ended), ok(2, PlaybackState::Playing)});
	failing_runtime->stop_ok = false;
	auto *failing_controller = new ScriptController(*failing_runtime,
		{{2, ControlCommandType::Stop, {}}});
	std::ostringstream log;
	assert(run(*failing_runtime, fast_config(), tracks, log,
		failing_controller) == PlaylistResult::StopCommandFailed);
	delete failing_controller;
	delete failing_runtime;

	assert(execute({
		ok(1, PlaybackState::Ended),
		ok(2, PlaybackState::Playing),
		ok(2, PlaybackState::Playing)
	}, tracks, &runtime, nullptr, 2,
		{{2, ControlCommandType::Stop, {}}}, &controller) ==
		PlaylistResult::StopTimeout);
	assert(runtime->commands.size() == 2);
	assert(runtime->commands[1] == "reset_core\n");
	delete controller;
	delete runtime;
}

void test_twenty_play_stop_cycles_never_auto_advance()
{
	char root_template[] = "/tmp/megavgm_stop_stress.XXXXXX";
	char *root_name = mkdtemp(root_template);
	assert(root_name);
	const std::string path = std::string(root_name) + "/Only.vgm";
	create_file(path);
	std::vector<Frame> frames = {ok(90, PlaybackState::Ended)};
	std::vector<ControlEvent> events;
	for (std::size_t cycle = 0; cycle < 20; ++cycle) {
		frames.push_back(ok(1, PlaybackState::Playing));
		frames.push_back(ok(0, PlaybackState::Idle));
		const std::size_t playing_read = 2 + cycle * 2;
		events.push_back({playing_read, ControlCommandType::Stop, {}});
		if (cycle + 1 < 20)
			events.push_back({playing_read + 1, ControlCommandType::Play, path});
	}
	events.push_back({41, ControlCommandType::Next, {}});
	ScriptRuntime *runtime = nullptr;
	ScriptController *controller = nullptr;
	assert(execute(std::move(frames), {{"Only.vgm", path}}, &runtime, nullptr,
		2, std::move(events), &controller) == PlaylistResult::Complete);
	assert(runtime->commands.size() == 40);
	std::size_t stopped_count = 0;
	for (const ControllerSnapshot &snapshot : controller->snapshots)
		if (snapshot.state == "STOPPED") stopped_count++;
	assert(stopped_count == 20);
	delete controller;
	delete runtime;
	assert(unlink(path.c_str()) == 0);
	assert(rmdir(root_name) == 0);
}

void test_play_current_from_stopped_restarts_from_beginning()
{
	char root_template[] = "/tmp/megavgm_stop_replay.XXXXXX";
	char *root_name = mkdtemp(root_template);
	assert(root_name);
	const std::string path = std::string(root_name) + "/Current.vgm";
	create_file(path);
	ScriptRuntime *runtime = nullptr;
	ScriptController *controller = nullptr;
	assert(execute({
		ok(30, PlaybackState::Ended),
		ok(31, PlaybackState::Playing),
		ok(0, PlaybackState::Idle),
		ok(1, PlaybackState::Playing),
		ok(1, PlaybackState::Ended)
	}, {{"Current.vgm", path}}, &runtime, nullptr, 2,
		{{2, ControlCommandType::Stop, {}},
		 {3, ControlCommandType::Play, path}}, &controller) ==
		PlaylistResult::Complete);
	assert(runtime->commands.size() == 3);
	assert(runtime->commands[0] == runtime->commands[2]);
	assert(runtime->commands[1] == "reset_core\n");
	delete controller;
	delete runtime;
	assert(unlink(path.c_str()) == 0);
	assert(rmdir(root_name) == 0);
}

void test_playlist_selection_from_stopped_replaces_context()
{
	char root_template[] = "/tmp/megavgm_stop_playlist.XXXXXX";
	char *root_name = mkdtemp(root_template);
	assert(root_name);
	char canonical_root[PATH_MAX];
	assert(realpath(root_name, canonical_root));
	const std::string root(canonical_root);
	const std::string first = root + "/First.vgm";
	const std::string second = root + "/Second.vgm";
	create_file(first);
	create_file(second);
	const std::string snapshot_path = root + "/stop.snapshot";
	{
		std::ofstream snapshot(snapshot_path);
		snapshot << "MEGAVGM_PLAYLIST_V1\nNAME Stop List\nSTART 1\nCOUNT 2\n"
		         << "PATH " << first << '\n' << "PATH " << second << '\n';
	}
	ScriptRuntime *runtime = nullptr;
	ScriptController *controller = nullptr;
	assert(execute({
		ok(40, PlaybackState::Ended),
		ok(41, PlaybackState::Playing),
		ok(0, PlaybackState::Idle),
		ok(1, PlaybackState::Playing),
		ok(1, PlaybackState::Ended)
	}, {{"First.vgm", first}}, &runtime, nullptr, 2,
		{{2, ControlCommandType::Stop, {}},
		 {3, ControlCommandType::Playlist, snapshot_path}}, &controller, 0,
		root) == PlaylistResult::Complete);
	assert(runtime->commands.size() == 3);
	assert(runtime->commands[2] == "load_file 1 " + second + "\n");
	bool playlist_context = false;
	for (const ControllerSnapshot &snapshot : controller->snapshots) {
		if (snapshot.path == second && snapshot.context == "PLAYLIST" &&
		    snapshot.playlist == "Stop List" && snapshot.index == 2 &&
		    snapshot.count == 2)
			playlist_context = true;
	}
	assert(playlist_context);
	delete controller;
	delete runtime;
	assert(unlink(first.c_str()) == 0);
	assert(unlink(second.c_str()) == 0);
	assert(rmdir(root.c_str()) == 0);
}

void test_repeat_all_and_shuffle_updates_remain_stopped()
{
	ScriptRuntime *runtime = nullptr;
	ScriptController *controller = nullptr;
	const std::vector<Track> tracks = three_tracks();
	assert(execute({
		ok(60, PlaybackState::Ended),
		ok(61, PlaybackState::Playing),
		ok(0, PlaybackState::Idle),
		ok(1, PlaybackState::Playing),
		ok(1, PlaybackState::Playing)
	}, tracks, &runtime, nullptr, 2,
		{{2, ControlCommandType::Stop, {}},
		 {3, ControlCommandType::Repeat, {}, RepeatMode::All, false},
		 {3, ControlCommandType::Shuffle, {}, RepeatMode::Off, true},
		 {3, ControlCommandType::Previous, {}}}, &controller, 1) ==
		PlaylistResult::TrackEndTimeout);
	assert(runtime->commands.size() == 3);
	assert(runtime->commands[1] == "reset_core\n");
	assert(controller->saved_preferences.size() == 2);
	assert(controller->saved_preferences.back().repeat == RepeatMode::All);
	assert(controller->saved_preferences.back().shuffle);
	bool stopped_with_modes = false;
	for (const ControllerSnapshot &snapshot : controller->snapshots) {
		if (snapshot.state == "STOPPED" && snapshot.repeat == RepeatMode::All &&
		    snapshot.shuffle)
			stopped_with_modes = true;
	}
	assert(stopped_with_modes);
	delete controller;
	delete runtime;
}

void test_stop_during_owned_load_is_not_lost()
{
	ScriptRuntime *runtime = nullptr;
	ScriptController *controller = nullptr;
	const std::vector<Track> tracks = {{"Loading.vgm", "/music/Loading.vgm"}};
	assert(execute({
		ok(70, PlaybackState::Ended),
		ok(71, PlaybackState::Loading),
		ok(71, PlaybackState::Playing),
		ok(0, PlaybackState::Idle)
	}, tracks, &runtime, nullptr, 2,
		{{2, ControlCommandType::Stop, {}},
		 {4, ControlCommandType::Next, {}}}, &controller) ==
		PlaylistResult::Complete);
	assert(runtime->commands.size() == 2);
	assert(runtime->commands[1] == "reset_core\n");
	assert(controller->discarded == 0);
	assert(controller->snapshots.back().state == "COMPLETE");
	delete controller;
	delete runtime;
}

} // namespace

int main()
{
	test_native_loop_limit_and_stale_reset();
	test_loop_counter_saturation_policy();
	test_loop_limit_zero_is_infinite();
	test_next_during_track_two_and_stale_end();
	test_previous_during_track_three();
	test_previous_restarts_first_track();
	test_next_at_last_track_completes();
	test_single_track_natural_end_completes_once();
	test_next_wins_loop_limit_race();
	test_manual_and_automatic_next_share_one_transition_owner();
	test_loop_limit_uses_guarded_transition_once();
	test_rapid_next_is_ignored_during_owned_load();
	test_three_tracks_and_duplicate_end();
	test_manual_suspension();
	test_fatal_skips_to_next();
	test_fatal_before_loop_limit();
	test_missing_and_timeout();
	test_discovery_and_ordering();
	test_empty_directory();
	test_playlist_snapshot_adopts_current_and_owns_auto_next();
	test_post_start_playlist_command_can_lose_initial_playing_race();
	test_initial_playlist_snapshot_keeps_five_track_repeat_all_order();
	test_repeat_one_non_loop_reloads_and_manual_next_works();
	test_repeat_one_native_loop_never_reloads_at_limit();
	test_repeat_all_wrap_and_shuffle_bag();
	test_mode_command_survives_owned_load_discard();
	test_stop_retains_context_and_next_restarts_from_reset_baseline();
	test_stop_then_previous_and_repeat_one_do_not_auto_advance();
	test_stop_command_failure_and_timeout();
	test_twenty_play_stop_cycles_never_auto_advance();
	test_play_current_from_stopped_restarts_from_beginning();
	test_playlist_selection_from_stopped_replaces_context();
	test_repeat_all_and_shuffle_updates_remain_stopped();
	test_stop_during_owned_load_is_not_lost();
	std::cout << "megavgm_playlist host tests: PASS\n";
	return 0;
}
