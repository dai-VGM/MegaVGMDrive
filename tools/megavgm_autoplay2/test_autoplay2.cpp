#include "autoplay2.h"

#include <cassert>
#include <chrono>
#include <cerrno>
#include <cstring>
#include <fcntl.h>
#include <iostream>
#include <poll.h>
#include <sstream>
#include <string>
#include <sys/stat.h>
#include <thread>
#include <unistd.h>
#include <vector>

using namespace megavgm_autoplay2;

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
		if (!build_load_command(path, command, detail)) return false;
		commands.push_back(command);
		return true;
	}

	bool issue_stop(std::string &detail) override
	{
		std::string command;
		build_stop_command(command);
		commands.push_back(command);
		detail.clear();
		return true;
	}

	bool issue_transition(TransitionReason, std::string &detail) override
	{
		detail.clear();
		return true;
	}

	std::uint64_t monotonic_ms() override { return now_ms_; }

	void sleep_ms(std::uint32_t milliseconds) override
	{
		now_ms_ += milliseconds;
	}

	std::vector<std::string> commands;

private:
	const Frame &current() const
	{
		return frames_[position_ < frames_.size() ? position_ : frames_.size() - 1];
	}

	std::vector<Frame> frames_;
	std::size_t position_ = 0;
	std::uint64_t now_ms_ = 0;
};

ControllerConfig fast_config()
{
	ControllerConfig config;
	config.track_start_timeout_ms = 4;
	config.track_end_timeout_ms = 4;
	config.next_session_timeout_ms = 4;
	config.track_b_playing_timeout_ms = 4;
	config.poll_interval_ms = 1;
	config.main_probe_interval_ms = 1;
	return config;
}

RunResult execute(std::vector<Frame> frames, ScriptRuntime **out_runtime = nullptr,
		std::string *out_log = nullptr,
		const std::string &track_a = "/media/fat/A.vgm",
		const std::string &track_b = "/media/fat/B.vgm")
{
	auto *runtime = new ScriptRuntime(std::move(frames));
	std::ostringstream log;
	const RunResult result = run(*runtime, fast_config(), track_a, track_b, log);
	if (out_log) *out_log = log.str();
	if (out_runtime) *out_runtime = runtime;
	else delete runtime;
	return result;
}

void test_success_and_duplicate_end()
{
	ScriptRuntime *runtime = nullptr;
	std::string log;
	const std::string track_a =
		"/media/fat/MegaVGMDrive/01 Track A (Arcade) [JP].vgm";
	const std::string track_b =
		"/media/fat/MegaVGMDrive/02 æ¥æ¬èª Track B [Final].vgm";
	const RunResult result = execute({
		ok(9, PlaybackState::Ended),
		ok(10, PlaybackState::Loading),
		ok(10, PlaybackState::Playing),
		ok(10, PlaybackState::Playing),
		ok(10, PlaybackState::Ended),
		ok(10, PlaybackState::Ended),
		ok(10, PlaybackState::Ended),
		ok(11, PlaybackState::Loading),
		ok(11, PlaybackState::Playing)
	}, &runtime, &log, track_a, track_b);
	assert(result == RunResult::Pass);
	assert(runtime->commands.size() == 2);
	assert(runtime->commands[0] == "load_file 1 " + track_a + "\n");
	assert(runtime->commands[1] == "load_file 1 " + track_b + "\n");
	assert(log.find("session=10 PLAYING") != std::string::npos);
	assert(log.find("session=10 ENDED") != std::string::npos);
	assert(log.find("session=11 PLAYING") != std::string::npos);
	assert(log.find("AUTOPLAY2 PASS") != std::string::npos);
	delete runtime;
}

void test_status_parser()
{
	PlaybackStatus parsed;
	std::string detail;
	assert(parse_status_text(
		"version=1\nsession=4294967295\nstate=PLAYING\nerror=0D\n",
		parsed, detail) == StatusReadResult::Ok);
	assert(parsed.session == UINT32_MAX);
	assert(parsed.state == PlaybackState::Playing);
	assert(parsed.error == 0x0d);
	assert(parse_status_text(
		"version=2\nsession=1\nstate=PLAYING\nerror=00\n"
		"loop_valid=1\nloop_count=2\n",
		parsed, detail) == StatusReadResult::Ok);
	assert(parsed.version == 2);
	assert(parsed.loop_valid);
	assert(parsed.loop_count == 2);
	assert(parse_status_text(
		"version=3\nsession=1\nstate=ENDED\nerror=00\n",
		parsed, detail) == StatusReadResult::UnsupportedVersion);
	assert(parse_status_text(
		"version=2\nsession=1\nstate=PLAYING\nerror=00\n",
		parsed, detail) == StatusReadResult::Malformed);
	assert(parse_status_text(
		"version=1\nsession=x\nstate=ENDED\nerror=00\n",
		parsed, detail) == StatusReadResult::Malformed);
	assert(parse_status_text(
		"version=1\nsession=1\nstate=ENDED\n",
		parsed, detail) == StatusReadResult::Malformed);
}

void test_failures()
{
	assert(execute({
		{StatusReadResult::Missing, {}, "not found", true}
	}) == RunResult::StatusFileMissing);

	assert(execute({
		{StatusReadResult::Malformed, {}, "bad snapshot", true}
	}) == RunResult::MalformedStatus);

	assert(execute({
		{StatusReadResult::UnsupportedVersion, {}, "version 2", true}
	}) == RunResult::UnsupportedVersion);

	assert(execute({
		ok(9, PlaybackState::Ended),
		ok(10, PlaybackState::Loading),
		ok(10, PlaybackState::Fatal, 0x0d)
	}) == RunResult::FatalStatus);

	assert(execute({
		ok(9, PlaybackState::Ended),
		ok(10, PlaybackState::Playing, 0x01)
	}) == RunResult::NonzeroError);

	assert(execute({
		ok(9, PlaybackState::Ended),
		ok(10, PlaybackState::Playing),
		ok(11, PlaybackState::Loading)
	}) == RunResult::ManualOrExternalSessionChange);

	assert(execute({
		ok(9, PlaybackState::Ended),
		ok(10, PlaybackState::Loading)
	}) == RunResult::TrackANeverStarts);

	assert(execute({
		ok(9, PlaybackState::Ended),
		ok(10, PlaybackState::Playing)
	}) == RunResult::TrackANeverEnds);

	assert(execute({
		ok(9, PlaybackState::Ended),
		ok(10, PlaybackState::Playing),
		ok(10, PlaybackState::Ended)
	}) == RunResult::TrackBSessionTimeout);

	assert(execute({
		ok(9, PlaybackState::Ended),
		ok(10, PlaybackState::Playing),
		ok(10, PlaybackState::Ended),
		ok(11, PlaybackState::Loading)
	}) == RunResult::TrackBNeverPlaying);

	assert(execute({
		ok(9, PlaybackState::Ended),
		ok(10, PlaybackState::Loading, 0, false)
	}) == RunResult::ActiveMainUnavailable);
}

void test_invalid_paths()
{
	std::string command;
	std::string detail;
	assert(!build_load_command("bad\npath.vgm", command, detail));
	assert(!build_load_command("", command, detail));
	assert(!build_load_command(std::string(961, 'a'), command, detail));
	assert(build_transition_command(TransitionReason::LoopLimitTwoLoops,
		"/tmp/megavgm_transition.control", command, detail));
	assert(command == "load_file 2 /tmp/megavgm_transition.control\n");
	assert(!build_transition_command(TransitionReason::LoopLimitDisabled,
		"bad\npath", command, detail));
	assert(execute({ok(1, PlaybackState::Idle)}, nullptr, nullptr,
		"bad\npath.vgm", "/media/fat/B.vgm") == RunResult::InvalidTrackPath);
}

void write_all(int fd, const std::string &text)
{
	std::size_t offset = 0;
	while (offset < text.size()) {
		const ssize_t count = write(fd, text.data() + offset, text.size() - offset);
		if (count > 0) {
			offset += static_cast<std::size_t>(count);
			continue;
		}
		if (count < 0 && errno == EINTR) continue;
		assert(false && "test fixture write failed");
	}
}

void publish_status(const std::string &path, std::uint32_t session,
		PlaybackState state)
{
	const std::string temporary = path + ".new";
	const int fd = open(temporary.c_str(),
			O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0600);
	assert(fd >= 0);
	std::ostringstream text;
	text << "version=1\nsession=" << session << "\nstate="
	     << state_name(state) << "\nerror=00\n";
	write_all(fd, text.str());
	assert(close(fd) == 0);
	assert(rename(temporary.c_str(), path.c_str()) == 0);
}

std::string read_fifo_line(int fd, std::string &pending)
{
	const auto deadline = std::chrono::steady_clock::now() +
		std::chrono::seconds(2);
	for (;;) {
		const std::size_t newline = pending.find('\n');
		if (newline != std::string::npos) {
			const std::string line = pending.substr(0, newline + 1);
			pending.erase(0, newline + 1);
			return line;
		}
		assert(std::chrono::steady_clock::now() < deadline);
		struct pollfd descriptor = {fd, POLLIN, 0};
		const int ready = poll(&descriptor, 1, 20);
		assert(ready >= 0 || errno == EINTR);
		if (ready <= 0) continue;
		char buffer[256];
		const ssize_t count = read(fd, buffer, sizeof(buffer));
		if (count > 0) pending.append(buffer, static_cast<std::size_t>(count));
		else if (count < 0) assert(errno == EAGAIN || errno == EINTR);
	}
}

void test_posix_status_and_fifo_integration()
{
	char directory_template[] = "/tmp/megavgm_autoplay2_test.XXXXXX";
	char *directory_name = mkdtemp(directory_template);
	assert(directory_name);
	const std::string directory(directory_name);
	const std::string status_path = directory + "/status";
	const std::string command_path = directory + "/MiSTer_cmd";
	assert(mkfifo(command_path.c_str(), 0600) == 0);
	const int fifo_fd = open(command_path.c_str(), O_RDWR | O_NONBLOCK | O_CLOEXEC);
	assert(fifo_fd >= 0);

	publish_status(status_path, 9, PlaybackState::Ended);
	const std::string track_a =
		"/media/fat/MegaVGMDrive/01 Track A (Arcade) [JP].vgm";
	const std::string track_b =
		"/media/fat/MegaVGMDrive/02 æ¥æ¬èª Track B [Final].vgm";
	std::vector<std::string> commands;

	std::thread simulated_main([&]() {
		std::string pending;
		commands.push_back(read_fifo_line(fifo_fd, pending));
		publish_status(status_path, 10, PlaybackState::Loading);
		std::this_thread::sleep_for(std::chrono::milliseconds(15));
		publish_status(status_path, 10, PlaybackState::Playing);
		std::this_thread::sleep_for(std::chrono::milliseconds(15));
		publish_status(status_path, 10, PlaybackState::Ended);
		std::this_thread::sleep_for(std::chrono::milliseconds(15));
		publish_status(status_path, 10, PlaybackState::Ended);
		commands.push_back(read_fifo_line(fifo_fd, pending));
		// Keep publishing A's latched ENDED after B was requested. The
		// controller must wait for the new session without issuing B again.
		publish_status(status_path, 10, PlaybackState::Ended);
		std::this_thread::sleep_for(std::chrono::milliseconds(15));
		publish_status(status_path, 10, PlaybackState::Ended);
		std::this_thread::sleep_for(std::chrono::milliseconds(15));
		publish_status(status_path, 11, PlaybackState::Loading);
		std::this_thread::sleep_for(std::chrono::milliseconds(15));
		publish_status(status_path, 11, PlaybackState::Playing);
	});

	PosixRuntime runtime(status_path, command_path);
	ControllerConfig config;
	config.track_start_timeout_ms = 2000;
	config.track_end_timeout_ms = 2000;
	config.next_session_timeout_ms = 2000;
	config.track_b_playing_timeout_ms = 2000;
	config.poll_interval_ms = 2;
	config.main_probe_interval_ms = 10;
	std::ostringstream log;
	const RunResult result = run(runtime, config, track_a, track_b, log);
	simulated_main.join();

	assert(result == RunResult::Pass);
	assert(commands.size() == 2);
	assert(commands[0] == "load_file 1 " + track_a + "\n");
	assert(commands[1] == "load_file 1 " + track_b + "\n");
	assert(log.str().find("AUTOPLAY2 PASS") != std::string::npos);

	assert(close(fifo_fd) == 0);
	assert(unlink(status_path.c_str()) == 0);
	assert(unlink(command_path.c_str()) == 0);
	assert(rmdir(directory.c_str()) == 0);
}

} // namespace

int main()
{
	test_success_and_duplicate_end();
	test_status_parser();
	test_failures();
	test_invalid_paths();
	test_posix_status_and_fifo_integration();
	std::cout << "megavgm_autoplay2 host tests: PASS\n";
	return 0;
}
