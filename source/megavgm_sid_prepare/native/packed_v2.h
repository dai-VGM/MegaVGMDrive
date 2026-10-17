#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <string>

namespace megavgm_sid {

constexpr std::uint32_t kDurationKnown = 1u << 0;
constexpr std::uint32_t kLoopValid = 1u << 1;
constexpr std::uint32_t kEndIsCaptureLimit = 1u << 2;
constexpr std::uint32_t kModelExplicitOverride = 1u << 3;
constexpr std::uint32_t kClockExplicitOverride = 1u << 4;
constexpr std::uint32_t kKnownFlags = (1u << 5) - 1;
constexpr std::uint64_t kHeaderBytes = 128;
constexpr std::uint64_t kMaximumFileBytes = 8ull * 1024ull * 1024ull;
constexpr std::uint64_t kMaximumStreamBytes = kMaximumFileBytes - kHeaderBytes;
constexpr std::uint64_t kMaximumEofBytes = 11;

enum class CapacityDecision { Write, CaptureLimit, Reject };

struct PackedMetadata {
	std::uint32_t flags = 0;
	std::uint32_t clock_num = 0;
	std::uint32_t clock_den = 1;
	std::uint8_t sid_model = 0;
	std::uint8_t timing_standard = 0;
	std::uint32_t subtune = 0;
	std::uint64_t write_count = 0;
	std::uint64_t stream_bytes = 0;
	std::uint64_t stream_cycles = 0;
	std::uint64_t duration_cycles = 0;
	std::uint64_t loop_write_index = 0;
	std::uint64_t loop_start_cycle = 0;
	std::uint64_t loop_end_cycle = 0;
	std::array<std::uint8_t,32> source_sha256{};
};

bool write_uleb(FILE *file, std::uint64_t value, std::uint64_t &bytes,
		std::string &detail);
unsigned uleb_size(std::uint64_t value);
CapacityDecision capacity_decision(std::uint64_t current_stream_bytes,
		std::uint64_t delta, bool allow_capacity_limit);
bool write_header(FILE *file, const PackedMetadata &metadata, std::string &detail);
bool validate_packed_v2(const std::string &path, PackedMetadata &metadata,
		std::string &detail);
bool canonicalize_manual_loop(const std::string &input_path,
		const std::string &output_path, std::uint64_t requested_start_cycle,
		std::uint64_t requested_end_cycle, PackedMetadata &metadata,
		std::string &detail);

} // namespace megavgm_sid
