#define _GNU_SOURCE

#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <time.h>
#include <unistd.h>

/*
 * Diagnostic-only LD_PRELOAD probe for the dynamically linked MiSTer Main.
 * It observes libc boundaries around fpga_load_rbf without changing data,
 * return values, timing decisions, or the production executable.
 */

static int (*next_open)(const char *, int, ...);
static int (*next_open64)(const char *, int, ...);
static ssize_t (*next_read)(int, void *, size_t);
static int (*next_close)(int);
static void (*next_sync)(void);

static int tracked_fd = -1;
static int command_fd = -1;
static off_t tracked_size;
static off_t tracked_read;
static bool completed_read;
static char tracked_path[1024];

static uint64_t monotonic_us(void)
{
	struct timespec value = {0, 0};
	if (clock_gettime(CLOCK_MONOTONIC, &value)) return 0;
	return (uint64_t)value.tv_sec * 1000000u +
		(uint64_t)value.tv_nsec / 1000u;
}

static bool rbf_path(const char *path)
{
	if (!path) return false;
	const char *base = strrchr(path, '/');
	base = base ? base + 1 : path;
	return !strcmp(base, "MegaVGMDrive_A.rbf") ||
		!strcmp(base, "MegaVGMDrive_B.rbf") ||
		!strcmp(base, "MegaVGMDrive_C.rbf");
}

static void log_event(const char *event, uint64_t value, off_t bytes)
{
	const char *log_path = getenv("MEGAVGM_RBF_BENCH_LOG");
	const char *source = getenv("MEGAVGM_RBF_BENCH_SOURCE");
	const char *switch_id = getenv("MEGAVGM_RBF_BENCH_SWITCH_ID");
	const char *from = getenv("MEGAVGM_RBF_BENCH_FROM");
	const char *to = getenv("MEGAVGM_RBF_BENCH_TO");
	if (!log_path || !*log_path) return;
	if (!source || !*source) source = "unknown";
	char line[1536];
	const int length = snprintf(line, sizeof(line),
		"RBF_BENCH event=%s source=%s switch_id=%s from=%s to=%s t_us=%llu pid=%ld bytes=%lld path=%s\n",
		event, source, switch_id ? switch_id : "0", from ? from : "UNKNOWN",
		to ? to : "UNKNOWN", (unsigned long long)value, (long)getpid(),
		(long long)bytes, tracked_path[0] ? tracked_path : "-");
	if (length <= 0 || (size_t)length >= sizeof(line)) return;
	const int fd = (int)syscall(SYS_openat, AT_FDCWD, log_path,
		O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0600);
	if (fd < 0) return;
	(void)syscall(SYS_write, fd, line, (size_t)length);
	(void)syscall(SYS_close, fd);
}

static void resolve_symbols(void)
{
	void *symbol;
	if (!next_open) {
		symbol = dlsym(RTLD_NEXT, "open");
		memcpy(&next_open, &symbol, sizeof(next_open));
	}
	if (!next_open64) {
		symbol = dlsym(RTLD_NEXT, "open64");
		memcpy(&next_open64, &symbol, sizeof(next_open64));
	}
	if (!next_read) {
		symbol = dlsym(RTLD_NEXT, "read");
		memcpy(&next_read, &symbol, sizeof(next_read));
	}
	if (!next_close) {
		symbol = dlsym(RTLD_NEXT, "close");
		memcpy(&next_close, &symbol, sizeof(next_close));
	}
	if (!next_sync) {
		symbol = dlsym(RTLD_NEXT, "sync");
		memcpy(&next_sync, &symbol, sizeof(next_sync));
	}
}

static void track_open(int fd, const char *path)
{
	if (fd < 0 || !rbf_path(path)) return;
	struct stat attributes = {0};
	if (fstat(fd, &attributes) || !S_ISREG(attributes.st_mode)) return;
	tracked_fd = fd;
	tracked_size = attributes.st_size;
	tracked_read = 0;
	completed_read = false;
	const char *base = strrchr(path, '/');
	base = base ? base + 1 : path;
	strncpy(tracked_path, base, sizeof(tracked_path) - 1);
	tracked_path[sizeof(tracked_path) - 1] = 0;
	log_event("t13_rbf_open_success", monotonic_us(), tracked_size);
}

static int open_common(const char *path, int flags, mode_t mode, bool use64)
{
	resolve_symbols();
	const bool tracked_rbf = rbf_path(path);
	if (tracked_rbf) {
		const char *base = strrchr(path, '/');
		base = base ? base + 1 : path;
		strncpy(tracked_path, base, sizeof(tracked_path) - 1);
		tracked_path[sizeof(tracked_path) - 1] = 0;
		log_event("t12_rbf_open_begin", monotonic_us(), 0);
	}
	int fd;
	if (flags & O_CREAT)
		fd = use64 ? next_open64(path, flags, mode) : next_open(path, flags, mode);
	else
		fd = use64 ? next_open64(path, flags) : next_open(path, flags);
	track_open(fd, path);
	if (fd >= 0 && !strcmp(path, "/dev/MiSTer_cmd")) command_fd = fd;
	return fd;
}

int open(const char *path, int flags, ...)
{
	mode_t mode = 0;
	if (flags & O_CREAT) {
		va_list values;
		va_start(values, flags);
		mode = (mode_t)va_arg(values, int);
		va_end(values);
	}
	return open_common(path, flags, mode, false);
}

int open64(const char *path, int flags, ...)
{
	mode_t mode = 0;
	if (flags & O_CREAT) {
		va_list values;
		va_start(values, flags);
		mode = (mode_t)va_arg(values, int);
		va_end(values);
	}
	return open_common(path, flags, mode, true);
}

ssize_t read(int fd, void *buffer, size_t count)
{
	resolve_symbols();
	const ssize_t result = next_read(fd, buffer, count);
	if (fd == command_fd && result >= 10 &&
		!memcmp(buffer, "load_core ", 10))
		log_event("t9_main_receives_load_core", monotonic_us(), result);
	if (fd == tracked_fd && result > 0 && !completed_read) {
		tracked_read += result;
		if (tracked_read >= tracked_size) {
			completed_read = true;
			log_event("source_read_complete", monotonic_us(), tracked_read);
		}
	}
	return result;
}

int close(int fd)
{
	resolve_symbols();
	if (fd == tracked_fd) tracked_fd = -1;
	if (fd == command_fd) command_fd = -1;
	return next_close(fd);
}

void sync(void)
{
	resolve_symbols();
	if (completed_read)
		log_event("configuration_return", monotonic_us(), tracked_size);
	next_sync();
	if (completed_read)
		log_event("post_configuration_sync", monotonic_us(), tracked_size);
}
