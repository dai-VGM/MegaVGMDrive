#ifndef MEGAVGM_AUTOPLAY2_H
#define MEGAVGM_AUTOPLAY2_H

#include <cstdint>
#include <iosfwd>
#include <string>

namespace megavgm_autoplay2 {

enum class PlaybackState {
	Idle,
	Loading,
	Playing,
	Ended,
	Fatal
};

// Transport transition reasons are deliberately independent of sound family.
// The FPGA owns the audible ramp; the controller only requests policy.
enum class TransitionReason {
	LoopLimit
};

struct PlaybackStatus {
	std::uint32_t version = 0;
	std::uint32_t session = 0;
	PlaybackState state = PlaybackState::Idle;
	std::uint8_t error = 0;
	bool loop_valid = false;
	std::uint16_t loop_count = 0;
};

enum class StatusReadResult {
	Ok,
	Missing,
	Malformed,
	UnsupportedVersion,
	IoError
};

enum class RunResult {
	Pass,
	StatusFileMissing,
	MalformedStatus,
	UnsupportedVersion,
	StatusIoError,
	FatalStatus,
	NonzeroError,
	ActiveMainUnavailable,
	InvalidTrackPath,
	CommandWriteFailed,
	TrackANeverStarts,
	TrackANeverEnds,
	TrackBSessionTimeout,
	TrackBNeverPlaying,
	ManualOrExternalSessionChange
};

struct ControllerConfig {
	std::uint64_t track_start_timeout_ms = 60000;
	std::uint64_t track_end_timeout_ms = 30 * 60 * 1000;
	std::uint64_t next_session_timeout_ms = 60000;
	std::uint64_t track_b_playing_timeout_ms = 60000;
	std::uint32_t poll_interval_ms = 100;
	std::uint32_t main_probe_interval_ms = 1000;
};

class Runtime {
public:
	virtual ~Runtime() = default;
	virtual StatusReadResult read_status(PlaybackStatus &status,
			std::string &detail) = 0;
	virtual bool main_available(std::string &detail) = 0;
	virtual bool issue_load(const std::string &path, std::string &detail) = 0;
	virtual bool issue_stop(std::string &detail) = 0;
	virtual bool issue_transition(TransitionReason reason,
			std::string &detail) = 0;
	virtual std::uint64_t monotonic_ms() = 0;
	virtual void sleep_ms(std::uint32_t milliseconds) = 0;
};

class PosixRuntime final : public Runtime {
public:
	PosixRuntime(std::string status_path = "/tmp/MegaVGMPlayer.status",
			std::string command_path = "/dev/MiSTer_cmd");

	StatusReadResult read_status(PlaybackStatus &status,
			std::string &detail) override;
	bool main_available(std::string &detail) override;
	bool issue_load(const std::string &path, std::string &detail) override;
	bool issue_stop(std::string &detail) override;
	bool issue_transition(TransitionReason reason,
			std::string &detail) override;
	std::uint64_t monotonic_ms() override;
	void sleep_ms(std::uint32_t milliseconds) override;

private:
	std::string status_path_;
	std::string command_path_;
	bool issue_command(const std::string &command, std::string &detail);
};

StatusReadResult parse_status_text(const std::string &text,
		PlaybackStatus &status, std::string &detail);
bool build_load_command(const std::string &path, std::string &command,
		std::string &detail);
bool build_stop_command(std::string &command);
bool build_transition_command(TransitionReason reason,
		const std::string &control_path, std::string &command,
		std::string &detail);
const char *state_name(PlaybackState state);
const char *run_result_name(RunResult result);

RunResult run(Runtime &runtime, const ControllerConfig &config,
		const std::string &track_a, const std::string &track_b,
		std::ostream &log);

} // namespace megavgm_autoplay2

#endif
