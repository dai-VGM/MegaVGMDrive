#include "playlist_control.h"

#include <csignal>
#include <iostream>

int main(int argc, char **argv)
{
	std::signal(SIGPIPE, SIG_IGN);
	if (argc != 2) {
		std::cerr << "Usage: megavgm_ctl next|prev\n";
		return 2;
	}

	megavgm_playlist::NavigationCommand command;
	const std::string argument(argv[1]);
	if (argument == "next") command = megavgm_playlist::NavigationCommand::Next;
	else if (argument == "prev")
		command = megavgm_playlist::NavigationCommand::Previous;
	else {
		std::cerr << "Usage: megavgm_ctl next|prev\n";
		return 2;
	}

	std::string detail;
	if (!megavgm_playlist::send_navigation_command(
			"/tmp/megavgm_playlist.cmd", command, detail)) {
		std::cerr << "CONTROL_WRITE_FAILED: " << detail << '\n';
		return 1;
	}
	return 0;
}
