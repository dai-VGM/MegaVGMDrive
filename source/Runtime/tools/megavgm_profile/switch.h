#pragma once
#include "profile.h"
#include "../megavgm_autoplay2/autoplay2.h"
#include <string>

namespace megavgm_profile {
struct Request {
    std::uint64_t generation = 0, domain = 0;
    std::uint32_t session = 0;
    Profile profile = Profile::Error;
    bool stop = false;
    std::string path;
};
struct Reply {
    std::uint64_t generation = 0, domain = 0;
    std::uint32_t baseline = 0;
    Profile profile = Profile::Error;
    std::string main_identity, state, detail;
};
class Client {
public:
    virtual ~Client() = default;
    virtual bool begin(const Request &, std::string &) = 0;
    virtual bool poll(Reply &, std::string &) = 0;
    virtual bool load_acknowledged(const Reply &, const std::string &, std::string &) = 0;
    // Conservative fallback for test/other clients. FileClient keeps an upload
    // proof separate from its latest-transfer witness and verifies live owners.
    virtual bool owns_session(const Reply &r, const std::string &p,
        const megavgm_autoplay2::PlaybackStatus &s, std::string &d) {
        return s.version == 2 && !s.error &&
            s.state == megavgm_autoplay2::PlaybackState::Playing &&
            s.session == static_cast<std::uint32_t>(r.baseline + 1u) &&
            load_acknowledged(r, p, d);
    }
    virtual bool owns_parked(const Reply &lease, std::string &d) {
        Reply current;
        return poll(current, d) && current.state == "STOPPED" &&
            current.generation == lease.generation && current.domain == lease.domain &&
            current.baseline == lease.baseline && current.profile == lease.profile &&
            current.main_identity == lease.main_identity;
    }
    virtual void note_policy_control() {}
    virtual void forget_session() {}
};
class SwitchHost {
public:
    virtual ~SwitchHost() = default;
    virtual bool status(megavgm_autoplay2::PlaybackStatus &, std::string &) = 0;
    virtual std::string main_identity() = 0;
    virtual bool fade(std::string &) = 0;
    virtual bool stop(std::string &) = 0;
    // Returns only after old Main drain, successor SHA/argv verification and
    // fresh authoritative IDLE. Controller remains parked throughout.
    virtual bool replace(Profile, std::string &) = 0;
    virtual std::uint64_t now() = 0;
};
class SwitchOwner {
public:
    SwitchOwner(SwitchHost &host, Profile resident) : host_(host), resident_(resident) {}
    Reply tick(const Request &request);
    Profile resident() const { return resident_; }
    // Read-only telemetry; never consulted by the controller or switch engine.
    bool fading() const { return ending_ && !stopping_; }
private:
    SwitchHost &host_;
    Profile resident_;
    Reply reply_;
    bool pending_ = false, ending_ = false, stopping_ = false, failed_ = false;
    std::uint64_t domain_ = 1, deadline_ = 0;
    std::uint64_t grant_source_domain_ = 0;
    std::uint32_t old_session_ = 0;
    std::string old_main_;
};

// Private per-ENTER directory is the epoch; generation numbers cannot alias
// a previous supervisor/controller pair. Files are atomic bounded records.
bool make_channel(std::string &directory, std::string &detail);
bool write_request(const std::string &, const Request &, std::string &);
bool read_request(const std::string &, Request &, std::string &);
bool write_reply(const std::string &, const Reply &, std::string &);
bool read_reply(const std::string &, Reply &, std::string &);
std::string process_identity(int pid);
class FileClient final : public Client {
public:
    explicit FileClient(std::string directory, std::string acknowledgment = "/tmp/megavgm_load_file.status")
        : directory_(std::move(directory)), acknowledgment_(std::move(acknowledgment)) {}
    bool begin(const Request &r, std::string &d) override;
    bool owns_parked(const Reply &, std::string &) override;
    bool poll(Reply &r, std::string &d) override { return read_reply(directory_, r, d); }
    bool load_acknowledged(const Reply &, const std::string &, std::string &) override;
    bool owns_session(const Reply &, const std::string &,
        const megavgm_autoplay2::PlaybackStatus &, std::string &) override;
    void note_policy_control() override { if (proof_valid_) policy_allowed_ = true; }
    void forget_session() override { proof_valid_ = policy_allowed_ = false; }

private:
    std::string directory_;
    std::string acknowledgment_;
    bool live_lease(const Reply &, std::string &);
    bool proof_valid_ = false, policy_allowed_ = false;
    bool channel_pinned_ = false;
    std::uint64_t channel_device_ = 0, channel_inode_ = 0;
    Reply proof_lease_;
    std::string proof_path_;
    std::uint64_t proof_sequence_ = 0, proof_device_ = 0, proof_inode_ = 0;
};
}
