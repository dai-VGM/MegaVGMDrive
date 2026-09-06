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
    if (!r.stop && r.profile != Profile::A && r.profile != Profile::B) return fail("classification failure");
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
    if (r.stop && !stopping_) {
        if (!host_.stop(detail)) return fail("stop: " + detail);
        stopping_ = true;
        return reply_;
    }
    if (stopping_ && s.state != PlaybackState::Idle) return reply_;
    if (!stopping_ && s.session != old_session_) return fail("old session ownership changed");
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
        magic != "MGS1" || profile < 0 || profile > 4 || stop > 1 || !r.generation || !finish(s)) {
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
          std::quoted(r.state) >> std::quoted(r.detail)) || magic != "MGR1" || profile < 0 || profile > 4 || !finish(s)) {
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
bool FileClient::load_acknowledged(const Reply &lease, const std::string &path, std::string &d) {
    Reply current;
    if (!read_reply(directory_, current, d) || current.state != "READY" ||
        current.generation != lease.generation || current.domain != lease.domain || current.profile != lease.profile ||
        current.main_identity != lease.main_identity) return false;
    const int pid = std::atoi(lease.main_identity.c_str());
    if (pid <= 0 || process_identity(pid) != lease.main_identity) return false;
    std::ifstream f(acknowledgment_);
    std::string line, phase, gen, observed_path, index, generation_valid, publisher_pid;
    while (std::getline(f, line)) {
        if (line.compare(0,6,"phase=")==0) phase=line.substr(6);
        if (line.compare(0,11,"generation=")==0) gen=line.substr(11);
        if (line.compare(0,5,"path=")==0) observed_path=line.substr(5);
        if (line.compare(0,6,"index=")==0) index=line.substr(6);
        if (line.compare(0,17,"generation_valid=")==0) generation_valid=line.substr(17);
        if (line.compare(0,4,"pid=")==0) publisher_pid=line.substr(4);
    }
    return generation_valid == "1" && publisher_pid == std::to_string(pid) &&
        gen == std::to_string(lease.generation) && observed_path == path && index == "1" &&
        (phase == "TRANSFER_SUCCESS" || phase == "SESSION_OBSERVED");
}
}
