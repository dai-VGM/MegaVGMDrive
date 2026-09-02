#include "playlist_control.h"

#include <csignal>
#include <iostream>

int main(int argc, char **argv)
{
	std::signal(SIGPIPE, SIG_IGN);
	if (argc < 2 || argc > 3) {
		std::cerr << "Usage: megavgm_ctl next|prev|play <path>|playlist <snapshot>\n";
		return 2;
	}

	const std::string argument(argv[1]);
	std::string detail;
	bool sent = false;
	if (argc == 2 && argument == "next")
		sent = megavgm_playlist::send_navigation_command(
			"/tmp/megavgm_playlist.cmd",
			megavgm_playlist::ControlCommandType::Next, detail);
	else if (argc == 2 && argument == "prev")
		sent = megavgm_playlist::send_navigation_command(
			"/tmp/megavgm_playlist.cmd",
			megavgm_playlist::ControlCommandType::Previous, detail);
	else if (argc == 3 && argument == "play")
		sent = megavgm_playlist::send_play_command(
			"/tmp/megavgm_playlist.cmd", argv[2], detail);
	else if (argc == 3 && argument == "playlist")
		sent = megavgm_playlist::send_playlist_command(
			"/tmp/megavgm_playlist.cmd", argv[2], detail);
	else {
		std::cerr << "Usage: megavgm_ctl next|prev|play <path>|playlist <snapshot>\n";
		return 2;
	}
	if (!sent) {
		std::cerr << "CONTROL_WRITE_FAILED: " << detail << '\n';
		return 1;
	}
	return 0;
}
