#ifndef MEGAVGM_PLAYLIST_CONTROL_H
#define MEGAVGM_PLAYLIST_CONTROL_H

#include <cstddef>
#include <cstdint>
#include <string>

namespace megavgm_playlist {

enum class ControlCommandType {
	Next,
	Previous,
	Play
};

struct ControlCommand {
	ControlCommandType type = ControlCommandType::Next;
	std::string path;
};

enum class ControlPollResult {
	None,
	Command,
	Invalid,
	IoError
};

struct ControllerSnapshot {
	std::string state;
	std::size_t index = 0; // One-based while a track is owned.
	std::size_t count = 0;
	std::string path;
	std::uint32_t session = 0;
	std::uint16_t loop_count = 0;
};

class ControllerIo {
public:
	virtual ~ControllerIo() = default;
	virtual ControlPollResult poll_command(ControlCommand &command,
			std::string &detail) = 0;
	virtual bool discard_commands(std::string &detail) = 0;
	virtual bool publish(const ControllerSnapshot &snapshot,
			std::string &detail) = 0;
};

class PosixControllerIo final : public ControllerIo {
public:
	PosixControllerIo(
			std::string command_path = "/tmp/megavgm_playlist.cmd",
			std::string status_path = "/tmp/megavgm_playlist.status");
	~PosixControllerIo() override;

	bool start(std::string &detail);
	ControlPollResult poll_command(ControlCommand &command,
			std::string &detail) override;
	bool discard_commands(std::string &detail) override;
	bool publish(const ControllerSnapshot &snapshot,
			std::string &detail) override;

private:
	ControlPollResult parse_buffered_command(ControlCommand &command,
			std::string &detail);
	bool drain_fd(std::string &detail);

	std::string command_path_;
	std::string status_path_;
	std::string input_buffer_;
	std::string last_status_content_;
	int command_fd_ = -1;
	bool command_owned_ = false;
	std::uint64_t command_device_ = 0;
	std::uint64_t command_inode_ = 0;
};

bool send_navigation_command(const std::string &command_path,
		ControlCommandType command, std::string &detail);
bool send_play_command(const std::string &command_path,
		const std::string &path, std::string &detail);
const char *control_command_name(ControlCommandType command);

} // namespace megavgm_playlist

#endif
