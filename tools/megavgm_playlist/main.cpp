#include "playlist.h"

#include <iostream>

int main(int argc, char **argv)
{
	if (argc != 2) {
		std::cerr << "Usage: megavgm_playlist <directory>\n";
		return 2;
	}

	std::vector<megavgm_playlist::Track> tracks;
	std::string detail;
	const megavgm_playlist::DiscoveryResult discovery =
		megavgm_playlist::discover_directory(argv[1], tracks, detail);
	if (discovery != megavgm_playlist::DiscoveryResult::Ok) {
		std::cerr << megavgm_playlist::discovery_result_name(discovery);
		if (!detail.empty()) std::cerr << ": " << detail;
		std::cerr << '\n';
		return 2;
	}

	megavgm_autoplay2::PosixRuntime runtime;
	megavgm_playlist::PlaylistConfig config;
	const megavgm_playlist::PlaylistResult result =
		megavgm_playlist::run(runtime, config, tracks, std::cout);
	if (result == megavgm_playlist::PlaylistResult::Complete) return 0;
	if (result == megavgm_playlist::PlaylistResult::Suspended) return 3;
	std::cerr << "PLAYLIST FAILED: "
	          << megavgm_playlist::playlist_result_name(result) << '\n';
	return 1;
}
