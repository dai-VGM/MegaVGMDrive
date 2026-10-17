#pragma once

#include <cerrno>
#include <cstdint>
#include <cstdlib>
#include <fcntl.h>
#include <string>
#include <time.h>
#include <unistd.h>

namespace megavgm_rbf_bench {

inline bool enabled()
{
	const char *path = std::getenv("MEGAVGM_RBF_BENCH_LOG");
	const char *source = std::getenv("MEGAVGM_RBF_BENCH_SOURCE");
	return path && std::string(path) ==
		"/tmp/megavgm-rbf-bench/main-events.log" && source &&
		(std::string(source) == "fat" || std::string(source) == "tmp");
}

inline std::uint64_t monotonic_us()
{
	struct timespec value = {0, 0};
	if (clock_gettime(CLOCK_MONOTONIC, &value)) return 0;
	return static_cast<std::uint64_t>(value.tv_sec) * 1000000u +
		static_cast<std::uint64_t>(value.tv_nsec) / 1000u;
}

inline void context(std::uint64_t generation, const std::string &from,
	const std::string &to)
{
	if (!enabled()) return;
	const std::string id = std::to_string(generation);
	(void)setenv("MEGAVGM_RBF_BENCH_SWITCH_ID", id.c_str(), 1);
	(void)setenv("MEGAVGM_RBF_BENCH_FROM", from.c_str(), 1);
	(void)setenv("MEGAVGM_RBF_BENCH_TO", to.c_str(), 1);
}

inline void write_line(const std::string &line)
{
	if (!enabled()) return;
	const int fd = open("/tmp/megavgm-rbf-bench/main-events.log",
		O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0600);
	if (fd < 0) return;
	std::size_t offset = 0;
	while (offset < line.size()) {
		const ssize_t count = write(fd, line.data() + offset, line.size() - offset);
		if (count > 0) offset += static_cast<std::size_t>(count);
		else if (count < 0 && errno == EINTR) continue;
		else break;
	}
	(void)close(fd);
}

inline void event(const char *name, std::uint64_t generation,
	const std::string &from, const std::string &to, const std::string &detail = {})
{
	if (!enabled()) return;
	std::string line = "SWITCH_LATENCY event=" + std::string(name) +
		" switch_id=" + std::to_string(generation) + " from=" + from +
		" to=" + to + " t_us=" + std::to_string(monotonic_us());
	if (!detail.empty()) line += " detail=" + detail;
	line += '\n';
	write_line(line);
}

inline void event(const char *name, const std::string &detail = {})
{
	if (!enabled()) return;
	const char *id = std::getenv("MEGAVGM_RBF_BENCH_SWITCH_ID");
	const char *from = std::getenv("MEGAVGM_RBF_BENCH_FROM");
	const char *to = std::getenv("MEGAVGM_RBF_BENCH_TO");
	if (!id || !from || !to) return;
	char *end = nullptr;
	errno = 0;
	const unsigned long long generation = std::strtoull(id, &end, 10);
	if (errno || !end || *end || !generation) return;
	event(name, static_cast<std::uint64_t>(generation), from, to, detail);
}

} // namespace megavgm_rbf_bench
