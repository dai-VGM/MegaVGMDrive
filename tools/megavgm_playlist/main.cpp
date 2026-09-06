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
	std::cerr << "Usage: megavgm_playlist [--loops N] [--start-file PATH | "
	          << "--playlist-snapshot PATH] <directory>\n";
}

} // namespace

int main(int argc, char **argv)
{
	std::uint16_t loop_limit = 2;
	const char *directory = nullptr;
	std::string start_file;
	std::string snapshot_path;
#ifdef MEGAVGM_PHASE2A
	std::string profile_channel;
#endif
	for (int argument = 1; argument < argc; ++argument) {
		const std::string option(argv[argument]);
		if (false) {}
#ifdef MEGAVGM_PHASE2A
		else if (option == "--phase2a-channel" && argument + 1 < argc) profile_channel = argv[++argument];
#endif
		else if (option == "--loops" && argument + 1 < argc &&
		    parse_loop_limit(argv[argument + 1], loop_limit)) {
			++argument;
		} else if (option == "--start-file" && argument + 1 < argc) {
			start_file = argv[++argument];
		} else if (option == "--playlist-snapshot" && argument + 1 < argc) {
			snapshot_path = argv[++argument];
		} else if (!directory && !option.empty() && option.front() != '-') {
			directory = argv[argument];
		} else {
			usage();
			return 2;
		}
	}
	if (!directory || (!start_file.empty() && !snapshot_path.empty())) {
		usage();
		return 2;
	}

	std::vector<megavgm_playlist::Track> tracks;
	std::string detail;
	megavgm_playlist::PlaylistConfig config;
	config.loop_limit = loop_limit;
#ifdef MEGAVGM_PHASE2A
	megavgm_profile::FileClient profile_client(profile_channel);
	if (!profile_channel.empty()) config.profile_client = &profile_client;
#endif
	if (!snapshot_path.empty()) {
		megavgm_playlist::PlaylistSnapshot snapshot;
		if (!megavgm_playlist::load_playlist_snapshot(snapshot_path,
				config.approved_root, snapshot, detail, true)) {
			std::cerr << "INVALID_PLAYLIST_SNAPSHOT";
			if (!detail.empty()) std::cerr << ": " << detail;
			std::cerr << '\n';
			return 2;
		}
		for (const std::string &path : snapshot.paths) {
			const std::size_t separator = path.find_last_of('/');
			tracks.push_back({separator == std::string::npos ? path :
				path.substr(separator + 1), path});
		}
		config.start_index = snapshot.start_index;
		config.initial_playlist_name = snapshot.name;
	} else {
		const megavgm_playlist::DiscoveryResult discovery =
			megavgm_playlist::discover_directory(directory, tracks, detail);
		if (discovery != megavgm_playlist::DiscoveryResult::Ok) {
			std::cerr << megavgm_playlist::discovery_result_name(discovery);
			if (!detail.empty()) std::cerr << ": " << detail;
			std::cerr << '\n';
			return 2;
		}
	}

	megavgm_autoplay2::PosixRuntime runtime;
	megavgm_playlist::PosixControllerIo controller;
	if (!controller.start(detail)) {
		std::cerr << "CONTROL_SETUP_FAILED: " << detail << '\n';
		return 1;
	}
	if (!start_file.empty()) {
		bool found = false;
		for (std::size_t index = 0; index < tracks.size(); ++index) {
			if (tracks[index].path == start_file) {
				config.start_index = index;
				found = true;
				break;
			}
		}
		if (!found) {
			std::cerr << "INVALID_START_FILE: selected file is not in directory\n";
			return 2;
		}
	}
	const megavgm_playlist::PlaylistResult result =
		megavgm_playlist::run(runtime, config, tracks, std::cout, &controller);
	if (result == megavgm_playlist::PlaylistResult::Complete) return 0;
	if (result == megavgm_playlist::PlaylistResult::Suspended) return 3;
	std::cerr << "PLAYLIST FAILED: "
	          << megavgm_playlist::playlist_result_name(result) << '\n';
	return 1;
}
