#include "profile.h"
#include "../megavgm_supervisor/sha256.h"
#include <cerrno>
#include <cstring>
#include <fcntl.h>
#include <iostream>
#include <sys/stat.h>
#include <unistd.h>

namespace {
int prepare_sn76489_clock(const char *path) {
    const int fd = open(path, O_RDWR | O_NOFOLLOW | O_CLOEXEC);
    if (fd < 0) {
        std::cerr << "failed to open preparation temp: " << path << ": "
                  << std::strerror(errno) << '\n';
        return 1;
    }
    struct stat st = {};
    if (fstat(fd, &st) || !S_ISREG(st.st_mode) || st.st_size < 64 ||
        st.st_size > 64*1024*1024) {
        std::cerr << "invalid preparation temp: " << path << '\n';
        close(fd);
        return 1;
    }
    std::vector<unsigned char> bytes(static_cast<std::size_t>(st.st_size));
    std::size_t pos = 0;
    while (pos < bytes.size()) {
        const auto count = pread(fd, bytes.data()+pos, bytes.size()-pos,
            static_cast<off_t>(pos));
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) break;
        pos += static_cast<std::size_t>(count);
    }
    if (pos != bytes.size()) {
        std::cerr << "short preparation read: " << path << '\n';
        close(fd);
        return 1;
    }

    std::string source_sha, normalized_sha, detail;
    if (!megavgm_supervisor::sha256_file(path, source_sha, detail)) {
        std::cerr << "failed to hash preparation temp: " << path << ": "
                  << detail << '\n';
        close(fd);
        return 1;
    }
    const auto normalization =
        megavgm_profile::normalize_sn76489_clock_bytes(bytes);
    if (!normalization.applied) {
        close(fd);
        return 0;
    }
    std::size_t written = 0;
    constexpr std::size_t kClockSize = 4;
    while (written < kClockSize) {
        const auto count = pwrite(fd, bytes.data()+0x0c+written,
            kClockSize-written,
            static_cast<off_t>(0x0c+written));
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) break;
        written += static_cast<std::size_t>(count);
    }
    const int close_result = close(fd);
    if (written != kClockSize || close_result != 0) {
        std::cerr << "failed to write normalized SN76489 clock: " << path << '\n';
        return 1;
    }
    if (!megavgm_supervisor::sha256_file(path, normalized_sha, detail)) {
        std::cerr << "failed to hash normalized body: " << path << ": "
                  << detail << '\n';
        return 1;
    }
    std::cout << "NORMALIZE_SN76489_CLOCK path=" << path
              << " original=0 normalized=3579545"
              << " reason=PSG_commands_present_in_validated_Mega_Drive_profile"
              << " source_body_sha256=" << source_sha
              << " normalized_body_sha256=" << normalized_sha << '\n';
    return 0;
}
}

int main(int argc, char **argv) {
    if (argc == 3 && std::string(argv[1]) == "--prepare-sn76489-clock")
        return prepare_sn76489_clock(argv[2]);
    if (argc < 3) { std::cerr << "Usage: classify <approved-root> <vgm>...\n"; return 2; }
    int result = 0;
    for (int i=2; i<argc; ++i) {
        const auto c = megavgm_profile::classify_file(argv[i], argv[1]);
        std::cout << megavgm_profile::name(c.profile) << '\t' << c.commands << '\t' << argv[i] << '\t' << c.detail << '\n';
        if (c.profile != megavgm_profile::Profile::A && c.profile != megavgm_profile::Profile::B &&
            c.profile != megavgm_profile::Profile::C &&
            c.profile != megavgm_profile::Profile::D && c.profile != megavgm_profile::Profile::E && c.profile != megavgm_profile::Profile::F) result = 1;
    }
    return result;
}
