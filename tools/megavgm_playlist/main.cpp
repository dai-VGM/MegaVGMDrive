#include "playlist.h"

#include <iostream>

namespace {

bool parse_loop_limit(const char *text, std::uint16_t &value)
{
	if (!text || !*text) return false;
	std::uint32_t parsed = 0;
	for (const unsigned char *p =
			reinterpret_cast<const unsigned char *>(text); *p; ++p) {
		if (*p < '0' || *p > '9') return false;
		const std::uint32_t digit = static_cast<std::uint32_t>(*p - '0');
		if (parsed > (0xffffu - digit) / 10u) return false;
		parsed = parsed * 10u + digit;
	}
	value = static_cast<std::uint16_t>(parsed);
	return true;
}

void usage()
{
	std::cerr << "Usage: megavgm_playlist [--loops N] <directory>\n";
}

} // namespace

int main(int argc, char **argv)
{
	std::uint16_t loop_limit = 2;
	const char *directory = nullptr;
	if (argc == 2) {
		directory = argv[1];
	} else if (argc == 4 && std::string(argv[1]) == "--loops" &&
		parse_loop_limit(argv[2], loop_limit)) {
		directory = argv[3];
	} else {
		usage();
		return 2;
	}

	std::vector<megavgm_playlist::Track> tracks;
	std::string detail;
	const megavgm_playlist::DiscoveryResult discovery =
		megavgm_playlist::discover_directory(directory, tracks, detail);
	if (discovery != megavgm_playlist::DiscoveryResult::Ok) {
		std::cerr << megavgm_playlist::discovery_result_name(discovery);
		if (!detail.empty()) std::cerr << ": " << detail;
		std::cerr << '\n';
		return 2;
	}

	megavgm_autoplay2::PosixRuntime runtime;
	megavgm_playlist::PosixControllerIo controller;
	if (!controller.start(detail)) {
		std::cerr << "CONTROL_SETUP_FAILED: " << detail << '\n';
		return 1;
	}
	megavgm_playlist::PlaylistConfig config;
	config.loop_limit = loop_limit;
	const megavgm_playlist::PlaylistResult result =
		megavgm_playlist::run(runtime, config, tracks, std::cout, &controller);
	if (result == megavgm_playlist::PlaylistResult::Complete) return 0;
	if (result == megavgm_playlist::PlaylistResult::Suspended) return 3;
	std::cerr << "PLAYLIST FAILED: "
	          << megavgm_playlist::playlist_result_name(result) << '\n';
	return 1;
}
