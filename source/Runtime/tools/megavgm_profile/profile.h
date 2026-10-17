#pragma once
#include <cstdint>
#include <array>
#include <string>
#include <vector>

namespace megavgm_profile {
// Keep the established A/B/C and failure wire values stable. Profile D is
// appended because request/reply records cross the controller/Supervisor
// process boundary during a switch.
enum class Profile {
    A = 0,
    B = 1,
    C = 2,
    Unsupported = 3,
    Ambiguous = 4,
    Error = 5,
    D = 6,
    E = 7,
    F = 8,
};
const char *name(Profile profile);
const char *rbf(Profile profile);
const char *status_name(Profile profile);
struct SidMetadata {
    std::uint16_t format_version = 0;
    std::string model;
    std::string timing;
    std::uint32_t subtune = 0;
    bool capture_limited = false;
    std::string source_sha256;
};
struct PlaybackTiming {
    // Duration of the first stream traversal. Values are populated only from
    // validated VGM/MVGMSID metadata; playback never depends on them.
    bool duration_valid = false;
    std::uint64_t duration_ms = 0;
    bool loop_valid = false;
    std::uint64_t loop_duration_ms = 0;
    std::string source;
};
struct Classification {
    Profile profile = Profile::Error;
    std::string detail;
    std::uint64_t commands = 0;
    // Read-only display evidence; never used to select or accept a profile.
    std::string sound_chips = {};
    SidMetadata sid = {};
    PlaybackTiming timing = {};
    // Host preparation only; never FPGA status or playback timing.
    bool resource_capacity_exceeded = false;
    std::array<std::uint64_t, 16> resource_page_mask{}; // audited pages, no ROM bytes
    unsigned required_pages = 0; // lower bound on rejection, exact on success
    std::uint32_t resource_fault_pc = 0;
    unsigned resource_fault_traversal = 0;

};

struct Sn76489ClockNormalization {
    bool applied = false;
    std::string detail;
};

Classification classify_bytes(const std::vector<unsigned char> &bytes);
Classification classify_file(const std::string &path,
    const std::string &root = "/media/fat/MegaVGMDrive");
// Preparation-only normalization. The ordinary classifier remains strict:
// callers must explicitly request this transformation on an unpublished copy.
Sn76489ClockNormalization normalize_sn76489_clock_bytes(
    std::vector<unsigned char> &bytes);
// Preflight-only admission for raw PSID/RSID. This does not classify the raw
// bytes as playable PROFILE_C content; the controller must prepare and then
// pass the resulting strict MVGMSID artifact through classify_file().
Classification inspect_raw_sid_for_prepare(const std::string &path,
    const std::string &root = "/media/fat/MegaVGMDrive");
}
