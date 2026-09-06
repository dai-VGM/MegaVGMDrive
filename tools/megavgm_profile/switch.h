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
    bool begin(const Request &r, std::string &d) override { return write_request(directory_, r, d); }
    bool poll(Reply &r, std::string &d) override { return read_reply(directory_, r, d); }
    bool load_acknowledged(const Reply &, const std::string &, std::string &) override;
private:
    std::string directory_;
    std::string acknowledgment_;
};
}
