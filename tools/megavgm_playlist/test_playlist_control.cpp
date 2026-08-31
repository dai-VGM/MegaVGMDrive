#include "playlist_control.h"

#include <cassert>
#include <cstdlib>
#include <fcntl.h>
#include <fstream>
#include <iterator>
#include <string>
#include <sys/stat.h>
#include <unistd.h>

using namespace megavgm_playlist;

namespace {

std::string read_text(const std::string &path)
{
	std::ifstream stream(path);
	assert(stream.good());
	return std::string(std::istreambuf_iterator<char>(stream),
		std::istreambuf_iterator<char>());
}

} // namespace

int main()
{
	char directory_template[] = "/tmp/megavgm-control-test.XXXXXX";
	char *directory_name = mkdtemp(directory_template);
	assert(directory_name);
	const std::string directory(directory_name);
	const std::string command_path = directory + "/playlist.cmd";
	const std::string status_path = directory + "/playlist.status";

	{
		PosixControllerIo controller(command_path, status_path);
		std::string detail;
		assert(controller.start(detail));
		struct stat attributes = {};
		assert(lstat(command_path.c_str(), &attributes) == 0);
		assert(S_ISFIFO(attributes.st_mode));

		assert(send_navigation_command(command_path,
			ControlCommandType::Next, detail));
		ControlCommand command;
		assert(controller.poll_command(command, detail) ==
			ControlPollResult::Command);
		assert(command.type == ControlCommandType::Next);

		assert(send_navigation_command(command_path,
			ControlCommandType::Previous, detail));
		assert(controller.poll_command(command, detail) ==
			ControlPollResult::Command);
		assert(command.type == ControlCommandType::Previous);

		const std::string play_path =
			"/media/fat/MegaVGMDrive/01 Arcade/[日本語] Stage.vgm";
		assert(send_play_command(command_path, play_path, detail));
		assert(controller.poll_command(command, detail) ==
			ControlPollResult::Command);
		assert(command.type == ControlCommandType::Play);
		assert(command.path == play_path);

		const int writer = open(command_path.c_str(),
			O_WRONLY | O_NONBLOCK | O_CLOEXEC);
		assert(writer >= 0);
		const char invalid[] = "next\n";
		assert(write(writer, invalid, sizeof(invalid) - 1) ==
			static_cast<ssize_t>(sizeof(invalid) - 1));
		assert(close(writer) == 0);
		assert(controller.poll_command(command, detail) ==
			ControlPollResult::Invalid);
		assert(!detail.empty());

		// The controller can discard a rapid command burst during its owned
		// load window, matching the Phase 1F serialization policy.
		assert(send_navigation_command(command_path,
			ControlCommandType::Next, detail));
		assert(send_navigation_command(command_path,
			ControlCommandType::Next, detail));
		assert(controller.poll_command(command, detail) ==
			ControlPollResult::Command);
		assert(controller.discard_commands(detail));
		assert(controller.poll_command(command, detail) ==
			ControlPollResult::None);

		ControllerSnapshot snapshot;
		snapshot.state = "PLAYING";
		snapshot.index = 4;
		snapshot.count = 10;
		snapshot.path = "/media/fat/Music/[日本語] Stage.vgm";
		snapshot.session = 27;
		snapshot.loop_count = 1;
		assert(controller.publish(snapshot, detail));
		assert(read_text(status_path) ==
			"state=PLAYING\nindex=4\ncount=10\n"
			"path=/media/fat/Music/[日本語] Stage.vgm\n"
			"session=27\nloop_count=1\n");
		const std::string temporary = status_path + ".tmp." +
			std::to_string(static_cast<unsigned long>(getpid()));
		assert(access(temporary.c_str(), F_OK) != 0);
	}
	assert(access(command_path.c_str(), F_OK) != 0);

	// Never replace a non-FIFO object at the public control path.
	const int regular_fd = open(command_path.c_str(),
		O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0600);
	assert(regular_fd >= 0);
	assert(close(regular_fd) == 0);
	{
		PosixControllerIo controller(command_path, status_path);
		std::string detail;
		assert(!controller.start(detail));
		assert(!detail.empty());
	}
	struct stat attributes = {};
	assert(lstat(command_path.c_str(), &attributes) == 0);
	assert(S_ISREG(attributes.st_mode));

	assert(unlink(command_path.c_str()) == 0);
	assert(unlink(status_path.c_str()) == 0);
	assert(rmdir(directory.c_str()) == 0);
	return 0;
}
