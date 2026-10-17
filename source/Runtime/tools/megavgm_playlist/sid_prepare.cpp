#include "sid_prepare.h"

#include <cerrno>
#include <csignal>
#include <cstring>
#include <dirent.h>
#include <fcntl.h>
#include <limits.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
#include <vector>
#include <sstream>

namespace megavgm_playlist {
namespace {

bool ends_with(const std::string &value, const char *suffix)
{
	const std::size_t length = std::strlen(suffix);
	return value.size() > length &&
		value.compare(value.size() - length, length, suffix) == 0;
}

bool is_cache_key(const std::string &value)
{
	if (value.size() != 64) return false;
	for (const char c : value)
		if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))) return false;
	return true;
}

void close_fd(int &fd)
{
	if (fd >= 0) close(fd);
	fd = -1;
}

void drain_fd(int fd, std::string &output)
{
	if (fd < 0 || output.size() >= 8192) return;
	char bytes[1024];
	for (;;) {
		const ssize_t count = read(fd, bytes, sizeof(bytes));
		if (count > 0) {
			const std::size_t room = 8192 - output.size();
			output.append(bytes, static_cast<std::size_t>(count) < room ?
				static_cast<std::size_t>(count) : room);
			continue;
		}
		if (count < 0 && errno == EINTR) continue;
		break;
	}
}

bool within(const std::string &root, const std::string &path)
{
	return path.compare(0, root.size() + 1, root + "/") == 0;
}

constexpr unsigned kTerminationGracePolls = 50;
constexpr long kTerminationPollNanoseconds = 10L * 1000L * 1000L;

bool reap_during_grace(pid_t child)
{
	for (unsigned attempt = 0; attempt < kTerminationGracePolls; ++attempt) {
		pid_t result;
		do result = waitpid(child, nullptr, WNOHANG); while (result < 0 && errno == EINTR);
		if (result == child || (result < 0 && errno == ECHILD)) return true;
		if (result < 0) return false;
		struct timespec delay = {0, kTerminationPollNanoseconds};
		while (nanosleep(&delay, &delay) < 0 && errno == EINTR) {}
	}
	return false;
}

void reap_blocking(pid_t child)
{
	pid_t result;
	do result = waitpid(child, nullptr, 0); while (result < 0 && errno == EINTR);
}

void append_detail(std::string &detail, const std::string &extra)
{
	if (extra.empty()) return;
	if (!detail.empty()) detail += "; ";
	detail += extra;
}

} // namespace

bool is_raw_sid_name(const std::string &name)
{
	return ends_with(name, ".sid");
}

bool is_native_container_name(const std::string &name)
{ return ends_with(name, ".nsf") || ends_with(name, ".nsfe"); }

PosixSidPreparer::PosixSidPreparer(std::string executable,
		std::string cache_root, std::string songlength_db, std::string prepared_extension, bool timing_receipt)
	: executable_(std::move(executable)), cache_root_(std::move(cache_root)),
	  songlength_db_(std::move(songlength_db)), prepared_extension_(std::move(prepared_extension)), timing_receipt_(timing_receipt)
{
}

PosixSidPreparer::~PosixSidPreparer()
{
	(void)cancel();
}

bool PosixSidPreparer::start(const std::string &source, std::string &detail)
{
	if (pid_ > 0) {
		detail = "SID prepare already active";
		return false;
	}
	timing_ = {};
 int output_pipe[2] = {-1, -1}, error_pipe[2] = {-1, -1};
	if (pipe(output_pipe) || pipe(error_pipe)) {
		detail = std::strerror(errno);
		close_fd(output_pipe[0]); close_fd(output_pipe[1]);
		close_fd(error_pipe[0]); close_fd(error_pipe[1]);
		return false;
	}
	const pid_t child = fork();
	if (child < 0) {
		detail = std::strerror(errno);
		close(output_pipe[0]); close(output_pipe[1]);
		close(error_pipe[0]); close(error_pipe[1]);
		return false;
	}
	if (child == 0) {
		dup2(output_pipe[1], STDOUT_FILENO);
		dup2(error_pipe[1], STDERR_FILENO);
		close(output_pipe[0]); close(output_pipe[1]);
		close(error_pipe[0]); close(error_pipe[1]);
		std::vector<char *> arguments;
		arguments.push_back(const_cast<char *>(executable_.c_str()));
		arguments.push_back(const_cast<char *>("--input"));
		arguments.push_back(const_cast<char *>(source.c_str()));
		arguments.push_back(const_cast<char *>("--cache-root"));
		arguments.push_back(const_cast<char *>(cache_root_.c_str()));
		if (!songlength_db_.empty()) {
			arguments.push_back(const_cast<char *>("--songlength-db"));
			arguments.push_back(const_cast<char *>(songlength_db_.c_str()));
		}
		if (timing_receipt_) arguments.push_back(const_cast<char *>("--timing-receipt"));
 arguments.push_back(nullptr);
		execv(executable_.c_str(), arguments.data());
		const char prefix[] = "converter exec failed: ";
		write(STDERR_FILENO, prefix, sizeof(prefix) - 1);
		const char *message = std::strerror(errno);
		write(STDERR_FILENO, message, std::strlen(message));
		_exit(127);
	}
	close(output_pipe[1]); close(error_pipe[1]);
	stdout_fd_ = output_pipe[0]; stderr_fd_ = error_pipe[0]; pid_ = child;
	fcntl(stdout_fd_, F_SETFL, fcntl(stdout_fd_, F_GETFL) | O_NONBLOCK);
	fcntl(stderr_fd_, F_SETFL, fcntl(stderr_fd_, F_GETFL) | O_NONBLOCK);
	standard_output_.clear(); standard_error_.clear(); detail.clear();
	return true;
}

void PosixSidPreparer::drain()
{
	drain_fd(stdout_fd_, standard_output_);
	drain_fd(stderr_fd_, standard_error_);
}

std::string PosixSidPreparer::cleanup_temporary_payload(int child_pid) const
{
	if (child_pid <= 0) return {};
	const std::string suffix = prepared_extension_ + ".tmp." + std::to_string(child_pid);
    const std::string metadata_suffix = prepared_extension_ + ".json.tmp." + std::to_string(child_pid);
	const int directory_fd = open(cache_root_.c_str(),
		O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
	if (directory_fd < 0)
		return "open " + cache_root_ + ": " + std::strerror(errno);
	DIR *directory = fdopendir(directory_fd);
	if (!directory) {
		const std::string detail = "fdopendir " + cache_root_ + ": " +
			std::strerror(errno);
		close(directory_fd);
		return detail;
	}
	std::string detail;
	for (;;) {
		errno = 0;
		dirent *entry = readdir(directory);
		if (!entry) {
			if (errno != 0) append_detail(detail, "read " + cache_root_ + ": " +
				std::strerror(errno));
			break;
		}
		const std::string name = entry->d_name;
		const auto matches = [&](const std::string &tail) {
            return name.size()>tail.size() && name.compare(name.size()-tail.size(),tail.size(),tail)==0 &&
                is_cache_key(name.substr(0,name.size()-tail.size()));
        };
        if (!matches(suffix) && !(prepared_extension_==".nsf" && matches(metadata_suffix)))
			continue;
		struct stat attributes = {};
		if (fstatat(directory_fd, name.c_str(), &attributes, AT_SYMLINK_NOFOLLOW) < 0) {
			if (errno != ENOENT)
				append_detail(detail, "inspect " + name + ": " + std::strerror(errno));
			continue;
		}
		// Never follow or unlink symlinks, directories, or other non-regular
		// entries even when their names happen to match this child's suffix.
		if (!S_ISREG(attributes.st_mode)) continue;
		if (unlinkat(directory_fd, name.c_str(), 0) < 0 && errno != ENOENT)
			append_detail(detail, "unlink " + name + ": " + std::strerror(errno));
	}
	if (closedir(directory) < 0)
		append_detail(detail, "close " + cache_root_ + ": " + std::strerror(errno));
	return detail;
}

SidPreparePollResult PosixSidPreparer::poll(std::string &prepared_path,
		std::string &detail)
{
	prepared_path.clear();
 timing_ = {};
	if (pid_ <= 0) {
		detail = "no SID prepare is active";
		return SidPreparePollResult::Failed;
	}
	drain();
	int status = 0;
	const pid_t result = waitpid(pid_, &status, WNOHANG);
	if (result == 0) return SidPreparePollResult::Running;
	if (result < 0) {
		detail = std::strerror(errno);
		append_detail(detail, cancel());
		return SidPreparePollResult::Failed;
	}
	const pid_t child = pid_;
	drain(); close_fd(stdout_fd_); close_fd(stderr_fd_); pid_ = -1;
	if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
		if (standard_error_.find("unknown/any") != std::string::npos)
			detail = "SID_METADATA_UNRESOLVED: " + standard_error_;
		else if (standard_error_.find("single-SID") != std::string::npos ||
			standard_error_.find("BASIC ROM") != std::string::npos ||
			standard_error_.find("malformed/unsupported SID") != std::string::npos)
			detail = "UNSUPPORTED_SID: " + standard_error_;
		else detail = "SID_CONVERSION_FAILED: " + standard_error_;
		append_detail(detail, cleanup_temporary_payload(child));
		return SidPreparePollResult::Failed;
	}
	while (!standard_output_.empty() &&
		(standard_output_.back() == '\n' || standard_output_.back() == '\r'))
		standard_output_.pop_back();
 if (timing_receipt_) {
  const auto line = standard_output_.find('\n');
  if (line == std::string::npos) { detail = "missing native timing receipt"; return SidPreparePollResult::Failed; }
  std::istringstream receipt(standard_output_.substr(line+1));
  std::string version, format, physical, time, fade, extra;
  PreparedPlaybackTiming parsed;
  if (!(receipt >> version >> format >> parsed.source_sha256 >> parsed.execution_sha256 >> physical >> time >> fade) ||
      (receipt >> extra) || version != "NATIVE_TIMING_V1" || (format != "NSF1" && format != "NSFe") ||
      !is_cache_key(parsed.source_sha256) || !is_cache_key(parsed.execution_sha256)) {
   detail = "invalid native timing receipt"; return SidPreparePollResult::Failed;
  }
  auto number = [](const std::string &v, std::uint64_t max, std::uint64_t &n) {
   if(v.empty()) return false;
   n=0;
   for(char c:v) { if(c<'0'||c>'9'||n>(max-static_cast<unsigned>(c-'0'))/10) return false; n=n*10+static_cast<unsigned>(c-'0'); }
   return n<=max;
  };
  std::uint64_t selected=0, t=0, f=100;
  if (!number(physical,255,selected) || !selected ||
      (time != "-" && !number(time,2147483647u,t)) ||
      (fade != "-" && !number(fade,2147483647u,f)) ||
      (format == "NSF1" && (time != "-" || fade != "-"))) {
   detail = "invalid native timing values"; return SidPreparePollResult::Failed;
  }
  parsed.physical=static_cast<unsigned>(selected);
  parsed.valid=format=="NSFe" && time!="-";
  parsed.target_ms=t+f;
  timing_=parsed;
  standard_output_.resize(line);
 }
	if (standard_output_.empty() || standard_output_.find_first_of("\r\n") != std::string::npos ||
		!ends_with(standard_output_, prepared_extension_.c_str())) {
		detail = "SID_CONVERSION_FAILED: invalid converter output path";
		append_detail(detail, cleanup_temporary_payload(child));
		return SidPreparePollResult::Failed;
	}
	char root[PATH_MAX], path[PATH_MAX]; struct stat attributes = {};
	if (!realpath(cache_root_.c_str(), root) || !realpath(standard_output_.c_str(), path) ||
		!within(root, path) || lstat(path, &attributes) || !S_ISREG(attributes.st_mode)) {
		detail = "SID_CONVERSION_FAILED: cache artifact failed path validation";
		append_detail(detail, cleanup_temporary_payload(child));
		return SidPreparePollResult::Failed;
	}
	prepared_path = path; detail.clear();
	return SidPreparePollResult::Ready;
}

std::string PosixSidPreparer::cancel()
{
	timing_ = {};
 const pid_t child = pid_;
	// Invalidate ownership before signalling. No poll result from this process
	// can become a later profile request once cancellation has begun.
	pid_ = -1;
	if (child > 0) {
		if (kill(child, SIGTERM) < 0 && errno != ESRCH) {
			// The child is ours; an unexpected signal error still falls through to
			// bounded reap/escalation instead of restoring its ownership.
		}
		if (!reap_during_grace(child)) {
			if (kill(child, SIGKILL) < 0 && errno != ESRCH) {
				// waitpid below remains the authoritative reap operation.
			}
			reap_blocking(child);
		}
	}
	close_fd(stdout_fd_); close_fd(stderr_fd_);
	standard_output_.clear(); standard_error_.clear();
	return cleanup_temporary_payload(child);
}

} // namespace megavgm_playlist
