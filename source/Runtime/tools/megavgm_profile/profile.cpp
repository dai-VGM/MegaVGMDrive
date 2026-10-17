#include "profile.h"
#include <algorithm>
#include <array>
#include <bitset>
#ifdef MEGAVGM_CAPACITY_AUDIT_TRACE
#include <cstdio>
#endif
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
// Pinned A resident capability: 2KiB pages /192 slots. The Package RBF
// binding gate verifies the exact FPGA profile; this is not declared ROM size.
struct KResidentAudit {
    struct Write { std::uint32_t pc; unsigned char address, data; };
    struct Voice { std::uint32_t start = 0; unsigned length = 0;
        std::uint32_t audited_start = 0; unsigned audited_length = 0;
        bool valid = false, reverse = false; };
    std::array<Voice, 4> voices{};
    std::bitset<1024> pages{};
    unsigned count = 0, keys = 0;
#ifdef MEGAVGM_CAPACITY_AUDIT_TRACE
    // Nonproduction comparator observer. Never compiled into packaged binaries.
    std::FILE *trace = std::getenv("MEGAVGM_CAPACITY_TRACE") ?
        std::fopen(std::getenv("MEGAVGM_CAPACITY_TRACE"), "wb") : nullptr;
    ~KResidentAudit() { if (trace) std::fclose(trace); }
#endif
    bool write(unsigned address, unsigned value) {
        // Pitch/volume/panning writes cannot change an audited ROM envelope.
        // Every envelope-changing write below completes all active audits before
        // the next call; a failure terminates admission, so no debt is skipped.
        if (address != 40 && (address < 8 || address > 39 ||
                (address & 7) < 2 || (address & 7) > 6)) return true;
        if (address >= 8 && address <= 39) {
            auto &v = voices[(address - 8) >> 3];
            switch (address & 7) {
            case 2: v.length = (v.length & 0xff00) | value; break;
            case 3: v.length = (v.length & 0xff) | (value << 8); break;
            case 4: v.start = (v.start & 0x1fff00) | value; break;
            case 5: v.start = (v.start & 0x1f00ff) | (value << 8); break;
            case 6: v.start = (v.start & 0xffff) | ((value & 31) << 16); break;
            default: break;
            }
        }
        if (address == 40) keys = value;
        for (unsigned n = 0; n != 4; ++n) {
            auto &v = voices[n]; const bool reverse = (keys & (16u << n)) != 0;
            if (!(keys & (1u << n))) continue;
            if (v.valid && v.audited_start == v.start &&
                v.audited_length == v.length && v.reverse == reverse) continue;
            const unsigned endpoint = (reverse ? v.start - v.length :
                v.start + v.length) & 0x1fffffu;
            unsigned cursor = v.start >> 11; const unsigned last = endpoint >> 11;
            for (;;) {
                if (!pages[cursor]) {
                    if (++count > 192) return false;
                    pages.set(cursor);
                }
                if (cursor == last) break;
                cursor = (cursor + (reverse ? 1023u : 1u)) & 1023u;
            }
            v.audited_start = v.start; v.audited_length = v.length;
            v.reverse = reverse; v.valid = true;
        }
        return true;
    }
};

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
    case Profile::E: return "SUPPORTED_PROFILE_E";
    case Profile::F: return "SUPPORTED_PROFILE_F";
    case Profile::Unsupported: return "UNSUPPORTED";
    case Profile::Ambiguous: return "AMBIGUOUS";
    default: return "ERROR";
    }
}
const char *rbf(Profile p) {
    return p == Profile::A ? "/media/fat/_Custom Cores/Cores/MegaVGMDrive_A.rbf" :
        p == Profile::B ? "/media/fat/_Custom Cores/Cores/MegaVGMDrive_B.rbf" :
        p == Profile::C ? "/media/fat/_Custom Cores/Cores/MegaVGMDrive_C.rbf" :
        p == Profile::D ? "/media/fat/_Custom Cores/Cores/MegaVGMDrive_D.rbf" :
        p == Profile::E ? "/media/fat/_Custom Cores/Cores/MegaVGMDrive_E_vNext_MiSTer.rbf" :
        p == Profile::F ? "/media/fat/_Custom Cores/Cores/MegaVGMDrive_F_vNext_MiSTer.rbf" : "";
}
const char *status_name(Profile p) {
    return p==Profile::A?"PROFILE_A":p==Profile::B?"PROFILE_B":
        p==Profile::C?"PROFILE_C":p==Profile::D?"PROFILE_D":p==Profile::E?"PROFILE_E":p==Profile::F?"PROFILE_F":"UNKNOWN";
}
// Container preflight only. The preparation provider validates metadata and
// serializes the sole NSF1 execution image before any index-1 upload.
static Classification classify_native(const std::vector<unsigned char> &source) {
    Classification r;
    const auto reject = [&](const char *why) { r.profile=Profile::Unsupported; r.detail=why; return r; };
    auto b=source;
    if (b.size()>2*1024*1024) return reject("native container limit");
    if (b.size()>=4 && std::equal(b.begin(),b.begin()+4,"NSFE")) {
        std::vector<unsigned char> info,data,bank,rate;
        std::vector<std::string> seen;
        bool have_info=false,have_data=false,have_bank=false,ended=false;
        for (std::size_t n=4;n<b.size();) {
            if (b.size()-n<8) return reject("NSFe truncated chunk");
            const std::uint32_t size=std::uint32_t(b[n])|(std::uint32_t(b[n+1])<<8)|
                (std::uint32_t(b[n+2])<<16)|(std::uint32_t(b[n+3])<<24);
            const std::string tag(b.begin()+n+4,b.begin()+n+8);
            if (size>b.size()-n-8 || std::find(seen.begin(),seen.end(),tag)!=seen.end()) return reject("NSFe chunk extent/duplicate");
            seen.push_back(tag);
            const bool known=tag=="INFO"||tag=="DATA"||tag=="BANK"||tag=="RATE"||tag=="NEND";
            if (tag=="NSF2" || (tag[0]>='A' && tag[0]<='Z' && !known)) return reject("unsupported NSFe mandatory chunk");
            std::vector<unsigned char> part(b.begin()+n+8,b.begin()+n+8+size);
            if(tag=="INFO") {info=part;have_info=true;}
            if(tag=="DATA") {if(!have_info)return reject("DATA before INFO");data=part;have_data=true;}
            if(tag=="BANK") {bank=part;have_bank=true;}
            if(tag=="RATE") rate=part;
            n+=8+size;
            if(tag=="NEND") {ended=true;break;}
        }
        if(!ended||!have_info||!have_data||info.size()<9) return reject("NSFe missing INFO/DATA/NEND");
        b.assign(128,0);const unsigned char magic[5]={'N','E','S','M',26};std::copy(magic,magic+5,b.begin());
        b[5]=1;b[6]=info[8];b[7]=info.size()>9?unsigned(info[9])+1:1;
        std::copy(info.begin(),info.begin()+6,b.begin()+8);b[122]=info[6];b[123]=info[7];
        std::copy(bank.begin(),bank.begin()+std::min<std::size_t>(8,bank.size()),b.begin()+112);
        if(have_bank && std::all_of(b.begin()+112,b.begin()+120,[](unsigned char v){return v==0;})) return reject("allzero BANK cannot represent NSF1");
        if(!rate.empty() && rate.size()!=2 && rate.size()!=4 && rate.size()!=6) return reject("NSFe RATE length");
        if(!rate.empty())std::copy(rate.begin(),rate.begin()+2,b.begin()+110);
        if(rate.size()>=4)std::copy(rate.begin()+2,rate.begin()+4,b.begin()+120);
        b.insert(b.end(),data.begin(),data.end());
    }
    if(b.size()<=128||b.size()>262272||b[4]!=26||b[5]!=1) return reject("NSF1 header/extent");
    const auto word=[&](std::size_t n){return unsigned(b[n])|(unsigned(b[n+1])<<8);};
    if(!b[6]||!b[7]||b[7]>b[6]||b[122]|| (b[123]&~1u) ||word(8)<0x8000||word(10)<0x8000||word(12)<0x8000 ||
       std::any_of(b.begin()+124,b.begin()+128,[](unsigned char v){return v!=0;})) return reject("NSF1 region/CPU/bank/features");
    const bool banked=std::any_of(b.begin()+112,b.begin()+120,[](unsigned char v){return v!=0;});
    const auto extent=b.size()-128+(banked?(word(8)&4095):word(8)-0x8000);
    if(extent>262144||(!banked&&extent>32768)) return reject("resident memory extent");
    if(banked)for(unsigned n=112;n<120;++n)if(b[n]>=(extent+4095)/4096)return reject("initial bank mapping");
    r.profile=Profile::E;r.detail="NSF1 native execution; container preparation required";
    r.sound_chips=b[123]?"NES APU,VRC6":"NES APU";return r;
}

Classification classify_bytes(const std::vector<unsigned char> &b) {
    if (b.size()>=4 && (std::equal(b.begin(),b.begin()+4,"NSFE") || std::equal(b.begin(),b.begin()+4,"NESM"))) return classify_native(b);
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
    bool a = false, opb = false, c140_command = false, huc6280 = false;
    bool c140_block = false, end_seen = false, unsupported = false;
#if defined(MEGAVGM_HOST_MSM6295) && MEGAVGM_HOST_MSM6295
    constexpr bool msm_grammar = true;
#else
    constexpr bool msm_grammar = false;
#endif
#if defined(MEGAVGM_HOST_K053260) && MEGAVGM_HOST_K053260
    constexpr bool k_grammar = true;
#else
    constexpr bool k_grammar = false;
#endif
// New admission requires the separately built matching RTL candidate.
#if defined(MEGAVGM_HOST_K053260_EMPTY_ROM) && MEGAVGM_HOST_K053260_EMPTY_ROM
    constexpr bool k_empty_rom = true;
#else
    constexpr bool k_empty_rom = false;
#endif
#if defined(MEGAVGM_HOST_MSM6295_PCM_ONLY) && MEGAVGM_HOST_MSM6295_PCM_ONLY
    constexpr bool msm_pcm_only = true;
#else
    constexpr bool msm_pcm_only = false;
#endif
    bool k_write = false, k_rom = false, k_key = false;
    std::uint32_t k_rom_size = 0;
    unsigned k_blocks = 0;
    KResidentAudit k_audit;
    std::vector<KResidentAudit::Write> k_writes;
    std::size_t k_loop_write = 0;
    bool k_capacity_bad = false;
    const auto k_observe = [&](const KResidentAudit::Write &w, unsigned traversal) {
        if (k_capacity_bad) return;
        if (!k_audit.write(w.address, w.data)) {
            k_capacity_bad = true; r.resource_fault_pc = w.pc;
            r.resource_fault_traversal = traversal; return;
        }
#ifdef MEGAVGM_CAPACITY_AUDIT_TRACE
        if (k_audit.trace) {
            std::uint32_t record[14]{traversal,w.pc,0xba,w.address,w.data,k_audit.keys};
            for(unsigned v=0;v<4;++v){record[6+v]=k_audit.voices[v].start;record[10+v]=k_audit.voices[v].length;}
            if (std::fwrite(record,sizeof(record),1,k_audit.trace)!=1) std::abort();
        }
#endif
    };
    // Candidate admission facts only: original bytes still go to the same
    // FPGA Generic WRITE/DATA parser. No resource materialization or audio.
    bool msm_write = false, msm_rom = false, resources_closed = false;
    bool msm_prefix = false, msm_loop_entry = false;
    unsigned msm_bank = 0, msm_loop_bank = 0, initial_ym = 0;
    bool positive_wait = false;
    std::uint32_t msm_clock_buffer = clock(0x98) & 0x00ffffffu;
    struct MsmSpan { std::uint32_t begin, end, rom_size; };
    std::vector<MsmSpan> msm_spans;
    bool ym2610b_channel_used = false;
    unsigned used = 0;
    unsigned command_chips = 0;
    const std::uint64_t loop = u32(0x1c) ? std::uint64_t(u32(0x1c)) + 0x1c : 0;
    bool loop_seen = !loop;
    for (std::uint64_t pc = data; pc < end;) {
        if (pc == loop) {
            loop_seen = true;
            k_loop_write = 0;
            msm_loop_entry = true;
            msm_loop_bank = msm_bank;
        }
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
            else if (type == 0x8e && k_grammar) {
                a = true; used |= 128; k_rom = true;
                if (size > end - pc || length < 8)
                    return fail(Profile::Error, "truncated K053260 ROM block");
                const auto declared = u32(pc+7), begin = u32(pc+11);
                const std::uint64_t finish = std::uint64_t(begin) + length - 8;
                if (!declared || declared > 0x400000u || finish > declared ||
                    (k_rom_size && k_rom_size != declared))
                    return fail(Profile::Unsupported, "K053260 ROM span/declaration");
                if (length == 8 && !k_empty_rom)
                    return fail(Profile::Unsupported, "K053260 declaration-only ROM block unsupported by selected FPGA");
                if (k_key || (length != 8 && ++k_blocks > 32))
                    return fail(Profile::Unsupported, "K053260 late ROM/descriptor capacity");
                // Preserve literal overlays; FPGA page/voice admission remains
                // authoritative. Declared ROM is not resident allocation.
                k_rom_size = declared;
            }
            else if (type == 0x8b && msm_grammar) {
                msm_rom = true;
                if (size > end - pc || length < 8)
                    return fail(Profile::Error, "truncated MSM6295 ROM block");
                if (resources_closed)
                    return fail(Profile::Unsupported, "MSM6295 ROM after playback controls");
                const auto rom_size = u32(pc+7), begin = u32(pc+11);
                const std::uint64_t payload = length - 8;
                const std::uint64_t finish = std::uint64_t(begin) + payload;
                if (!rom_size || rom_size > 0x100000u || begin > rom_size || finish > rom_size)
                    return fail(Profile::Unsupported, "MSM6295 ROM span/capacity");
                // Empty declarations are metadata, not a resident descriptor.
                if (payload) {
                    if (msm_spans.size() == 16)
                        return fail(Profile::Unsupported, "MSM6295 descriptor capacity");
                    for (const auto &span : msm_spans) {
                        if (span.rom_size != rom_size)
                            return fail(Profile::Unsupported, "MSM6295 inconsistent ROM size");
                        if (begin < span.end && span.begin < finish)
                            return fail(Profile::Unsupported, "MSM6295 overlapping ROM spans");
                    }
                    msm_spans.push_back({begin, static_cast<std::uint32_t>(finish), rom_size});
                }
            }
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
        else if (c == 0xba && k_grammar) {
            size = 3;
            if (size > end - pc) return fail(Profile::Error, "truncated K053260 write");
            if (b[pc+1] >= 64)
                return fail(Profile::Unsupported, "K053260 register/second instance");
            a = true; used |= 128; command_chips |= 128; k_write = true;
            if (b[pc+1] == 0x28 && (b[pc+2] & 15)) k_key = true;
            const KResidentAudit::Write w{static_cast<std::uint32_t>(pc), b[pc+1], b[pc+2]};
            k_observe(w, 0);
            if (loop && pc >= loop) k_writes.push_back(w);
        }
        else if (c == 0xb8 && msm_grammar) {
            size = 3;
            if (size > end - pc) return fail(Profile::Error, "truncated MSM6295 write");
            const unsigned address = b[pc+1], value = b[pc+2];
            if (address & 0x80) return fail(Profile::Unsupported, "second MSM6295 instance");
            if (!(address == 0 || (address >= 8 && address <= 12) || address == 15))
                return fail(Profile::Unsupported, "unsupported MSM6295 register");
            msm_write = true;
            if (address == 0) {
                if (msm_prefix) msm_prefix = false;
                else if (value & 0x80) {
                    if (msm_spans.empty())
                        return fail(Profile::Unsupported, "MSM6295 start without resident ROM");
                    msm_prefix = true;
                }
            } else if (address >= 8 && address <= 10) {
                const unsigned shift = 8 * (address - 8);
                msm_clock_buffer = (msm_clock_buffer & ~(0xffu << shift)) | (value << shift);
            } else if (address == 11) {
                const auto next_clock = (std::uint32_t(value) << 24) | msm_clock_buffer;
                if (!next_clock || next_clock > 4000000u)
                    return fail(Profile::Unsupported, "unsupported MSM6295 clock update");
            } else if (address == 12 && value > 1)
                return fail(Profile::Unsupported, "unsupported MSM6295 pin7 update");
            else if (address == 15) {
                if (value > 1) return fail(Profile::Unsupported, "unsupported MSM6295 bank");
                msm_bank = value;
            }
        }
        else if (c == 0xb9) {
            size = 3;huc6280 = true;
            if (pc + size > end) return fail(Profile::Error, "truncated HuC6280 write");
            if (b[pc+1] > 9) return fail(Profile::Unsupported, "unsupported HuC6280 register/instance");
        }
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
        if (c == 0x54 && !positive_wait) ++initial_ym;
        const bool waited = c == 0x62 || c == 0x63 || (c >= 0x70 && c <= 0x7f) ||
            (c == 0x61 && le16(b, pc+1) != 0);
        positive_wait |= waited;
        // Match D PASS1: only ROM declarations before first positive wait/write.
        resources_closed |= waited || (c != 0x61 && c != 0x67);
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
    if (msm_write || msm_rom) {
        if (opb || huc6280 || (used & ~4u))
            return fail(Profile::Ambiguous, "MSM6295 stream uses another profile chip");
        if (version < 0x161 || data < 0x9c)
            return fail(Profile::Unsupported, "MSM6295 requires VGM1.61 header");
        if (data > 0x96 && b[0x96] > 1)
            return fail(Profile::Unsupported, "unsupported D C140 type");
        if (initial_ym > 256)
            return fail(Profile::Unsupported, "D initial YM2151 queue capacity");
        if (msm_write) {
            const auto msm_clock = clock(0x98), ym_clock = clock(0x30);
            // Bit31 is pin7, not a second instance; bit30 is dual chip.
            if (!(msm_clock & 0x3fffffffu) || (msm_clock & 0x3fffffffu) > 4000000u ||
                (msm_clock & 0x40000000u) ||
                ((!msm_pcm_only || (used & 4u)) && (!ym_clock || (ym_clock & 0xc0000000u))))
                return fail(Profile::Unsupported, "unsupported D MSM6295/YM2151 header clock");
            if (msm_prefix || (msm_loop_entry && msm_bank != msm_loop_bank))
                return fail(Profile::Unsupported, "MSM6295 incomplete pair or loop bank state");
        }
        if (used & 4u) {
            if (!(clock(0x30) & 0x3fffffffu) || (clock(0x30) & 0xc0000000u))
                return fail(Profile::Unsupported, "unsupported D YM2151 clock");
            r.sound_chips = "YM2151";
        }
        if (c140_command) {
            if (!c140_block || !(clock(0xa8) & 0x3fffffffu) || (clock(0xa8) & 0x40000000u))
                return fail(Profile::Unsupported, "unsupported D C140 resource/clock");
            if (!r.sound_chips.empty()) r.sound_chips += ',';
            r.sound_chips += "C140";
        } else if (c140_block)
            return fail(Profile::Unsupported, "C140 ROM without command usage");
        if (msm_write) {
            if (!r.sound_chips.empty()) r.sound_chips += ',';
            r.sound_chips += "MSM6295";
        }
        if (r.sound_chips.empty())
            return fail(Profile::Unsupported, "MSM6295 ROM without sound command usage");
        return fail(Profile::D, "D Generic MSM6295 WRITE/ROM admission; FPGA PASS1 remains authoritative");
    }
    if (huc6280) {
        if (a || opb || c140_command || c140_block)
            return fail(Profile::Ambiguous, "HuC6280 mixed with another profile");
        // Exact header admission of the fixed F candidate; no guessed clock.
        if (version < 0x161 || data < 0xa8 || clock(0xa4) != 3579545)
            return fail(Profile::Unsupported, "HuC6280 requires VGM1.61 single 3579545Hz clock");
        r.sound_chips = "HuC6280";
        return fail(Profile::F, "HuC6280 command usage");
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
    // Selected Engine A capability; no engine lifecycle or fallback.
#if defined(MEGAVGM_HOST_A_YM2151_4026987) && MEGAVGM_HOST_A_YM2151_4026987
    const bool a_ym_clock_supported = clock(0x30)==3579545u || clock(0x30)==4000000u || clock(0x30)==4026987u;
#else
    const bool a_ym_clock_supported = clock(0x30)==3579545u || clock(0x30)==4000000u;
#endif
    if ((used & 4u) && clock(0x30) && !a_ym_clock_supported)
        return fail(Profile::Unsupported, "A YM2151 clock unsupported by selected RBF capability");
    if (k_write || k_rom) {
        if (version < 0x161 || data < 0xb0 || !clock(0xac) ||
            clock(0xac) > 3579545u || (clock(0xac) & 0xc0000000u))
            return fail(Profile::Unsupported, "K053260 header/clock");
        if ((!k_write && !k_empty_rom) || !k_rom)
            return fail(Profile::Unsupported, "K053260 requires WRITE and ROM");
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
    if (command_chips & 128) {
        if (!r.sound_chips.empty()) r.sound_chips += ',';
        r.sound_chips += "K053260";
    }
    if (k_write || k_rom) {
        // Retain all carried traversals, independent of FPGA fixed-point exit.
        // Every retained tuple is from the fully validated immutable stream.
        if (loop) for (unsigned traversal = 1; traversal != 4 && !k_capacity_bad; ++traversal)
            for (std::size_t n = k_loop_write; n < k_writes.size() && !k_capacity_bad; ++n)
                k_observe(k_writes[n], traversal);
        r.required_pages = k_audit.count;
        for (unsigned page = 0; page != 1024; ++page)
            if (k_audit.pages[page]) r.resource_page_mask[page >> 6] |= std::uint64_t(1) << (page & 63);
        if (!k_capacity_bad) {
            if (k_empty_rom && k_audit.count != 0 && k_blocks == 0)
                return fail(Profile::Unsupported, "K053260 sample references without ROM data");
            if (k_audit.count == 0 && !k_empty_rom) return fail(Profile::Unsupported, "K053260 empty resident page plan");
            for (unsigned page = 0; page != 1024; ++page)
                if (k_audit.pages[page] && (page << 11) >= k_rom_size)
                    return fail(Profile::Unsupported, "K053260 resident page outside declared ROM");
        }
        if (k_capacity_bad) {
            r.resource_capacity_exceeded = true;
            return fail(Profile::Unsupported,
                "resource_capacity_exceeded: K053260 resident pages >192 (384KiB)");
        }
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
    if (fstat(fd, &st) || !S_ISREG(st.st_mode) || st.st_size < 4 || st.st_size > 64*1024*1024) {
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
