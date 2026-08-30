#include "playlist.h"

#include <cassert>
#include <cerrno>
#include <fcntl.h>
#include <iostream>
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

	std::uint64_t monotonic_ms() override { return now_ms_; }

	void sleep_ms(std::uint32_t milliseconds) override
	{
		now_ms_ += milliseconds;
	}

	std::vector<std::string> commands;
	std::size_t read_count = 0;

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
	NavigationCommand command;
};

class ScriptController final : public ControllerIo {
public:
	ScriptController(ScriptRuntime &runtime, std::vector<ControlEvent> events)
		: runtime_(runtime), events_(std::move(events))
	{
	}

	ControlPollResult poll_command(NavigationCommand &command,
			std::string &detail) override
	{
		if (position_ >= events_.size() ||
		    events_[position_].after_reads > runtime_.read_count) {
			detail.clear();
			return ControlPollResult::None;
		}
		command = events_[position_++].command;
		detail.clear();
		return ControlPollResult::Command;
	}

	bool discard_commands(std::string &detail) override
	{
		while (position_ < events_.size() &&
		       events_[position_].after_reads <= runtime_.read_count) {
			position_++;
			discarded++;
		}
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

private:
	ScriptRuntime &runtime_;
	std::vector<ControlEvent> events_;
	std::size_t position_ = 0;
};

PlaylistConfig fast_config()
{
	PlaylistConfig config;
	config.session_timeout_ms = 5;
	config.playing_timeout_ms = 5;
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
		ScriptController **out_controller = nullptr)
{
	auto *runtime = new ScriptRuntime(std::move(frames));
	auto *controller = new ScriptController(*runtime, std::move(control_events));
	std::ostringstream log;
	PlaylistConfig config = fast_config();
	config.loop_limit = loop_limit;
	const PlaylistResult result = run(*runtime, config, tracks, log, controller);
	if (out_log) *out_log = log.str();
	if (out_controller) *out_controller = controller;
	else delete controller;
	if (out_runtime) *out_runtime = runtime;
	else delete runtime;
	return result;
}

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
		{{5, NavigationCommand::Next}}, &controller);
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
		{{7, NavigationCommand::Previous}});
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
		{{3, NavigationCommand::Previous}});
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
		{{3, NavigationCommand::Next}});
	assert(result == PlaylistResult::Complete);
	assert(runtime->commands.size() == 1);
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
		{{3, NavigationCommand::Next}});
	assert(result == PlaylistResult::Complete);
	assert(runtime->commands.size() == 2);
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
		{{3, NavigationCommand::Next}, {3, NavigationCommand::Next}},
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

	assert(execute({
		ok(40, PlaybackState::Ended)
	}, three_tracks()) == PlaylistResult::TrackSessionTimeout);

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
	test_next_wins_loop_limit_race();
	test_rapid_next_is_ignored_during_owned_load();
	test_three_tracks_and_duplicate_end();
	test_manual_suspension();
	test_fatal_skips_to_next();
	test_fatal_before_loop_limit();
	test_missing_and_timeout();
	test_discovery_and_ordering();
	test_empty_directory();
	std::cout << "megavgm_playlist host tests: PASS\n";
	return 0;
}
