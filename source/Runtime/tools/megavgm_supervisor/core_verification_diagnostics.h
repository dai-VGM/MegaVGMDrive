#pragma once

#include "../megavgm_autoplay2/autoplay2.h"

#include <sstream>
#include <string>

namespace megavgm_supervisor {

inline const char *playback_state_name(
	megavgm_autoplay2::PlaybackState state)
{
	using megavgm_autoplay2::PlaybackState;
	switch (state) {
	case PlaybackState::Idle: return "IDLE";
	case PlaybackState::Loading: return "LOADING";
	case PlaybackState::Playing: return "PLAYING";
	case PlaybackState::Ended: return "ENDED";
	case PlaybackState::Fatal: return "FATAL";
	}
	return "UNKNOWN";
}

inline bool accepted_megavgm_status(
	const megavgm_autoplay2::PlaybackStatus &status, bool phase2a,
	std::string &rejection)
{
	if (!phase2a) {
		rejection.clear();
		return true;
	}

	std::ostringstream reasons;
	const auto append = [&](const std::string &reason) {
		if (reasons.tellp() > 0) reasons << ',';
		reasons << reason;
	};
	if (status.version != 2) append("version_not_2");
	if (status.session != 0) append("session_not_0");
	if (status.state != megavgm_autoplay2::PlaybackState::Idle)
		append("state_not_IDLE");
	if (status.error != 0) append("error_nonzero");
	rejection = reasons.str();
	return rejection.empty();
}

} // namespace megavgm_supervisor
