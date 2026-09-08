#include "profile.h"
#include <cerrno>
#include <climits>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

namespace megavgm_profile {
const char *name(Profile p) {
    switch (p) {
    case Profile::A: return "SUPPORTED_PROFILE_A";
    case Profile::B: return "SUPPORTED_PROFILE_B";
    case Profile::Unsupported: return "UNSUPPORTED";
    case Profile::Ambiguous: return "AMBIGUOUS";
    default: return "ERROR";
    }
}
const char *rbf(Profile p) {
    return p == Profile::A ? "/media/fat/_custom_core/MegaVGMPlayer_Transport13FadeOnly_A_MiSTer.rbf" :
        p == Profile::B ? "/media/fat/_custom_core/MegaVGMPlayer_Transport13FadeOnly_B_MiSTer.rbf" : "";
}
Classification classify_bytes(const std::vector<unsigned char> &b) {
    Classification r;
    auto fail = [&](Profile p, const std::string &s) { r.profile = p; r.detail = s; return r; };
    auto u32 = [&](std::size_t n) -> std::uint32_t {
        return n + 4 <= b.size() ? std::uint32_t(b[n]) | (std::uint32_t(b[n+1]) << 8) |
            (std::uint32_t(b[n+2]) << 16) | (std::uint32_t(b[n+3]) << 24) : 0;
    };
    if (b.size() < 64 || u32(0) != 0x206d6756) return fail(Profile::Error, "not uncompressed VGM");
    const std::uint64_t end = std::uint64_t(u32(4)) + 4;
    const auto version = u32(8);
    const std::uint64_t data = version < 0x150 || !u32(0x34) ? 64 : std::uint64_t(u32(0x34)) + 0x34;
    if (end > b.size() || data < 64 || data >= end) return fail(Profile::Error, "invalid VGM bounds");
    if (version < 0x110 || version > 0x171) return fail(Profile::Unsupported, "unsupported VGM version");
    auto clock = [&](std::size_t n) { return n + 4 <= data ? u32(n) : 0u; };
    bool a = false, opb = false, end_seen = false, unsupported = false;
    unsigned used = 0;
    const std::uint64_t loop = u32(0x1c) ? std::uint64_t(u32(0x1c)) + 0x1c : 0;
    bool loop_seen = !loop;
    for (std::uint64_t pc = data; pc < end;) {
        if (pc == loop) loop_seen = true;
        ++r.commands;
        const unsigned c = b[pc];
        std::uint64_t size = 1;
        if (c == 0x66) { end_seen = true; break; }
        if (c == 0x61) size = 3;
        else if (c == 0x62 || c == 0x63 || (c >= 0x70 && c <= 0x7f)) {}
        else if (c == 0x67) {
            if (pc + 7 > end || b[pc+1] != 0x66) return fail(Profile::Error, "malformed data block");
            const auto length = u32(pc+3);
            if (length & 0x80000000u) return fail(Profile::Unsupported, "second-chip data block");
            size = 7ull + length;
            const unsigned type = b[pc+2];
            if (type == 0x82 || type == 0x83) opb = true;
            else if (type == 0x80) { a = true; used |= 16; }
            else if (type == 0x00) { a = true; used |= 2; }
            else unsupported = true;
            if (type >= 0x80 && length < 8) return fail(Profile::Error, "short ROM data block");
        } else if (c == 0x58 || c == 0x59) { opb = true; size = 3; }
        else if (c == 0x4f || c == 0x50) { a = true; used |= 1; size = 2; }
        else if (c == 0x52 || c == 0x53) { a = true; used |= 2; size = 3; }
        else if (c == 0x54) { a = true; used |= 4; size = 3; }
        else if (c == 0x55) { a = true; used |= 8; size = 3; }
        else if (c == 0xc0) { a = true; used |= 16; size = 4; }
        else if (c >= 0x80 && c <= 0x8f) { a = true; used |= 2; }
        else if (c == 0xe0) { a = true; used |= 2; size = 5; }
        else return fail(Profile::Unsupported, "unsupported command at " + std::to_string(pc) + ": " + std::to_string(c));
        if (size > end - pc) return fail(Profile::Error, "truncated command/data block");
        pc += size;
    }
    if (!end_seen || !loop_seen) return fail(Profile::Error, "missing EOF or invalid loop command boundary");
    if (a && opb) return fail(Profile::Ambiguous, "actual command/data usage requires both profiles");
    if (unsupported) return fail(Profile::Unsupported, "unsupported data block type");
    if (!a && !opb) return fail(Profile::Ambiguous, "no supported sound command usage");
    if (opb) {
        if (!(clock(0x4c) & 0x3fffffffu)) return fail(Profile::Error, "YM2610 commands without clock/header");
        if (clock(0x4c) & 0x40000000u) return fail(Profile::Unsupported, "dual YM2610");
        // B scanner uses the explicit v1.50 data offset (does not normalize 0).
        if (version >= 0x150 && !u32(0x34)) return fail(Profile::Unsupported, "B requires explicit data offset");
        return fail(Profile::B, "YM2610/YM2610B commands; hardware scanner retains register/address validation");
    }
    const unsigned offsets[] = {0x0c, 0x2c, 0x30, 0x44, 0x38};
    for (unsigned i = 0; i != 5; ++i) if (used & (1u << i)) {
        if (!(clock(offsets[i]) & 0x3fffffffu)) return fail(Profile::Error, "used chip has no header clock");
        if (clock(offsets[i]) & 0x40000000u) return fail(Profile::Unsupported, "dual chip");
    }
    return fail(Profile::A, "A command whitelist; no skipped/unknown sound command admitted");
}
Classification classify_file(const std::string &path, const std::string &root) {
    char canonical[PATH_MAX], base[PATH_MAX];
    if (!realpath(root.c_str(), base) || !realpath(path.c_str(), canonical))
        return {Profile::Error, std::strerror(errno), 0};
    const std::string p(canonical), r(base);
    if (p.compare(0, r.size()+1, r + "/") != 0 || p.find_first_of("\r\n") != std::string::npos)
        return {Profile::Error, "path outside approved root", 0};
    const int fd = open(p.c_str(), O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK);
    if (fd < 0) return {Profile::Error, std::strerror(errno), 0};
    struct stat st = {};
    if (fstat(fd, &st) || !S_ISREG(st.st_mode) || st.st_size < 64 || st.st_size > 64*1024*1024) {
        close(fd); return {Profile::Error, "invalid file type/size (max 64MiB)", 0};
    }
    std::vector<unsigned char> bytes(static_cast<std::size_t>(st.st_size));
    std::size_t pos = 0;
    while (pos < bytes.size()) {
        const auto n = read(fd, bytes.data()+pos, bytes.size()-pos);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) break;
        pos += n;
    }
    close(fd);
    if (pos != bytes.size()) return {Profile::Error, "short VGM read", 0};
    return classify_bytes(bytes);
}
}
