#include "autoplay2.h"

#include <cerrno>
#include <chrono>
#include <climits>
#include <csignal>
#include <cstring>
#include <fcntl.h>
#include <poll.h>
#include <sstream>
#include <time.h>
#include <unistd.h>
#include <utility>

namespace megavgm_autoplay2 {
namespace {

constexpr std::uint32_t kInterfaceVersionV1 = 1;
constexpr std::uint32_t kInterfaceVersionV2 = 2;
constexpr std::size_t kMaximumStatusBytes = 512;
constexpr std::size_t kMaximumTrackPathBytes = 960;
const char kTransitionControlPath[] = "/tmp/megavgm_transition.control";
unsigned char loop_limit_policy_value(TransitionReason reason)
{
	return reason == TransitionReason::LoopLimitTwoLoops ? 1 : 0;
}

bool parse_unsigned(const std::string &text, unsigned int base,
		std::uint32_t maximum, std::uint32_t &value)
{
	if (text.empty()) return false;
	std::uint64_t result = 0;
	for (unsigned char c : text) {
		unsigned int digit;
		if (c >= '0' && c <= '9') digit = c - '0';
		else if (base == 16 && c >= 'a' && c <= 'f') digit = c - 'a' + 10;
		else if (base == 16 && c >= 'A' && c <= 'F') digit = c - 'A' + 10;
		else return false;
		if (digit >= base) return false;
		result = result * base + digit;
		if (result > maximum) return false;
	}
	value = static_cast<std::uint32_t>(result);
	return true;
}

RunResult map_read_failure(StatusReadResult result)
{
	switch (result) {
	case StatusReadResult::Missing: return RunResult::StatusFileMissing;
	case StatusReadResult::Malformed: return RunResult::MalformedStatus;
	case StatusReadResult::UnsupportedVersion:
		return RunResult::UnsupportedVersion;
	case StatusReadResult::IoError: return RunResult::StatusIoError;
	default: return RunResult::StatusIoError;
	}
}

RunResult validate_status(const PlaybackStatus &status, std::ostream &log)
{
	if (status.state == PlaybackState::Fatal) {
		log << "FATAL session=" << status.session << " error=";
		log << std::hex << static_cast<unsigned int>(status.error)
		    << std::dec << '\n';
		return RunResult::FatalStatus;
	}
	if (status.error != 0) {
		log << "NONZERO_ERROR session=" << status.session << " error=";
		log << std::hex << static_cast<unsigned int>(status.error)
		    << std::dec << '\n';
		return RunResult::NonzeroError;
	}
	return RunResult::Pass;
}

class Monitor {
public:
	Monitor(Runtime &runtime, const ControllerConfig &config, std::ostream &log)
		: runtime_(runtime), config_(config), log_(log),
		  next_main_probe_(runtime.monotonic_ms())
	{
	}

	RunResult read(PlaybackStatus &status)
	{
		const std::uint64_t now = runtime_.monotonic_ms();
		if (now >= next_main_probe_) {
			std::string detail;
			if (!runtime_.main_available(detail)) {
				log_ << "ACTIVE_MAIN_UNAVAILABLE";
				if (!detail.empty()) log_ << ": " << detail;
				log_ << '\n';
				return RunResult::ActiveMainUnavailable;
			}
			next_main_probe_ = now + config_.main_probe_interval_ms;
		}

		std::string detail;
		const StatusReadResult read_result = runtime_.read_status(status, detail);
		if (read_result != StatusReadResult::Ok) {
			const RunResult result = map_read_failure(read_result);
			log_ << run_result_name(result);
			if (!detail.empty()) log_ << ": " << detail;
			log_ << '\n';
			return result;
		}
		return validate_status(status, log_);
	}

	void sleep()
	{
		runtime_.sleep_ms(config_.poll_interval_ms);
	}

private:
	Runtime &runtime_;
	const ControllerConfig &config_;
	std::ostream &log_;
	std::uint64_t next_main_probe_;
};

void log_status(std::ostream &log, const PlaybackStatus &status,
		PlaybackStatus &last, bool &last_valid)
{
	if (last_valid && last.session == status.session &&
	    last.state == status.state && last.error == status.error)
		return;
	log << "session=" << status.session << ' ' << state_name(status.state);
	if (status.error) {
		log << " error=" << std::hex
		    << static_cast<unsigned int>(status.error) << std::dec;
	}
	log << '\n';
	last = status;
	last_valid = true;
}

bool timed_out(Runtime &runtime, std::uint64_t deadline)
{
	return runtime.monotonic_ms() >= deadline;
}

} // namespace

const char *state_name(PlaybackState state)
{
	switch (state) {
	case PlaybackState::Idle: return "IDLE";
	case PlaybackState::Loading: return "LOADING";
	case PlaybackState::Playing: return "PLAYING";
	case PlaybackState::Ended: return "ENDED";
	case PlaybackState::Fatal: return "FATAL";
	}
	return "UNKNOWN";
}

const char *run_result_name(RunResult result)
{
	switch (result) {
	case RunResult::Pass: return "AUTOPLAY2 PASS";
	case RunResult::StatusFileMissing: return "STATUS_FILE_MISSING";
	case RunResult::MalformedStatus: return "MALFORMED_STATUS";
	case RunResult::UnsupportedVersion: return "INVALID_VERSION";
	case RunResult::StatusIoError: return "STATUS_IO_ERROR";
	case RunResult::FatalStatus: return "FATAL_STATUS";
	case RunResult::NonzeroError: return "NONZERO_ERROR";
	case RunResult::ActiveMainUnavailable: return "ACTIVE_MAIN_UNAVAILABLE";
	case RunResult::InvalidTrackPath: return "INVALID_TRACK_PATH";
	case RunResult::CommandWriteFailed: return "COMMAND_WRITE_FAILED";
	case RunResult::TrackANeverStarts: return "TRACK_A_NEVER_STARTS";
	case RunResult::TrackANeverEnds: return "TRACK_A_NEVER_ENDS";
	case RunResult::TrackBSessionTimeout: return "TRACK_B_SESSION_TIMEOUT";
	case RunResult::TrackBNeverPlaying: return "TRACK_B_NEVER_PLAYING";
	case RunResult::ManualOrExternalSessionChange:
		return "MANUAL_OR_EXTERNAL_SESSION_CHANGE";
	}
	return "UNKNOWN_ERROR";
}

StatusReadResult parse_status_text(const std::string &text,
		PlaybackStatus &status, std::string &detail)
{
	bool have_version = false;
	bool have_session = false;
	bool have_state = false;
	bool have_error = false;
	bool have_loop_valid = false;
	bool have_loop_count = false;
	PlaybackStatus parsed;

	if (text.empty()) {
		detail = "empty status snapshot";
		return StatusReadResult::Malformed;
	}

	std::size_t offset = 0;
	while (offset < text.size()) {
		const std::size_t newline = text.find('\n', offset);
		const std::size_t end = newline == std::string::npos ? text.size() : newline;
		const std::string line = text.substr(offset, end - offset);
		offset = newline == std::string::npos ? text.size() : newline + 1;
		if (line.empty()) {
			if (offset == text.size()) continue;
			detail = "unexpected empty line";
			return StatusReadResult::Malformed;
		}

		const std::size_t separator = line.find('=');
		if (separator == std::string::npos || line.find('=', separator + 1) != std::string::npos) {
			detail = "invalid key/value line";
			return StatusReadResult::Malformed;
		}
		const std::string key = line.substr(0, separator);
		const std::string value = line.substr(separator + 1);
		std::uint32_t number = 0;

		if (key == "version" && !have_version) {
			if (!parse_unsigned(value, 10, UINT32_MAX, number)) {
				detail = "invalid version";
				return StatusReadResult::Malformed;
			}
			parsed.version = number;
			have_version = true;
		} else if (key == "session" && !have_session) {
			if (!parse_unsigned(value, 10, UINT32_MAX, number)) {
				detail = "invalid session";
				return StatusReadResult::Malformed;
			}
			parsed.session = number;
			have_session = true;
		} else if (key == "state" && !have_state) {
			if (value == "IDLE") parsed.state = PlaybackState::Idle;
			else if (value == "LOADING") parsed.state = PlaybackState::Loading;
			else if (value == "PLAYING") parsed.state = PlaybackState::Playing;
			else if (value == "ENDED") parsed.state = PlaybackState::Ended;
			else if (value == "FATAL") parsed.state = PlaybackState::Fatal;
			else {
				detail = "invalid state";
				return StatusReadResult::Malformed;
			}
			have_state = true;
		} else if (key == "error" && !have_error) {
			if (value.size() != 2 || !parse_unsigned(value, 16, 0xff, number)) {
				detail = "invalid error code";
				return StatusReadResult::Malformed;
			}
			parsed.error = static_cast<std::uint8_t>(number);
			have_error = true;
		} else if (key == "loop_valid" && !have_loop_valid) {
			if (!parse_unsigned(value, 10, 1, number)) {
				detail = "invalid loop_valid";
				return StatusReadResult::Malformed;
			}
			parsed.loop_valid = number != 0;
			have_loop_valid = true;
		} else if (key == "loop_count" && !have_loop_count) {
			if (!parse_unsigned(value, 10, 0xffff, number)) {
				detail = "invalid loop_count";
				return StatusReadResult::Malformed;
			}
			parsed.loop_count = static_cast<std::uint16_t>(number);
			have_loop_count = true;
		} else {
			detail = "unknown or duplicate key";
			return StatusReadResult::Malformed;
		}
	}

	if (!have_version || !have_session || !have_state || !have_error) {
		detail = "incomplete status snapshot";
		return StatusReadResult::Malformed;
	}
	if (parsed.version == kInterfaceVersionV1) {
		if (have_loop_valid || have_loop_count) {
			detail = "v1 status contains v2 loop fields";
			return StatusReadResult::Malformed;
		}
		parsed.loop_valid = false;
		parsed.loop_count = 0;
	} else if (parsed.version == kInterfaceVersionV2) {
		if (!have_loop_valid || !have_loop_count) {
			detail = "v2 status is missing loop fields";
			return StatusReadResult::Malformed;
		}
	} else {
		detail = "unsupported interface version";
		return StatusReadResult::UnsupportedVersion;
	}
	status = parsed;
	detail.clear();
	return StatusReadResult::Ok;
}

bool build_load_command(const std::string &path, std::string &command,
		std::string &detail)
{
	if (path.empty() || path.size() > kMaximumTrackPathBytes) {
		detail = path.empty() ? "empty track path" : "track path exceeds 960 bytes";
		return false;
	}
	for (unsigned char c : path) {
		if (c < 0x20 || c == 0x7f) {
			detail = "track path contains a control byte";
			return false;
		}
	}
	command = "load_file 1 ";
	command += path;
	command.push_back('\n');
	detail.clear();
	return true;
}

bool build_stop_command(std::string &command)
{
	command = "reset_core\n";
	return true;
}

bool build_transition_command(TransitionReason reason,
		const std::string &control_path, std::string &command,
		std::string &detail)
{
	if ((reason != TransitionReason::LoopLimitDisabled &&
	     reason != TransitionReason::LoopLimitTwoLoops) || control_path.empty() ||
	    control_path.size() > kMaximumTrackPathBytes) {
		detail = "invalid transition request";
		return false;
	}
	for (unsigned char byte : control_path) {
		if (byte < 0x20 || byte == 0x7f) {
			detail = "transition path contains a control byte";
			return false;
		}
	}
	command = "load_file 2 " + control_path + '\n';
	detail.clear();
	return true;
}

PosixRuntime::PosixRuntime(std::string status_path, std::string command_path)
	: status_path_(std::move(status_path)), command_path_(std::move(command_path))
{
	// If Main exits in the narrow window between FIFO open and write, report
	// EPIPE through issue_load instead of terminating the controller process.
	std::signal(SIGPIPE, SIG_IGN);
}

StatusReadResult PosixRuntime::read_status(PlaybackStatus &status,
		std::string &detail)
{
	int fd = open(status_path_.c_str(), O_RDONLY | O_CLOEXEC);
	if (fd < 0) {
		detail = std::strerror(errno);
		return errno == ENOENT ? StatusReadResult::Missing : StatusReadResult::IoError;
	}

	std::string text;
	char buffer[256];
	for (;;) {
		const ssize_t count = read(fd, buffer, sizeof(buffer));
		if (count > 0) {
			text.append(buffer, static_cast<std::size_t>(count));
			if (text.size() > kMaximumStatusBytes) {
				close(fd);
				detail = "status snapshot exceeds 512 bytes";
				return StatusReadResult::Malformed;
			}
			continue;
		}
		if (count == 0) break;
		if (errno == EINTR) continue;
		detail = std::strerror(errno);
		close(fd);
		return StatusReadResult::IoError;
	}
	if (close(fd) < 0) {
		detail = std::strerror(errno);
		return StatusReadResult::IoError;
	}
	return parse_status_text(text, status, detail);
}

bool PosixRuntime::main_available(std::string &detail)
{
	const int fd = open(command_path_.c_str(),
			O_WRONLY | O_NONBLOCK | O_CLOEXEC | O_APPEND);
	if (fd < 0) {
		detail = std::strerror(errno);
		return false;
	}
	if (close(fd) < 0) {
		detail = std::strerror(errno);
		return false;
	}
	detail.clear();
	return true;
}

bool PosixRuntime::issue_load(const std::string &path, std::string &detail)
{
	std::string command;
	if (!build_load_command(path, command, detail)) return false;
	return issue_command(command, detail);
}

bool PosixRuntime::issue_stop(std::string &detail)
{
	std::string command;
	build_stop_command(command);
	return issue_command(command, detail);
}

bool PosixRuntime::issue_transition(TransitionReason reason,
		std::string &detail)
{
	if (reason != TransitionReason::LoopLimitDisabled &&
	    reason != TransitionReason::LoopLimitTwoLoops) {
		detail = "unsupported transition reason";
		return false;
	}

	// Main already provides a generic indexed file-transfer endpoint. A tiny,
	// versioned record on reserved index 2 carries transport policy without
	// adding another command path or coupling the controller to a sound core.
	const unsigned char record[] = {
		'M', 'V', 2, loop_limit_policy_value(reason)
	};
	const int fd = open(kTransitionControlPath,
		O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0600);
	if (fd < 0) {
		detail = std::strerror(errno);
		return false;
	}
	std::size_t offset = 0;
	while (offset < sizeof(record)) {
		const ssize_t count = write(fd, record + offset,
			sizeof(record) - offset);
		if (count > 0) {
			offset += static_cast<std::size_t>(count);
		} else if (count < 0 && errno == EINTR) {
			continue;
		} else {
			detail = count < 0 ? std::strerror(errno) : "short control write";
			close(fd);
			return false;
		}
	}
	if (fsync(fd) < 0) {
		detail = std::strerror(errno);
		close(fd);
		return false;
	}
	if (close(fd) < 0) {
		detail = std::strerror(errno);
		return false;
	}

	std::string command;
	if (!build_transition_command(reason, kTransitionControlPath,
			command, detail))
		return false;
	return issue_command(command, detail);
}

bool PosixRuntime::issue_command(const std::string &command,
		std::string &detail)
{

	const int fd = open(command_path_.c_str(),
			O_WRONLY | O_NONBLOCK | O_CLOEXEC | O_APPEND);
	if (fd < 0) {
		detail = std::strerror(errno);
		return false;
	}

	const ssize_t count = write(fd, command.data(), command.size());
	const int write_errno = errno;
	if (close(fd) < 0 && count == static_cast<ssize_t>(command.size())) {
		detail = std::strerror(errno);
		return false;
	}
	if (count != static_cast<ssize_t>(command.size())) {
		detail = count < 0 ? std::strerror(write_errno) : "short command write";
		return false;
	}
	detail.clear();
	return true;
}

std::uint64_t PosixRuntime::monotonic_ms()
{
	const auto now = std::chrono::steady_clock::now().time_since_epoch();
	return static_cast<std::uint64_t>(
			std::chrono::duration_cast<std::chrono::milliseconds>(now).count());
}

void PosixRuntime::sleep_ms(std::uint32_t milliseconds)
{
	struct timespec request = {
		static_cast<time_t>(milliseconds / 1000),
		static_cast<long>((milliseconds % 1000) * 1000000UL)
	};
	while (nanosleep(&request, &request) < 0 && errno == EINTR) {}
}

RunResult run(Runtime &runtime, const ControllerConfig &config,
		const std::string &track_a, const std::string &track_b,
		std::ostream &log)
{
	std::string command;
	std::string detail;
	if (!build_load_command(track_a, command, detail) ||
	    !build_load_command(track_b, command, detail)) {
		log << "INVALID_TRACK_PATH: " << detail << '\n';
		return RunResult::InvalidTrackPath;
	}

	Monitor monitor(runtime, config, log);
	PlaybackStatus status;
	RunResult result = monitor.read(status);
	if (result != RunResult::Pass) return result;
	const std::uint32_t baseline_session = status.session;

	if (!runtime.issue_load(track_a, detail)) {
		log << "COMMAND_WRITE_FAILED: Track A: " << detail << '\n';
		return RunResult::CommandWriteFailed;
	}
	log << "Track A load requested\n";

	PlaybackStatus last_logged;
	bool last_logged_valid = false;
	std::uint32_t track_a_session = 0;
	bool have_track_a_session = false;
	bool track_a_playing = false;
	std::uint64_t deadline = runtime.monotonic_ms() + config.track_start_timeout_ms;

	while (!track_a_playing) {
		result = monitor.read(status);
		if (result != RunResult::Pass) return result;
		if (!have_track_a_session && status.session != baseline_session) {
			track_a_session = status.session;
			have_track_a_session = true;
		}
		if (have_track_a_session) {
			if (status.session != track_a_session) {
				log << "MANUAL_OR_EXTERNAL_SESSION_CHANGE\n";
				return RunResult::ManualOrExternalSessionChange;
			}
			log_status(log, status, last_logged, last_logged_valid);
			if (status.state == PlaybackState::Playing) track_a_playing = true;
			else if (status.state == PlaybackState::Ended) {
				log << "TRACK_A_NEVER_STARTS: ENDED before PLAYING\n";
				return RunResult::TrackANeverStarts;
			}
		}
		if (!track_a_playing && timed_out(runtime, deadline)) {
			log << "TRACK_A_NEVER_STARTS\n";
			return RunResult::TrackANeverStarts;
		}
		if (!track_a_playing) monitor.sleep();
	}

	deadline = runtime.monotonic_ms() + config.track_end_timeout_ms;
	bool track_a_ended = false;
	while (!track_a_ended) {
		result = monitor.read(status);
		if (result != RunResult::Pass) return result;
		if (status.session != track_a_session) {
			log << "MANUAL_OR_EXTERNAL_SESSION_CHANGE\n";
			return RunResult::ManualOrExternalSessionChange;
		}
		log_status(log, status, last_logged, last_logged_valid);
		track_a_ended = status.state == PlaybackState::Ended;
		if (!track_a_ended && timed_out(runtime, deadline)) {
			log << "TRACK_A_NEVER_ENDS\n";
			return RunResult::TrackANeverEnds;
		}
		if (!track_a_ended) monitor.sleep();
	}

	// ENDED is consumed exactly once by advancing to the next state before
	// polling again. Repeated snapshots for track_a_session can never issue B.
	if (!runtime.issue_load(track_b, detail)) {
		log << "COMMAND_WRITE_FAILED: Track B: " << detail << '\n';
		return RunResult::CommandWriteFailed;
	}
	log << "Track B load requested\n";

	std::uint32_t track_b_session = 0;
	bool have_track_b_session = false;
	deadline = runtime.monotonic_ms() + config.next_session_timeout_ms;
	while (!have_track_b_session) {
		result = monitor.read(status);
		if (result != RunResult::Pass) return result;
		if (status.session != track_a_session) {
			track_b_session = status.session;
			have_track_b_session = true;
			log_status(log, status, last_logged, last_logged_valid);
		}
		if (!have_track_b_session && timed_out(runtime, deadline)) {
			log << "TRACK_B_SESSION_TIMEOUT\n";
			return RunResult::TrackBSessionTimeout;
		}
		if (!have_track_b_session) monitor.sleep();
	}

	deadline = runtime.monotonic_ms() + config.track_b_playing_timeout_ms;
	while (status.state != PlaybackState::Playing) {
		if (status.state == PlaybackState::Ended) {
			log << "TRACK_B_NEVER_PLAYING: ENDED before PLAYING\n";
			return RunResult::TrackBNeverPlaying;
		}
		monitor.sleep();
		result = monitor.read(status);
		if (result != RunResult::Pass) return result;
		if (status.session != track_b_session) {
			log << "MANUAL_OR_EXTERNAL_SESSION_CHANGE\n";
			return RunResult::ManualOrExternalSessionChange;
		}
		log_status(log, status, last_logged, last_logged_valid);
		if (status.state != PlaybackState::Playing &&
		    timed_out(runtime, deadline)) {
			log << "TRACK_B_NEVER_PLAYING\n";
			return RunResult::TrackBNeverPlaying;
		}
	}

	log << "AUTOPLAY2 PASS\n";
	return RunResult::Pass;
}

} // namespace megavgm_autoplay2
