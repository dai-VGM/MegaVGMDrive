#pragma once
#include <cstdint>
#include <string>
#include <vector>

namespace megavgm_profile {
enum class Profile { A, B, Unsupported, Ambiguous, Error };
const char *name(Profile profile);
const char *rbf(Profile profile);
struct Classification {
    Profile profile = Profile::Error;
    std::string detail;
    std::uint64_t commands = 0;
};
Classification classify_bytes(const std::vector<unsigned char> &bytes);
Classification classify_file(const std::string &path,
    const std::string &root = "/media/fat/MegaVGMDrive");
}
