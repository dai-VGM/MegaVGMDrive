#include "test_profile.h"
#include <cerrno>
#include <cstring>
#include <cstdio>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

namespace megavgm_supervisor {
namespace {
OperationResult error(const std::string &what) {
	return OperationResult::failure(what + ": " + std::strerror(errno));
}
OperationResult production_default(Paths &paths) {
#ifdef MEGAVGM_PHASE2A
	paths.phase2a = true;
	paths.rbf_profile = "PHASE2A_AUTO";
	paths.playlist_binary = "/media/fat/MegaVGMPlayer/megavgm_playlist-phase2a";
#else
	(void)paths;
#endif
	return OperationResult::success();
}
bool known(const std::string &name) {
#ifdef MEGAVGM_PHASE2A
	if (name == "phase2a") return true;
#endif
	return name == "default" || name == "ym2610b-phase1b" ||
	       name == "fade-only-a" || name == "fade-only-b";
}
int open_directory(const Paths &paths, bool create) {
	if (create && mkdir(paths.test_profile_directory.c_str(), 0700) < 0 && errno != EEXIST)
		return -1;
	const int fd = open(paths.test_profile_directory.c_str(), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
	if (fd < 0) return -1;
	struct stat st = {};
	if (fstat(fd, &st) < 0 || st.st_uid != geteuid() || (st.st_mode & 0077)) {
		close(fd); errno = EPERM; return -1;
	}
	return fd;
}
}

OperationResult apply_test_profile(Paths &paths) {
	const int dir = open_directory(paths, false);
	if (dir < 0) return errno == ENOENT ? production_default(paths) : error("test-profile directory");
	const int fd = openat(dir, "profile", O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC);
	const int saved = errno;
	close(dir);
	if (fd < 0) { errno = saved; return errno == ENOENT ? production_default(paths) : error("test-profile open"); }
	struct stat st = {};
	if (fstat(fd, &st) < 0 || !S_ISREG(st.st_mode) || st.st_uid != geteuid() ||
	    (st.st_mode & 0077) || st.st_size < 1 || st.st_size > 64) {
		close(fd); return OperationResult::failure("invalid test-profile file");
	}
	std::string record;
	char buffer[65];
	for (;;) {
		const ssize_t n = read(fd, buffer, sizeof(buffer));
		if (n < 0 && errno == EINTR) continue;
		if (n < 0) { const auto result = error("test-profile read"); close(fd); return result; }
		if (!n) break;
		record.append(buffer, static_cast<std::size_t>(n));
		if (record.size() > 64) break;
	}
	close(fd);
	if (false) {}
#ifdef MEGAVGM_PHASE2A
	else if (record == "phase2a\n") {
		return production_default(paths);
	}
#endif
	else if (record == "ym2610b-phase1b\n") {
		paths.rbf = "/media/fat/MegaVGMPlayer/MegaVGMPlayer_GoldenTransport12Phase1B_YM2610B_MiSTer.rbf";
		paths.rbf_profile = "YM2610B_PHASE1B";
	} else if (record == "fade-only-a\n") {
		paths.rbf = "/media/fat/_Utility/MegaVGMPlayer_Transport13FadeOnly_A_MiSTer.rbf";
		paths.rbf_profile = "FADE_ONLY_A";
	} else if (record == "fade-only-b\n") {
		paths.rbf = "/media/fat/_Utility/MegaVGMPlayer_Transport13FadeOnly_B_MiSTer.rbf";
		paths.rbf_profile = "FADE_ONLY_B";
	} else return OperationResult::failure("unknown test-profile record");
	// Fixed-resident lab overrides retain the legacy controller, even when
	// reusing a Paths value which previously selected the production route.
	paths.phase2a = false;
	paths.playlist_binary = "/media/fat/Scripts/megavgm_playlist";
	return OperationResult::success();
}

OperationResult set_test_profile(const Paths &paths, const std::string &name) {
	if (!known(name)) return OperationResult::failure("unknown test-profile; use default, ym2610b-phase1b, fade-only-a or fade-only-b");
	// Same flock as ENTER: cannot select while an owner is starting/running/draining.
	InstanceLock lock;
	auto result = lock.acquire(paths.supervisor_lock);
	if (!result.ok) return result;
	struct stat status = {};
	if (lstat(paths.supervisor_status.c_str(), &status) == 0) {
		std::string content, detail;
		if (!read_text_file(paths.supervisor_status, content, detail) || !status_is_stock(content))
			return OperationResult::failure("test-profile requires STOCK; Exit first");
	} else if (errno != ENOENT) return error("supervisor status");
	const int dir = open_directory(paths, name != "default");
	if (dir < 0) return name == "default" && errno == ENOENT ? OperationResult::success() : error("test-profile directory");
	if (name == "default") {
		const int removed = unlinkat(dir, "profile", 0);
		const int saved = errno;
		close(dir);
		if (removed < 0 && saved != ENOENT) { errno = saved; return error("clear test-profile"); }
		return OperationResult::success();
	}
	const std::string temporary = ".profile." + std::to_string(getpid());
	const int fd = openat(dir, temporary.c_str(), O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
	if (fd < 0) { result = error("create test-profile"); close(dir); return result; }
	const std::string record = name + "\n";
	std::size_t offset = 0;
	while (offset < record.size()) {
		const ssize_t n = write(fd, record.data()+offset, record.size()-offset);
		if (n < 0 && errno == EINTR) continue;
		if (n <= 0) { result = error("write test-profile"); break; }
		offset += static_cast<std::size_t>(n);
	}
	if (result.ok && fsync(fd) < 0) result = error("sync test-profile");
	if (close(fd) < 0 && result.ok) result = error("close test-profile");
	if (result.ok && renameat(dir, temporary.c_str(), dir, "profile") < 0) result = error("publish test-profile");
	if (!result.ok) unlinkat(dir, temporary.c_str(), 0);
	close(dir);
	return result;
}
} // namespace megavgm_supervisor
