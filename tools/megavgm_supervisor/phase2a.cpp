#include "phase2a.h"
#include "../megavgm_playlist/playlist.h"
#include <cerrno>
#include <cstring>
#include <fcntl.h>
#include <iostream>
#include <sys/stat.h>
#include <unistd.h>

namespace megavgm_supervisor {
using megavgm_profile::Profile;
OperationResult phase2a_preflight(Paths &paths, const std::string &directory,
    const std::string &start_file, const std::string &snapshot_path) {
    std::string selected = start_file, detail;
    if (!snapshot_path.empty()) {
        megavgm_playlist::PlaylistSnapshot snapshot;
        if (!megavgm_playlist::load_playlist_snapshot(snapshot_path, "/media/fat/MegaVGMDrive", snapshot, detail, false))
            return OperationResult::failure("cold snapshot: " + detail);
        selected = snapshot.paths[snapshot.start_index];
    } else if (selected.empty()) {
        std::vector<megavgm_playlist::Track> tracks;
        if (megavgm_playlist::discover_directory(directory, tracks, detail) != megavgm_playlist::DiscoveryResult::Ok)
            return OperationResult::failure("cold directory: " + detail);
        selected = tracks.front().path;
    }
    const auto classification = megavgm_profile::classify_file(selected);
    std::cout << "PHASE2A_COLD_CLASSIFY path=" << selected << " result=" << megavgm_profile::name(classification.profile)
              << " detail=" << classification.detail << std::endl;
    if (classification.profile != Profile::A && classification.profile != Profile::B)
        return OperationResult::failure("classification: " + classification.detail);
    for (const auto p : {Profile::A, Profile::B}) {
        struct stat s = {};
        if (lstat(megavgm_profile::rbf(p), &s) || !S_ISREG(s.st_mode) || s.st_size <= 0)
            return OperationResult::failure("both canonical A/B RBFs must exist before stock is stopped");
    }
    paths.rbf = megavgm_profile::rbf(classification.profile);
    paths.rbf_profile = classification.profile == Profile::A ? "PROFILE_A" : "PROFILE_B";
    if (!megavgm_profile::make_channel(paths.phase2a_channel, detail)) return OperationResult::failure(detail);
    return OperationResult::success();
}
Phase2Service::Phase2Service(const Paths &paths, Supervisor &s)
    : paths_(paths), supervisor_(s), runtime_(paths.megavgm_status, paths.main_command),
      owner_(*this, paths.rbf_profile == "PROFILE_B" ? Profile::B : Profile::A) {}
bool Phase2Service::status(megavgm_autoplay2::PlaybackStatus &s, std::string &d) {
    return runtime_.read_status(s,d) == megavgm_autoplay2::StatusReadResult::Ok;
}
std::string Phase2Service::main_identity() { return megavgm_profile::process_identity(supervisor_.modified_pid()); }
bool Phase2Service::stop(std::string &d) { return runtime_.issue_stop(d); }
std::uint64_t Phase2Service::now() { return runtime_.monotonic_ms(); }
bool Phase2Service::replace(Profile p, std::string &d) {
    const auto result = supervisor_.switch_test_rbf(megavgm_profile::rbf(p), p == Profile::A ? "PROFILE_A" : "PROFILE_B");
    d = result.detail; return result.ok;
}
bool Phase2Service::fade(std::string &d) {
    // Immutable file, separate from controller's loop policy file. Main may
    // consume it after this function returns; keep it for the ENTER lifetime.
    const std::string path = paths_.phase2a_channel + "/fade-only.control";
    int fd = open(path.c_str(), O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
    if (fd >= 0) {
        const unsigned char record[] = {0x4d,0x56,0x02,0x02};
        bool ok = write(fd, record, sizeof(record)) == sizeof(record);
        if (ok) ok = !fsync(fd);
        if (close(fd)) ok = false;
        if (!ok) { d = "FADE_ONLY payload write failed"; return false; }
    } else if (errno != EEXIST) { d = std::strerror(errno); return false; }
    const std::string command = "load_file 2 " + path + "\n";
    fd = open(paths_.main_command.c_str(), O_WRONLY | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW);
    if (fd < 0) { d = std::strerror(errno); return false; }
    const auto n = write(fd, command.data(), command.size());
    const int saved = errno;
    const int closed = close(fd);
    if (n != static_cast<ssize_t>(command.size()) || closed) { d = std::strerror(saved); return false; }
    std::cout << "PHASE2A_FADE_ONLY timestamp_ms=" << now() << std::endl;
    return true;
}
OperationResult Phase2Service::tick() {
    megavgm_profile::Request request;
    std::string detail;
    if (!megavgm_profile::read_request(paths_.phase2a_channel, request, detail))
        return detail.empty() ? OperationResult::success() : OperationResult::failure(detail);
    const auto reply = owner_.tick(request);
    if (!megavgm_profile::write_reply(paths_.phase2a_channel, reply, detail)) return OperationResult::failure(detail);
    const std::string trace = "generation=" + std::to_string(reply.generation) + " domain=" +
        std::to_string(reply.domain) + " profile=" + megavgm_profile::name(reply.profile) + " state=" + reply.state +
        " baseline=" + std::to_string(reply.baseline) + " Main=" + reply.main_identity + " detail=" + reply.detail;
    if (trace != previous_trace_) { std::cout << "PHASE2A_SWITCH timestamp_ms=" << now() << ' ' << trace << std::endl; previous_trace_ = trace; }
    return reply.state == "FAILED" ? OperationResult::failure(reply.detail) : OperationResult::success();
}
}
