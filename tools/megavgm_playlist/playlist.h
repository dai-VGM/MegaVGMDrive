#ifndef MEGAVGM_PLAYLIST_H
#define MEGAVGM_PLAYLIST_H

#include "../megavgm_autoplay2/autoplay2.h"
#include "playlist_control.h"

#include <cstdint>
#include <iosfwd>
#include <string>
#include <vector>

namespace megavgm_playlist {

struct Track {
	std::string name;
	std::string path;
};

enum class DiscoveryResult {
	Ok,
	OpenFailed,
	ReadFailed,
	Empty
};

enum class PlaylistResult {
	Complete,
	Suspended,
	StatusFileMissing,
	MalformedStatus,
	UnsupportedVersion,
	StatusIoError,
	ActiveMainUnavailable,
	InvalidTrackPath,
	CommandWriteFailed,
	ControlIoError,
	TrackSessionTimeout,
	TrackNeverPlaying,
	TrackEndTimeout
};

struct PlaylistConfig {
	std::uint16_t loop_limit = 2;
	std::size_t start_index = 0;
	std::uint64_t session_timeout_ms = 60000;
	std::uint64_t playing_timeout_ms = 60000;
	// Zero intentionally disables normal playback timeout.
	std::uint64_t end_timeout_ms = 0;
	std::uint32_t poll_interval_ms = 100;
	std::uint32_t main_probe_interval_ms = 1000;
	std::string approved_root = "/media/fat/MegaVGMDrive";
	RandomSource *random_source = nullptr;
};

DiscoveryResult discover_directory(const std::string &directory,
		std::vector<Track> &tracks, std::string &detail);

PlaylistResult run(megavgm_autoplay2::Runtime &runtime,
		const PlaylistConfig &config, const std::vector<Track> &tracks,
		std::ostream &log, ControllerIo *controller = nullptr);

const char *discovery_result_name(DiscoveryResult result);
const char *playlist_result_name(PlaylistResult result);

} // namespace megavgm_playlist

#endif
