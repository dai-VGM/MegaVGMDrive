#ifndef MEGAVGM_PLAYLIST_CONTROL_H
#define MEGAVGM_PLAYLIST_CONTROL_H

#include "playback_mode.h"

#include <cstddef>
#include <cstdint>
#include <deque>
#include <string>
#include <vector>

namespace megavgm_playlist {

enum class ControlCommandType {
	Next,
	Previous,
	Stop,
	Play,
	Playlist,
	Repeat,
	Shuffle
};

struct ControlCommand {
	ControlCommandType type = ControlCommandType::Next;
	std::string path;
	RepeatMode repeat = RepeatMode::Off;
	bool shuffle = false;
};

struct PlaylistSnapshot {
	std::string name;
	std::vector<std::string> paths;
	std::size_t start_index = 0;
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
	std::string context = "DIRECTORY";
	std::string playlist;
	RepeatMode repeat = RepeatMode::Off;
	bool shuffle = false;
	std::string traversal = "ORDERED";
};

class ControllerIo {
public:
	virtual ~ControllerIo() = default;
	virtual ControlPollResult poll_command(ControlCommand &command,
			std::string &detail) = 0;
	virtual bool discard_commands(std::string &detail) = 0;
	virtual bool publish(const ControllerSnapshot &snapshot,
			std::string &detail) = 0;
	virtual bool load_preferences(PlaybackPreferences &preferences,
			std::string &detail) = 0;
	virtual bool save_preferences(const PlaybackPreferences &preferences,
			std::string &detail) = 0;
};

class PosixControllerIo final : public ControllerIo {
public:
	PosixControllerIo(
			std::string command_path = "/tmp/megavgm_playlist.cmd",
			std::string status_path = "/tmp/megavgm_playlist.status",
			std::string preferences_path =
				"/media/fat/Scripts/.config/megavgm/playback_modes.conf");
	~PosixControllerIo() override;

	bool start(std::string &detail);
	ControlPollResult poll_command(ControlCommand &command,
			std::string &detail) override;
	bool discard_commands(std::string &detail) override;
	bool publish(const ControllerSnapshot &snapshot,
			std::string &detail) override;
	bool load_preferences(PlaybackPreferences &preferences,
			std::string &detail) override;
	bool save_preferences(const PlaybackPreferences &preferences,
			std::string &detail) override;

private:
	ControlPollResult parse_buffered_command(ControlCommand &command,
			std::string &detail);
	bool drain_fd(std::string &detail);

	std::string command_path_;
	std::string status_path_;
	std::string preferences_path_;
	std::string input_buffer_;
	std::deque<ControlCommand> retained_commands_;
	std::string last_status_content_;
	int command_fd_ = -1;
	bool command_owned_ = false;
	std::uint64_t command_device_ = 0;
	std::uint64_t command_inode_ = 0;
};

bool send_navigation_command(const std::string &command_path,
		ControlCommandType command, std::string &detail);
bool send_stop_command(const std::string &command_path, std::string &detail);
bool send_play_command(const std::string &command_path,
		const std::string &path, std::string &detail);
bool send_playlist_command(const std::string &command_path,
		const std::string &snapshot_path, std::string &detail);
bool send_repeat_command(const std::string &command_path, RepeatMode mode,
		std::string &detail);
bool send_shuffle_command(const std::string &command_path, bool enabled,
		std::string &detail);
bool load_playlist_snapshot(const std::string &snapshot_path,
		const std::string &approved_root, PlaylistSnapshot &snapshot,
		std::string &detail, bool consume = false);
const char *control_command_name(ControlCommandType command);

} // namespace megavgm_playlist

#endif
