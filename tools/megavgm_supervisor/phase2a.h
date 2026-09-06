#pragma once
#include "linux_runtime.h"
#include "../megavgm_profile/switch.h"

namespace megavgm_supervisor {
OperationResult phase2a_preflight(Paths &, const std::string &directory,
    const std::string &start_file, const std::string &snapshot);
class Phase2Service final : public megavgm_profile::SwitchHost {
public:
    Phase2Service(const Paths &, Supervisor &);
    OperationResult tick();
    bool status(megavgm_autoplay2::PlaybackStatus &, std::string &) override;
    std::string main_identity() override;
    bool fade(std::string &) override;
    bool stop(std::string &) override;
    bool replace(megavgm_profile::Profile, std::string &) override;
    std::uint64_t now() override;
private:
    Paths paths_;
    Supervisor &supervisor_;
    megavgm_autoplay2::PosixRuntime runtime_;
    megavgm_profile::SwitchOwner owner_;
    std::string previous_trace_;
};
}
