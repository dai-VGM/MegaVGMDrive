#pragma once

#include <string>
#include <cstdint>

namespace megavgm_playlist {

// Validated receipt from the owned native preparer, not display timing.
struct PreparedPlaybackTiming {
 bool valid = false;
 std::uint64_t target_ms = 0;
 std::string source_sha256, execution_sha256;
 unsigned physical = 0;
};



enum class SidPreparePollResult { Running, Ready, Failed };

class SidPreparer {
public:
	virtual ~SidPreparer() = default;
	virtual bool start(const std::string &source, std::string &detail) = 0;
	virtual SidPreparePollResult poll(std::string &prepared_path,
			std::string &detail) = 0;
	virtual std::string cancel() = 0;
 virtual PreparedPlaybackTiming playback_timing() const { return {}; }
};

class PosixSidPreparer final : public SidPreparer {
public:
	PosixSidPreparer(
			std::string executable = "/media/fat/MegaVGMPlayer/megavgm_sid_prepare",
			std::string cache_root = "/media/fat/MegaVGMPlayer/cache/sid",
			std::string songlength_db = "/media/fat/MegaVGMPlayer/sid/Songlengths.md5",
            std::string prepared_extension = ".mvgmsid", bool timing_receipt = false);
	~PosixSidPreparer() override;
	bool start(const std::string &source, std::string &detail) override;
	SidPreparePollResult poll(std::string &prepared_path,
			std::string &detail) override;
	std::string cancel() override;
 PreparedPlaybackTiming playback_timing() const override { return timing_; }

private:
	void drain();
	std::string cleanup_temporary_payload(int child_pid) const;
	std::string executable_, cache_root_, songlength_db_, prepared_extension_;
	std::string standard_output_, standard_error_;
	int pid_ = -1, stdout_fd_ = -1, stderr_fd_ = -1;
 bool timing_receipt_;
 PreparedPlaybackTiming timing_;
};

bool is_raw_sid_name(const std::string &name);
bool is_native_container_name(const std::string &name);

} // namespace megavgm_playlist
