#include "profile.h"
#include <algorithm>
#include <array>
#include <cerrno>
#include <climits>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

namespace megavgm_profile {
namespace {
constexpr const char *kSoundChipMetadata = ".megavgm-sound-chip";
constexpr std::size_t kSidHeaderBytes = 128;
constexpr std::size_t kSidMaximumBytes = 8 * 1024 * 1024;
constexpr std::uint32_t kSidV1AllowedFlags = 0x1d;
constexpr std::uint32_t kSidV2AllowedFlags = 0x1f;

std::uint16_t le16(const std::vector<unsigned char> &b, std::size_t n) {
    return std::uint16_t(b[n]) | (std::uint16_t(b[n+1]) << 8);
}
std::uint32_t le32(const std::vector<unsigned char> &b, std::size_t n) {
    return std::uint32_t(b[n]) | (std::uint32_t(b[n+1]) << 8) |
        (std::uint32_t(b[n+2]) << 16) | (std::uint32_t(b[n+3]) << 24);
}
std::uint64_t le64(const std::vector<unsigned char> &b, std::size_t n) {
    return std::uint64_t(le32(b,n)) | (std::uint64_t(le32(b,n+4)) << 32);
}
bool all_zero(const std::vector<unsigned char> &b, std::size_t begin, std::size_t end) {
    return std::all_of(b.begin()+begin,b.begin()+end,[](unsigned char v){return v==0;});
}
std::string digest(const std::vector<unsigned char> &b) {
    static const char digits[] = "0123456789abcdef";
    if (all_zero(b,0x60,0x80)) return {};
    std::string result;
    result.reserve(64);
    for (std::size_t i=0x60;i<0x80;++i) {
        result.push_back(digits[b[i]>>4]); result.push_back(digits[b[i]&15]);
    }
    return result;
}
bool sid_clock_ok(std::uint32_t num, std::uint32_t den, unsigned timing) {
    return num && den && ((timing==1 && std::uint64_t(num)==985248ull*den) ||
        (timing==2 && std::uint64_t(num)==1022727ull*den));
}

bool cycles_to_ms(std::uint64_t cycles, std::uint32_t clock_num,
        std::uint32_t clock_den, std::uint64_t &milliseconds) {
    if (!cycles || !clock_num || !clock_den) return false;
    const std::uint64_t whole = cycles / clock_num;
    const std::uint64_t remainder = cycles % clock_num;
    if (whole > UINT64_MAX / clock_den / 1000u ||
        remainder > UINT64_MAX / clock_den / 1000u) return false;
    const std::uint64_t whole_ms = whole * clock_den * 1000u;
    const std::uint64_t numerator = remainder * clock_den * 1000u;
    const std::uint64_t partial = numerator / clock_num +
        (numerator % clock_num ? 1u : 0u);
    if (whole_ms > UINT64_MAX - partial) return false;
    milliseconds = whole_ms + partial;
    return milliseconds != 0;
}

std::uint64_t samples_to_ms(std::uint64_t samples) {
    return samples / 44100u * 1000u +
        ((samples % 44100u) * 1000u + 44099u) / 44100u;
}

Classification classify_sid(const std::vector<unsigned char> &b) {
    Classification r;
    auto fail = [&](const std::string &s) { r.profile=Profile::Error;r.detail=s;return r; };
    if (b.size()<kSidHeaderBytes || b.size()>kSidMaximumBytes)
        return fail("MVGMSID size outside 128..8388608 bytes");
    static const unsigned char magic[8]={'M','V','G','M','S','I','D',0};
    if (!std::equal(magic,magic+8,b.begin())) return fail("bad MVGMSID magic");
    const auto major=le16(b,8),minor=le16(b,10),header=le16(b,12),encoding=le16(b,14);
    if (minor || header!=128 || !((major==1 && encoding==16) || (major==2 && encoding==1)))
        return fail("unsupported MVGMSID version/header/encoding");
    const auto flags=le32(b,0x10),num=le32(b,0x14),den=le32(b,0x18);
    const unsigned model=b[0x1c],timing=b[0x1d];
    const auto subtune=le32(b,0x20);
    const auto count=le64(b,0x28),body=le64(b,0x30);
    const auto end_cycle=le64(b,0x38),duration=le64(b,0x40);
    const auto loop_index=le64(b,0x48),loop_start=le64(b,0x50),loop_end=le64(b,0x58);
    const auto allowed_flags=major==2?kSidV2AllowedFlags:kSidV1AllowedFlags;
    if ((flags&~allowed_flags) || (major==1 && (flags&2)) ||
        b[0x1e]!=1 || b[0x1f] || !all_zero(b,0x24,0x28))
        return fail("unsupported MVGMSID flags/SID count/reserved field");
    if ((model!=1 && model!=2) || (timing!=1 && timing!=2) || !subtune ||
        !sid_clock_ok(num,den,timing)) return fail("invalid MVGMSID model/timing/clock/subtune");
    if (bool(flags&1)!=bool(duration))
        return fail("invalid MVGMSID duration/loop metadata");
    if (flags&2) {
        if (major!=2 || loop_index>count || !(loop_start<loop_end) ||
            loop_end!=end_cycle) return fail("invalid MVGMSID loop range/ordinal");
    } else if (loop_index || loop_start || loop_end) {
        return fail("MVGMSID loop metadata without LOOP_VALID");
    }
    if (body>kSidMaximumBytes-kSidHeaderBytes || body+kSidHeaderBytes!=b.size())
        return fail("MVGMSID body/file length mismatch");
    std::uint64_t writes=0,cycle=0;
    if (major==1) {
        if (!count || count>(kSidMaximumBytes-kSidHeaderBytes)/16 || body!=count*16)
            return fail("invalid MVGMSID v1 event count/size");
        bool eof=false; std::uint64_t last_write=0; bool have_write=false;
        for (std::uint64_t i=0;i<count;++i) {
            const std::size_t p=kSidHeaderBytes+static_cast<std::size_t>(i*16);
            const unsigned op=b[p],addr=b[p+1],data=b[p+2]; const auto operand=le64(b,p+8);
            if (!all_zero(b,p+3,p+8)) return fail("nonzero MVGMSID v1 event reserved field");
            if (op==0) {
                if (addr || data || !operand || operand>UINT64_MAX-cycle) return fail("invalid/overflowing MVGMSID v1 WAIT");
                cycle+=operand;
            } else if (op==1) {
                if (addr>0x18 || operand || (have_write && last_write==cycle)) return fail("invalid/same-cycle MVGMSID v1 WRITE");
                last_write=cycle;have_write=true;++writes;
            } else if (op==0xff) {
                if (addr || data || operand || i+1!=count) return fail("malformed MVGMSID v1 EOF");
                eof=true;
            } else return fail("unknown MVGMSID v1 opcode");
        }
        if (!eof || cycle!=end_cycle) return fail("MVGMSID v1 missing EOF/cycle mismatch");
    } else {
        if (count>(kSidMaximumBytes-2)/3 || body<count*3+2 || body>count*12+11)
            return fail("impossible MVGMSID v2 WRITE count/body size");
		std::size_t pos=kSidHeaderBytes; bool eof=false,have_write=false;
		bool loop_boundary_seen=false,loop_first_write_seen=false;
		std::uint64_t last_write_cycle=0,loop_first_write_cycle=0;
        while (pos<b.size()) {
            std::uint64_t delta=0; unsigned group=0;
            for (;;) {
                if (pos>=b.size() || group==10) return fail("truncated/overlong MVGMSID v2 ULEB128");
                const unsigned byte=b[pos++];
                if ((group==9 && byte!=1) || (group && !(byte&0x80) && !(byte&0x7f)))
                    return fail("noncanonical/overflowing MVGMSID v2 ULEB128");
                delta|=std::uint64_t(byte&0x7f)<<(7*group);
                ++group; if (!(byte&0x80)) break;
            }
            if (delta>UINT64_MAX-cycle || pos>=b.size()) return fail("overflowing/truncated MVGMSID v2 record");
            cycle+=delta;
            const unsigned tag=b[pos++];
            if (tag==0xff) {
                if (pos!=b.size() || writes!=count || cycle!=end_cycle)
                    return fail("malformed MVGMSID v2 EOF/count/cycle");
				if (flags&2) {
					if (loop_index==count) {
						const bool wait_only_boundary=!have_write ? loop_start==0 :
							last_write_cycle<=loop_start;
                        if (!wait_only_boundary)
                            return fail("MVGMSID loop ordinal is not an event boundary");
                        loop_boundary_seen=true;
                    }
                    if (!loop_boundary_seen)
                        return fail("MVGMSID loop ordinal is not an event boundary");
					if (loop_first_write_seen && loop_first_write_cycle==loop_start &&
						last_write_cycle==loop_end)
                        return fail("same-cycle MVGMSID WRITE across loop boundary");
                }
                eof=true;break;
            }
            if (tag>0x18 || pos>=b.size() || (writes && !delta) || writes>=count || cycle>end_cycle)
                return fail("invalid/same-cycle MVGMSID v2 WRITE");
			++pos;
			if ((flags&2) && writes==loop_index) {
				if ((have_write && last_write_cycle>loop_start) || cycle<loop_start)
					return fail("MVGMSID loop WRITE ordinal/cycle mismatch");
				loop_boundary_seen=true;loop_first_write_seen=true;loop_first_write_cycle=cycle;
            }
            last_write_cycle=cycle;have_write=true;++writes;
        }
        if (!eof) return fail("missing MVGMSID v2 EOF");
    }
    r.profile=Profile::C;
    r.detail=major==2 ? "strict MVGMSID Packed v2 stream" : "strict MVGMSID v1 stream";
    r.commands=writes;
    r.sound_chips=model==1 ? "SID 6581" : "SID 8580";
    r.sid.format_version=major;r.sid.model=model==1?"6581":"8580";
    r.sid.timing=timing==1?"PAL":"NTSC";r.sid.subtune=subtune;
    r.sid.capture_limited=flags&4;r.sid.source_sha256=digest(b);
    const bool native_loop = (flags & 2u) != 0;
    const std::uint64_t first_cycles = native_loop ? end_cycle : duration;
    std::uint64_t first_ms = 0, loop_ms = 0;
    if (((flags & 1u) || native_loop) &&
        cycles_to_ms(first_cycles, num, den, first_ms)) {
        r.timing.duration_valid = true;
        r.timing.duration_ms = first_ms;
        r.timing.source = "MVGMSID_HEADER";
    }
    r.timing.loop_valid = native_loop;
    if (native_loop && cycles_to_ms(loop_end-loop_start, num, den, loop_ms)) {
        r.timing.loop_duration_ms = loop_ms;
    }
    return r;
}

std::string declared_sound_chip(const std::string &track, const std::string &root) {
    const auto slash = track.find_last_of('/');
    if (slash == std::string::npos) return {};
    std::string directory = track.substr(0, slash);
    while (directory.size() > root.size() &&
           directory.compare(0, root.size() + 1, root + "/") == 0) {
        const std::string metadata = directory + "/" + kSoundChipMetadata;
        const int fd = open(metadata.c_str(), O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK);
        if (fd >= 0) {
            struct stat st = {};
            char bytes[65] = {};
            const auto count = fstat(fd, &st) == 0 && S_ISREG(st.st_mode) &&
                    st.st_size > 0 && st.st_size <= 64
                ? read(fd, bytes, static_cast<std::size_t>(st.st_size)) : -1;
            close(fd);
            if (count != st.st_size) return {};
            std::string record(bytes, static_cast<std::size_t>(count));
            record.erase(std::remove(record.begin(), record.end(), '\r'), record.end());
            if (record == "version=1\nsound_chip=YM2610\n" ||
                record == "version=1\nsound_chip=YM2610") return "YM2610";
            if (record == "version=1\nsound_chip=YM2610B\n" ||
                record == "version=1\nsound_chip=YM2610B") return "YM2610B";
            return {};
        }
        if (errno != ENOENT && errno != ENOTDIR) return {};
        const auto parent = directory.find_last_of('/');
        if (parent == std::string::npos) break;
        directory.resize(parent);
    }
    return {};
}
}

const char *name(Profile p) {
    switch (p) {
    case Profile::A: return "SUPPORTED_PROFILE_A";
    case Profile::B: return "SUPPORTED_PROFILE_B";
    case Profile::C: return "SUPPORTED_PROFILE_C";
    case Profile::D: return "SUPPORTED_PROFILE_D";
    case Profile::Unsupported: return "UNSUPPORTED";
    case Profile::Ambiguous: return "AMBIGUOUS";
    default: return "ERROR";
    }
}
const char *rbf(Profile p) {
    return p == Profile::A ? "/media/fat/_Custom Cores/Cores/MegaVGMDrive_A.rbf" :
        p == Profile::B ? "/media/fat/_Custom Cores/Cores/MegaVGMDrive_B.rbf" :
        p == Profile::C ? "/media/fat/_Custom Cores/Cores/MegaVGMDrive_C.rbf" :
        p == Profile::D ? "/media/fat/_Custom Cores/Cores/MegaVGMDrive_D.rbf" : "";
}
const char *status_name(Profile p) {
    return p==Profile::A?"PROFILE_A":p==Profile::B?"PROFILE_B":
        p==Profile::C?"PROFILE_C":p==Profile::D?"PROFILE_D":"UNKNOWN";
}
Classification classify_bytes(const std::vector<unsigned char> &b) {
    static const unsigned char sid_magic[8]={'M','V','G','M','S','I','D',0};
    if (b.size()>=8 && std::equal(sid_magic,sid_magic+8,b.begin())) return classify_sid(b);
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
    bool a = false, opb = false, c140_command = false;
    bool c140_block = false, end_seen = false, unsupported = false;
    bool ym2610b_channel_used = false;
    unsigned used = 0;
    unsigned command_chips = 0;
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
            else if (type == 0x8d) c140_block = true;
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
        else if (c == 0xd4) { c140_command = true; size = 4; }
        else if (c >= 0x80 && c <= 0x8f) { a = true; used |= 2; }
        else if (c == 0xe0) { a = true; used |= 2; size = 5; }
        else return fail(Profile::Unsupported, "unsupported command at " + std::to_string(pc) + ": " + std::to_string(c));
        if (size > end - pc) return fail(Profile::Error, "truncated command/data block");
        if (c == 0x58 || c == 0x59) {
            const unsigned port = c - 0x58;
            const unsigned address = b[pc+1];
            const unsigned value = b[pc+2];
            // YM2610B adds the two FM channels represented by selector zero.
            // Operator initialization alone is not audible channel use (Neo Geo
            // streams commonly initialize those hidden slots), so require a
            // key-on, frequency or channel-control write to that selector.
            const unsigned key_channel = value & 7;
            const bool b_key_on = port == 0 && address == 0x28 &&
                (key_channel == 0 || key_channel == 4);
            const bool b_channel_register = address == 0xa0 || address == 0xa4 ||
                address == 0xb0 || address == 0xb4;
            ym2610b_channel_used |= b_key_on || b_channel_register;
        }
        // Observe the already-accepted command stream. ROM/data blocks alone
        // are not evidence that a chip was commanded. Do not alter used/profile.
        if (c == 0x4f || c == 0x50) command_chips |= 1;
        if (c == 0x52 || c == 0x53 || c == 0xe0 || (c >= 0x80 && c <= 0x8f)) command_chips |= 2;
        if (c == 0x54) command_chips |= 4;
        if (c == 0x55) command_chips |= 8;
        if (c == 0xc0) command_chips |= 16;
        if (c == 0x58 || c == 0x59) command_chips |= 32;
        if (c == 0xd4) command_chips |= 64;
        pc += size;
    }
    if (!end_seen || !loop_seen) return fail(Profile::Error, "missing EOF or invalid loop command boundary");
    if (unsupported) return fail(Profile::Unsupported, "unsupported data block type");
    const auto total_samples = u32(0x18);
    const auto loop_samples = u32(0x20);
    if (total_samples) {
        r.timing.duration_valid = true;
        r.timing.duration_ms = samples_to_ms(total_samples);
        r.timing.source = "VGM_HEADER";
    }
    r.timing.loop_valid = loop != 0;
    if (loop && loop_samples) {
        r.timing.loop_duration_ms = samples_to_ms(loop_samples);
    }
    if (opb && (a || c140_command || c140_block))
        return fail(Profile::Ambiguous, "actual command/data usage requires multiple profiles");
    if (c140_command) {
        // Engine D shares only YM2151 with Engine A. Any other A-family
        // command in a C140 stream is not silently discarded or rerouted.
        if (used & ~4u)
            return fail(Profile::Ambiguous, "C140 stream also uses a non-YM2151 Engine A chip");
        if (!c140_block)
            return fail(Profile::Error, "C140 commands without 0x8D ROM data block");
        const auto c140_clock = clock(0xa8);
        if (!(c140_clock & 0x3fffffffu))
            return fail(Profile::Error, "C140 commands without clock/header");
        if (c140_clock & 0x40000000u)
            return fail(Profile::Unsupported, "dual C140");
        // C140 type was added in VGM 1.61. Older/absent metadata is the
        // legacy System 2 contract. Type 1 is System 21; ASIC219/type 2 is
        // intentionally not routed to the current Engine D implementation.
        const unsigned c140_type = version >= 0x161 && data > 0x96 ? b[0x96] : 0;
        if (c140_type == 2)
            return fail(Profile::Unsupported, "C140 ASIC219/type 2 is unsupported");
        if (c140_type > 2)
            return fail(Profile::Unsupported, "unknown C140 type");
        if (used & 4u) {
            if (!(clock(0x30) & 0x3fffffffu))
                return fail(Profile::Error, "YM2151 commands without clock/header");
            if (clock(0x30) & 0x40000000u)
                return fail(Profile::Unsupported, "dual YM2151");
        }
        r.sound_chips = (command_chips & 4) ? "YM2151,C140" : "C140";
        return fail(Profile::D, c140_type == 1 ?
            "C140 System 21 command/data usage" :
            "C140 System 2/legacy command/data usage");
    }
    if (c140_block)
        return fail(Profile::Unsupported, "C140 ROM data block without C140 command usage");
    if (a && opb) return fail(Profile::Ambiguous, "actual command/data usage requires both profiles");
    if (!a && !opb) return fail(Profile::Ambiguous, "no supported sound command usage");
    if (opb) {
        if (!(clock(0x4c) & 0x3fffffffu)) return fail(Profile::Error, "YM2610 commands without clock/header");
        if (clock(0x4c) & 0x40000000u) return fail(Profile::Unsupported, "dual YM2610");
        // B scanner uses the explicit v1.50 data offset (does not normalize 0).
        if (version >= 0x150 && !u32(0x34)) return fail(Profile::Unsupported, "B requires explicit data offset");
        if (command_chips & 32)
            r.sound_chips = (clock(0x4c) & 0x80000000u) && ym2610b_channel_used
                ? "YM2610B" : "YM2610";
        return fail(Profile::B, "YM2610/YM2610B commands; hardware scanner retains register/address validation");
    }
    const unsigned offsets[] = {0x0c, 0x2c, 0x30, 0x44, 0x38};
    for (unsigned i = 0; i != 5; ++i) if (used & (1u << i)) {
        if (!(clock(offsets[i]) & 0x3fffffffu)) return fail(Profile::Error, "used chip has no header clock");
        if (clock(offsets[i]) & 0x40000000u) return fail(Profile::Unsupported, "dual chip");
    }
    const char *chips[] = {"PSG", "YM2612", "YM2151", "YM2203", "SegaPCM"};
    for (unsigned i = 0; i != 5; ++i) if (command_chips & (1u << i)) {
        if (!r.sound_chips.empty()) r.sound_chips += ',';
        r.sound_chips += chips[i];
    }
    return fail(Profile::A, "A command whitelist; no skipped/unknown sound command admitted");
}

Sn76489ClockNormalization normalize_sn76489_clock_bytes(
        std::vector<unsigned char> &bytes) {
    Sn76489ClockNormalization result;
    auto u32 = [&](std::size_t n) -> std::uint32_t {
        return n + 4 <= bytes.size() ? std::uint32_t(bytes[n]) |
            (std::uint32_t(bytes[n+1]) << 8) |
            (std::uint32_t(bytes[n+2]) << 16) |
            (std::uint32_t(bytes[n+3]) << 24) : 0;
    };
    if (bytes.size() < 64 || u32(0) != 0x206d6756) {
        result.detail = "not an uncompressed VGM";
        return result;
    }
    const auto version = u32(8);
    const std::uint64_t data = version < 0x150 || !u32(0x34) ? 64 :
        std::uint64_t(u32(0x34)) + 0x34;
    if (data < 64 || data > bytes.size() || u32(0x0c) != 0) {
        result.detail = "SN76489 clock is not the sole eligible zero field";
        return result;
    }
    const auto ym2612_clock = u32(0x2c);
    if (!(ym2612_clock & 0x3fffffffu) || (ym2612_clock & 0x40000000u)) {
        result.detail = "missing or dual YM2612 clock";
        return result;
    }

    // A Mega Drive preparation candidate may declare only YM2612. Header
    // fields overlapped by an early data start are absent, as in classify_bytes.
    static const unsigned non_md_clock_offsets[] = {
        0x10, 0x30, 0x38, 0x40, 0x44, 0x48, 0x4c, 0x50, 0x54, 0x58,
        0x5c, 0x60, 0x64, 0x68, 0x6c, 0x70, 0x74, 0x80, 0x84, 0x88,
        0x8c, 0x90, 0x98, 0x9c, 0xa0, 0xa4, 0xa8, 0xac, 0xb0, 0xb4,
        0xb8, 0xc0, 0xc4, 0xc8, 0xcc, 0xd0, 0xd8, 0xdc, 0xe0,
    };
    for (unsigned offset : non_md_clock_offsets) {
        if (std::uint64_t(offset) + 4 <= data && u32(offset)) {
            result.detail = "non-Mega-Drive header clock is present";
            return result;
        }
    }

    // These fields are available from VGM 1.10. Requiring the known Mega
    // Drive PSG shape makes the fixed 3.579545 MHz repair conservative.
    if (version >= 0x110 &&
        ((u32(0x28) & 0xffffu) != 0x0009u || bytes[0x2a] != 16u)) {
        result.detail = "SN76489 metadata is not Mega Drive compatible";
        return result;
    }
    if (version <= 0x151 && bytes[0x2b] != 0) {
        result.detail = "SN76489 flags are invalid for this VGM version";
        return result;
    }

    const auto original = classify_bytes(bytes);
    if (original.profile != Profile::Error ||
        original.detail != "used chip has no header clock") {
        result.detail = "strict classifier did not report the expected clock error";
        return result;
    }

    std::vector<unsigned char> normalized(bytes);
    constexpr std::uint32_t kMegaDriveSn76489Clock = 3579545u;
    for (unsigned i = 0; i < 4; ++i)
        normalized[0x0c+i] = static_cast<unsigned char>(kMegaDriveSn76489Clock >> (8*i));
    const auto classified = classify_bytes(normalized);
    if (classified.profile != Profile::A || classified.sound_chips != "PSG,YM2612") {
        result.detail = "normalized view is not an unambiguous PSG,YM2612 Profile A VGM";
        return result;
    }

    bytes.swap(normalized);
    result.applied = true;
    result.detail = "PSG commands present in validated Mega Drive profile";
    return result;
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
    Classification result = classify_bytes(bytes);
    // Package hardware metadata refines display evidence only. It must never
    // participate in the Profile A/B acceptance or switching decision.
    if (result.profile == Profile::B &&
        (result.sound_chips == "YM2610" || result.sound_chips == "YM2610B")) {
        const auto declared = declared_sound_chip(p, r);
        if (!declared.empty()) result.sound_chips = declared;
    }
    return result;
}

Classification inspect_raw_sid_for_prepare(const std::string &path,
        const std::string &root) {
    Classification result;
    auto fail = [&](const std::string &detail) {
        result.profile = Profile::Error; result.detail = detail; return result;
    };
    if (path.size() <= 4 || path.compare(path.size()-4,4,".sid") != 0)
        return fail("not a raw .sid path");
    char canonical[PATH_MAX], base[PATH_MAX];
    if (!realpath(root.c_str(), base) || !realpath(path.c_str(), canonical))
        return fail(std::strerror(errno));
    const std::string p(canonical), r(base);
    if (p.compare(0, r.size()+1, r+"/") != 0 || p.find_first_of("\r\n") != std::string::npos)
        return fail("raw SID path outside approved root");
    const int fd = open(p.c_str(), O_RDONLY|O_NOFOLLOW|O_CLOEXEC|O_NONBLOCK);
    if (fd < 0) return fail(std::strerror(errno));
    struct stat st = {}; unsigned char h[124] = {}; std::size_t got = 0;
    bool ok = !fstat(fd,&st) && S_ISREG(st.st_mode) && st.st_size >= 0x76 &&
        st.st_size <= 16*1024*1024;
    while (ok && got < sizeof(h)) {
        const auto n = read(fd,h+got,sizeof(h)-got);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) break;
        got += static_cast<std::size_t>(n);
    }
    close(fd);
    if (!ok || got < 0x76) return fail("malformed/raw SID file bounds");
    const bool psid = !std::memcmp(h,"PSID",4), rsid = !std::memcmp(h,"RSID",4);
    if (!psid && !rsid) return fail("raw SID magic is not PSID/RSID");
    auto be16 = [&](unsigned n) { return unsigned(h[n])<<8 | h[n+1]; };
    const unsigned version=be16(4), offset=be16(6), songs=be16(14), start=be16(16);
    if (version < 1 || version > 4 || offset < (version == 1 ? 0x76u : 0x7cu) ||
        offset > static_cast<unsigned long>(st.st_size) || !songs || !start || start > songs)
        return fail("unsupported raw SID version/header/song fields");
    if (version < 2) return fail("raw SID v1 cannot carry model/timing metadata");
    if (got < 0x7c) return fail("truncated raw SID v2+ header");
    const unsigned flags=be16(0x76), timing=(flags>>2)&3u, model=(flags>>4)&3u;
    if ((version >= 3 && h[0x7a]) || (version >= 4 && h[0x7b]))
        return fail("raw multi-SID is unsupported");
    result.profile=Profile::C;
    result.detail="raw SID admitted for preparation only";
    if (model==1 || model==2) {
        result.sound_chips=model==1?"SID 6581":"SID 8580";
        result.sid.model=model==1?"6581":"8580";
    }
    if (timing==1 || timing==2) result.sid.timing=timing==1?"PAL":"NTSC";
    result.sid.subtune=start;
    return result;
}
}
