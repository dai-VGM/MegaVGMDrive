#include "switch.h"
#include <cerrno>
#include <cstring>
#include <cstdlib>
#include <fcntl.h>
#include <fstream>
#include <iomanip>
#include <sstream>
#include <sys/stat.h>
#include <unistd.h>

namespace megavgm_profile {
using megavgm_autoplay2::PlaybackState;
Reply SwitchOwner::tick(const Request &r) {
    if (!r.generation || r.generation < reply_.generation) return reply_;
    if (!pending_ && r.generation == reply_.generation) return reply_;
    if (failed_) return reply_;
    auto fail = [&](const std::string &d) {
        reply_.generation = r.generation; reply_.state = "FAILED"; reply_.detail = d;
        failed_ = true; pending_ = false; return reply_;
    };
    std::string detail;
    if (!r.stop && r.profile != Profile::A && r.profile != Profile::B &&
        r.profile != Profile::C && r.profile != Profile::D && r.profile != Profile::E && r.profile != Profile::F)
        return fail("classification failure");
    if (!pending_) {
        old_session_ = r.session;
        if (r.domain != domain_ && !(r.domain == 0 && reply_.generation == 0)) {
            // READY can be published just before a new user intent reaches the
            // controller. Until that lease is consumed it still knows the old
            // domain. Allow superseding only an UNUSED grant: same verified
            // successor, exactly the granted baseline, no new index-1 session.
            megavgm_autoplay2::PlaybackStatus current;
            if ((reply_.state != "READY" && reply_.state != "STOPPED") ||
                r.domain != grant_source_domain_ || !host_.status(current, detail) ||
                current.session != reply_.baseline || host_.main_identity() != reply_.main_identity)
                return fail("stale resident domain");
            old_session_ = current.session;
        }
        pending_ = true; deadline_ = host_.now() + 60000;
        old_main_ = host_.main_identity();
        if (old_main_.empty()) return fail("no verified Main identity");
    }
    reply_.generation = r.generation; reply_.state = "PARKED";
    reply_.domain = domain_; reply_.profile = resident_;
    if (host_.now() > deadline_) return fail("profile transaction timeout");
    megavgm_autoplay2::PlaybackStatus s;
    if (!host_.status(s, detail)) return fail("status: " + detail);
    if (s.version != 2) return fail("status v2 required");
    if (host_.main_identity() != old_main_) return fail("Main changed outside switch owner");
    if (s.error || s.state == PlaybackState::Fatal) return fail("current RBF FATAL");
    if (s.session != old_session_) return fail("old session ownership changed");
    if (r.stop && !stopping_ && s.state != PlaybackState::Ended && s.state != PlaybackState::Idle) {
        if (!host_.stop(detail)) return fail("stop: " + detail);
        stopping_ = true;
        return reply_;
    }
    if (stopping_ && s.state != PlaybackState::Ended) return reply_;
    if (!r.stop && resident_ != r.profile && !ending_ && !stopping_) {
        if (s.state == PlaybackState::Playing) {
            if (!host_.fade(detail)) return fail("FADE_ONLY: " + detail);
            ending_ = true;
            return reply_;
        }
        if (s.state != PlaybackState::Ended && s.state != PlaybackState::Idle)
            return fail("switch requested outside owned PLAYING/ENDED/IDLE");
    }
    // A newer selection can supersede the target, not restart the old fade.
    if (ending_ && !stopping_ && s.state != PlaybackState::Ended) return reply_;
    if (!r.stop && resident_ != r.profile) {
        if (!host_.replace(r.profile, detail)) return fail("RBF switch: " + detail);
        resident_ = r.profile; ++domain_;
        old_main_ = host_.main_identity();
        if (old_main_.empty() || !host_.status(s, detail) || s.state != PlaybackState::Idle || s.error)
            return fail("no fresh successor IDLE baseline");
        old_session_ = s.session;
        ending_ = stopping_ = false;
        // Re-read latest request on the next tick BEFORE granting any load.
        // replace() may have taken seconds while the controller accepted input.
        return reply_;
    }
    reply_.domain = domain_; reply_.profile = resident_; reply_.baseline = s.session;
    reply_.main_identity = old_main_; reply_.state = r.stop ? "STOPPED" : "READY";
    grant_source_domain_ = r.domain;
    reply_.detail.clear(); pending_ = ending_ = stopping_ = false;
    return reply_;
}

namespace {
int directory_fd(const std::string &p) {
    const int fd = open(p.c_str(), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (fd < 0) return -1;
    struct stat s = {};
    if (fstat(fd, &s) || s.st_uid != geteuid() || (s.st_mode & 077)) {
        close(fd); errno = EPERM; return -1;
    }
    return fd;
}
bool record(const std::string &dir, const char *name, std::string &text, bool writing, std::string &d) {
    d.clear();
    const int folder = directory_fd(dir);
    if (folder < 0) { d = std::strerror(errno); return false; }
    const std::string temp = std::string(name) + "." + std::to_string(getpid()) + ".tmp";
    const int fd = openat(folder, writing ? temp.c_str() : name,
        (writing ? O_WRONLY | O_CREAT | O_EXCL : O_RDONLY | O_NONBLOCK) | O_NOFOLLOW | O_CLOEXEC, 0600);
    if (fd < 0) {
        if (writing || errno != ENOENT) d = std::strerror(errno);
        close(folder); return false;
    }
    struct stat s = {};
    bool ok = !fstat(fd, &s) && S_ISREG(s.st_mode) && s.st_uid == geteuid() && !(s.st_mode & 077);
    if (writing) {
        std::size_t pos = 0;
        while (ok && pos < text.size()) {
            const auto n = write(fd, text.data()+pos, text.size()-pos);
            if (n < 0 && errno == EINTR) continue;
            if (n <= 0) { ok = false; break; }
            pos += n;
        }
        if (ok) ok = !fsync(fd);
    } else {
        ok = ok && s.st_size > 0 && s.st_size <= 8192;
        text.clear(); char b[8193];
        while (ok) {
            const auto n = read(fd, b, sizeof(b));
            if (n < 0 && errno == EINTR) continue;
            if (n < 0) { ok = false; break; }
            if (!n) break;
            text.append(b, n);
            if (text.size() > 8192) ok = false;
        }
    }
    if (close(fd)) ok = false;
    if (writing && ok) ok = !renameat(folder, temp.c_str(), folder, name);
    if (writing && !ok) unlinkat(folder, temp.c_str(), 0);
    close(folder);
    if (!ok) d = "invalid/failed atomic channel record";
    return ok;
}
bool finish(std::istringstream &s) { s >> std::ws; return s.eof() && !s.bad(); }
}
bool make_channel(std::string &dir, std::string &d) {
    char pattern[] = "/tmp/megavgm-phase2a.XXXXXX";
    const char *p = mkdtemp(pattern);
    if (!p) { d = std::strerror(errno); return false; }
    dir = p; return true;
}
bool write_request(const std::string &dir, const Request &r, std::string &d) {
    std::ostringstream s;
    s << "MGS1 " << r.generation << ' ' << r.domain << ' ' << r.session << ' '
      << int(r.profile) << ' ' << r.stop << ' ' << std::quoted(r.path) << '\n';
    auto text = s.str(); return record(dir, "request", text, true, d);
}
bool read_request(const std::string &dir, Request &r, std::string &d) {
    std::string text, magic; int profile; unsigned stop;
    if (!record(dir, "request", text, false, d)) return false;
    std::istringstream s(text);
    if (!(s >> magic >> r.generation >> r.domain >> r.session >> profile >> stop >> std::quoted(r.path)) ||
        magic != "MGS1" || profile < 0 || profile > 8 || stop > 1 || !r.generation || !finish(s)) {
        d = "malformed switch request"; return false;
    }
    r.profile = static_cast<Profile>(profile); r.stop = stop; return true;
}
bool write_reply(const std::string &dir, const Reply &r, std::string &d) {
    std::ostringstream s;
    s << "MGR1 " << r.generation << ' ' << r.domain << ' ' << r.baseline << ' ' << int(r.profile) << ' '
      << std::quoted(r.main_identity) << ' ' << std::quoted(r.state) << ' ' << std::quoted(r.detail) << '\n';
    auto text = s.str(); return record(dir, "reply", text, true, d);
}
bool read_reply(const std::string &dir, Reply &r, std::string &d) {
    std::string text, magic; int profile;
    if (!record(dir, "reply", text, false, d)) return false;
    std::istringstream s(text);
    if (!(s >> magic >> r.generation >> r.domain >> r.baseline >> profile >> std::quoted(r.main_identity) >>
          std::quoted(r.state) >> std::quoted(r.detail)) || magic != "MGR1" || profile < 0 || profile > 8 || !finish(s)) {
        d = "malformed switch reply"; return false;
    }
    r.profile = static_cast<Profile>(profile); return true;
}
std::string process_identity(int pid) {
    std::ifstream f("/proc/" + std::to_string(pid) + "/stat");
    std::string line; std::getline(f, line);
    const auto end = line.find_last_of(')');
    if (end == std::string::npos) return {};
    std::istringstream fields(line.substr(end+1));
    std::string value;
    for (unsigned field = 3; field <= 22; ++field) if (!(fields >> value)) return {};
    struct stat exe = {};
    if (stat(("/proc/" + std::to_string(pid) + "/exe").c_str(), &exe)) return {};
    return std::to_string(pid) + ":" + value + ":" + std::to_string(exe.st_dev) + ":" + std::to_string(exe.st_ino);
}
namespace {
struct UploadReceipt {
    std::uint64_t version=0, pid=0, sequence=0, valid=0, generation=0, index=0;
    std::string phase, path;
};
bool number(const std::string &text, std::uint64_t &n) {
    if (text.empty() || text.find_first_not_of("0123456789") != std::string::npos) return false;
    std::istringstream in(text); in >> n; return !in.fail() && in.eof();
}
bool receipt(const std::string &path, UploadReceipt &r) {
    struct stat st={};
    if (lstat(path.c_str(), &st) || !S_ISREG(st.st_mode) || st.st_size<=0 || st.st_size>8192) return false;
    std::ifstream f(path); std::string line; unsigned seen=0;
    while (std::getline(f,line)) {
        auto at=line.find('='); if(at==std::string::npos) return false;
        const auto key=line.substr(0,at), value=line.substr(at+1); unsigned bit=0; bool ok=true;
        if(key=="version") {bit=1;ok=number(value,r.version);}
        else if(key=="pid") {bit=2;ok=number(value,r.pid);}
        else if(key=="command_seq") {bit=4;ok=number(value,r.sequence);}
        else if(key=="generation_valid") {bit=8;ok=number(value,r.valid);}
        else if(key=="generation") {bit=16;ok=number(value,r.generation);}
        else if(key=="index") {bit=32;ok=number(value,r.index);}
        else if(key=="phase") {bit=64;r.phase=value;}
        else if(key=="path") {bit=128;r.path=value;}
        else return false;
        if(!ok || (seen&bit)) return false;
        seen|=bit;
    }
    return f.eof() && !f.bad() && seen==255 && r.version==2 && r.sequence && r.valid<=1;
}
bool same_lease(const Reply &a, const Reply &b) {
    return a.generation==b.generation && a.domain==b.domain && a.baseline==b.baseline &&
        a.profile==b.profile && a.main_identity==b.main_identity;
}
}
bool FileClient::live_lease(const Reply &lease, std::string &d) {
    Reply current;
    if (lease.state!="READY" || !read_reply(directory_,current,d) ||
        current.state!="READY" || !same_lease(current,lease)) {d="READY lease changed";return false;}
    const int pid=std::atoi(lease.main_identity.c_str());
    if(pid<=0 || process_identity(pid)!=lease.main_identity) {d="Main process identity changed";return false;}
    return true;
}
bool FileClient::begin(const Request &r, std::string &d) {
    forget_session();
    struct stat channel = {};
    if (lstat(directory_.c_str(), &channel) || !S_ISDIR(channel.st_mode) ||
        (channel_pinned_ && (channel_device_ != static_cast<std::uint64_t>(channel.st_dev) ||
                            channel_inode_ != static_cast<std::uint64_t>(channel.st_ino)))) {
        d = "private channel epoch changed"; return false;
    }
    channel_device_ = channel.st_dev; channel_inode_ = channel.st_ino; channel_pinned_ = true;
    return write_request(directory_, r, d);
}
bool FileClient::owns_parked(const Reply &lease, std::string &d) {
    struct stat channel = {};
    if (!channel_pinned_ || lstat(directory_.c_str(), &channel) ||
        channel_device_ != static_cast<std::uint64_t>(channel.st_dev) ||
        channel_inode_ != static_cast<std::uint64_t>(channel.st_ino) ||
        !Client::owns_parked(lease, d) ||
        process_identity(std::atoi(lease.main_identity.c_str())) != lease.main_identity) {
        d = "parked Main/lease/epoch changed"; return false;
    }
    return true;
}
bool FileClient::load_acknowledged(const Reply &lease, const std::string &path, std::string &d) {
    if(!live_lease(lease,d)) return false;
    UploadReceipt r;
    if(!receipt(acknowledgment_,r) || r.valid!=1 || r.pid!=static_cast<unsigned>(std::atoi(lease.main_identity.c_str())) ||
       r.generation!=lease.generation || r.path!=path || r.index!=1 ||
       (r.phase!="TRANSFER_SUCCESS" && r.phase!="SESSION_OBSERVED")) return false;
    struct stat epoch={};
    if(lstat(directory_.c_str(),&epoch) || !S_ISDIR(epoch.st_mode)) return false;
    proof_lease_=lease;proof_path_=path;proof_sequence_=r.sequence;
    proof_device_=epoch.st_dev;proof_inode_=epoch.st_ino;
    proof_valid_=true;policy_allowed_=false;
    return true;
}
bool FileClient::owns_session(const Reply &lease,const std::string &path,
    const megavgm_autoplay2::PlaybackStatus &status,std::string &d) {
    auto reject=[&](const char *reason){d=reason;forget_session();return false;};
    if(!proof_valid_ || !same_lease(proof_lease_,lease) || proof_path_!=path)
        return reject("accepted upload proof missing/changed");
    if(status.version!=2 || status.error || status.state!=megavgm_autoplay2::PlaybackState::Playing ||
       status.session!=static_cast<std::uint32_t>(lease.baseline+1u))
        return reject("owned PLAYING session changed");
    struct stat epoch={};
    if(lstat(directory_.c_str(),&epoch) || !S_ISDIR(epoch.st_mode) ||
       static_cast<std::uint64_t>(epoch.st_dev)!=proof_device_ ||
       static_cast<std::uint64_t>(epoch.st_ino)!=proof_inode_)
        return reject("private channel epoch changed");
    if(!live_lease(lease,d)) {forget_session();return false;}
    UploadReceipt r;
    if(!receipt(acknowledgment_,r) || r.pid!=static_cast<unsigned>(std::atoi(lease.main_identity.c_str())))
        return reject("latest Main receipt invalid");
    // The accepted upload stays immutable. A newer index1, unknown transfer or
    // failed transfer cannot be treated as our continuing session.
    const bool original=r.index==1 && r.sequence==proof_sequence_ && r.valid==1 &&
        r.generation==lease.generation && r.path==path &&
        (r.phase=="TRANSFER_SUCCESS" || r.phase=="SESSION_OBSERVED");
    const bool policy=policy_allowed_ && r.index==2 && r.sequence>proof_sequence_ &&
        r.valid==0 && r.generation==0 && r.path=="/tmp/megavgm_transition.control" &&
        (r.phase=="PARSED" || r.phase=="TRANSFER_ENTERED" || r.phase=="TRANSFER_SUCCESS");
    if(!original && !policy) return reject("foreign/failed transfer after accepted upload");
    return true;
}
}
