#pragma once
#include "supervisor.h"
#include "../megavgm_profile/switch.h"

namespace megavgm_supervisor {
// Pure display projection. READY remains a load grant until a generation-bound
// Main witness AND a fresh-domain FPGA record prove actual playback.
inline std::string observed_transport_state(const TransportObservation &previous,
    const megavgm_profile::Reply &reply, bool fading,
    const megavgm_autoplay2::PlaybackStatus *verified_playback)
{
    std::string state = reply.state;
    if (state == "PARKED" && fading) state = "FADING";
    if (state == "READY") {
        using megavgm_autoplay2::PlaybackState;
        if (verified_playback && verified_playback->version == 2 &&
            verified_playback->session == static_cast<std::uint32_t>(reply.baseline + 1)) {
            const auto &s = *verified_playback;
            if (s.error || s.state == PlaybackState::Fatal) state = "FAILED";
            else if (s.state == PlaybackState::Playing) state = "PLAYING";
            else if (s.state == PlaybackState::Ended) state = "ENDED";
        }
        if (previous.generation == reply.generation &&
            (previous.state == "PLAYING" || previous.state == "ENDED" || previous.state == "FAILED") &&
            state == "READY") state = previous.state;
    }
    return state;
}
}
