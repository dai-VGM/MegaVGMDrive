#include "phase2a.h"
#include "transport_observation.h"
#include "../megavgm_playlist/playlist.h"
#include "../megavgm_rbf_bench/latency_log.h"
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
    auto classification = megavgm_profile::classify_file(selected);
    if (!classification.resource_capacity_exceeded && classification.profile != Profile::A && classification.profile != Profile::B &&
        classification.profile != Profile::C && classification.profile != Profile::D && classification.profile != Profile::E && classification.profile != Profile::F)
        classification = megavgm_profile::inspect_raw_sid_for_prepare(selected);
    std::cout << "PHASE2A_COLD_CLASSIFY path=" << selected << " result=" << megavgm_profile::name(classification.profile)
              << " detail=" << classification.detail << std::endl;
    if (classification.profile != Profile::A && classification.profile != Profile::B &&
        classification.profile != Profile::C && classification.profile != Profile::D && classification.profile != Profile::E && classification.profile != Profile::F)
        return OperationResult::failure(classification.resource_capacity_exceeded ?
            "resource_capacity_exceeded" : "classification: " + classification.detail);
    for (const auto p : {Profile::A, Profile::B, Profile::C, Profile::D}) {
        struct stat s = {};
        if (lstat(megavgm_profile::rbf(p), &s) || !S_ISREG(s.st_mode) || s.st_size <= 0)
            return OperationResult::failure("all canonical A/B/C/D RBFs must exist before stock is stopped");
    }
    if (classification.profile == Profile::E || classification.profile == Profile::F) {
        struct stat s = {};
        if (lstat(megavgm_profile::rbf(classification.profile), &s) || !S_ISREG(s.st_mode) || s.st_size <= 0)
            return OperationResult::failure("selected candidate RBF missing");
    }
    paths.rbf = megavgm_profile::rbf(classification.profile);
    paths.rbf_profile = megavgm_profile::status_name(classification.profile);
    if (!megavgm_profile::make_channel(paths.phase2a_channel, detail)) return OperationResult::failure(detail);
    return OperationResult::success();
}
Phase2Service::Phase2Service(const Paths &paths, Supervisor &s)
    : paths_(paths), supervisor_(s), runtime_(paths.megavgm_status, paths.main_command),
      owner_(*this, paths.rbf_profile == "PROFILE_B" ? Profile::B :
          paths.rbf_profile == "PROFILE_C" ? Profile::C :
          paths.rbf_profile == "PROFILE_D" ? Profile::D :
          paths.rbf_profile == "PROFILE_E" ? Profile::E :
          paths.rbf_profile == "PROFILE_F" ? Profile::F : Profile::A) {
    observation_.epoch = paths.phase2a_channel.substr(paths.phase2a_channel.find_last_of('/') + 1);
    observation_.current_profile = observation_.required_profile = paths.rbf_profile;
    supervisor_.observe_transport(observation_);
}
bool Phase2Service::status(megavgm_autoplay2::PlaybackStatus &s, std::string &d) {
	const auto result = runtime_.read_status(s,d);
	std::string trace;
	if (result == megavgm_autoplay2::StatusReadResult::Ok) {
		trace = "read=OK version=" + std::to_string(s.version) +
			" session=" + std::to_string(s.session) +
			" state=" + megavgm_autoplay2::state_name(s.state) +
			" error=" + std::to_string(s.error) +
			" loop_valid=" + std::to_string(s.loop_valid ? 1 : 0) +
			" loop_count=" + std::to_string(s.loop_count);
	} else {
		trace = "read=FAILED result=" + std::to_string(static_cast<int>(result)) +
			" detail=" + d;
	}
	if (trace != previous_status_trace_) {
		std::cout << "PHASE2A_RESIDENT_STATUS timestamp_ms=" << now()
			<< " generation=" << observation_.generation
			<< " domain=" << observation_.domain
			<< " resident=" << observation_.current_profile
			<< ' ' << trace << std::endl;
		previous_status_trace_ = trace;
	}
	return result == megavgm_autoplay2::StatusReadResult::Ok;
}
std::string Phase2Service::main_identity() { return megavgm_profile::process_identity(supervisor_.modified_pid()); }
bool Phase2Service::stop(std::string &d) { return runtime_.issue_stop(d); }
std::uint64_t Phase2Service::now() { return runtime_.monotonic_ms(); }
bool Phase2Service::replace(Profile p, std::string &d) {
    megavgm_rbf_bench::event("t2_supervisor_enters_switching");
    observation_.state = "SWITCHING";
    observation_.changed = true;
    supervisor_.observe_transport(observation_);
    megavgm_rbf_bench::event("t3_target_profile_resolved");
    const std::string rbf = megavgm_profile::rbf(p);
    megavgm_rbf_bench::event("t4_target_rbf_path_resolved", rbf);
    const auto result = supervisor_.switch_test_rbf(rbf, megavgm_profile::status_name(p));
    d = result.detail; return result.ok;
}
bool Phase2Service::fade(std::string &d) {
    observation_.state = "FADING";
    supervisor_.observe_transport(observation_);
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
    const auto before = observation_;
    if (request.generation > observation_.generation) {
        megavgm_rbf_bench::context(request.generation,
            megavgm_profile::status_name(owner_.resident()),
            megavgm_profile::status_name(request.profile));
        megavgm_rbf_bench::event("t1_supervisor_request_observed");
        observation_.changed = request.profile != owner_.resident() && !request.stop;
        observation_.generation = request.generation;
        observation_.path = request.path;
        observation_.required_profile = megavgm_profile::status_name(request.profile);
    }
    const auto reply = owner_.tick(request);
    if (!megavgm_profile::write_reply(paths_.phase2a_channel, reply, detail)) return OperationResult::failure(detail);
    // No return value from the observer participates in switching/parking.
    if (reply.generation == request.generation) {
        observation_.generation = reply.generation;
        observation_.domain = reply.domain;
        observation_.baseline = reply.baseline;
        observation_.current_profile = megavgm_profile::status_name(owner_.resident());
        megavgm_autoplay2::PlaybackStatus playback;
        const megavgm_autoplay2::PlaybackStatus *verified = nullptr;
        if (reply.state == "READY") {
            std::string ignored;
            megavgm_profile::FileClient witness(paths_.phase2a_channel, paths_.main_load_file_status);
            if (witness.load_acknowledged(reply, observation_.path, ignored) &&
                status(playback, ignored)) verified = &playback;
        }
        observation_.state = observed_transport_state(before, reply, owner_.fading(), verified);
        supervisor_.observe_transport(observation_);
    } else observation_ = before;
    const std::string trace = "generation=" + std::to_string(reply.generation) + " domain=" +
        std::to_string(reply.domain) + " resident_profile=" + megavgm_profile::name(reply.profile) +
        " target_profile=" + megavgm_profile::name(request.profile) +
        " target_wire=" + std::to_string(static_cast<int>(request.profile)) + " state=" + reply.state +
        " baseline=" + std::to_string(reply.baseline) + " Main=" + reply.main_identity + " detail=" + reply.detail;
    if (trace != previous_trace_) { std::cout << "PHASE2A_SWITCH timestamp_ms=" << now() << ' ' << trace << std::endl; previous_trace_ = trace; }
    return reply.state == "FAILED" ? OperationResult::failure(reply.detail) : OperationResult::success();
}
}
