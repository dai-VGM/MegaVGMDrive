#ifndef MEGAVGM_PLAYBACK_MODE_H
#define MEGAVGM_PLAYBACK_MODE_H

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace megavgm_playlist {

enum class RepeatMode {
	Off,
	One,
	All
};

struct PlaybackPreferences {
	RepeatMode repeat = RepeatMode::Off;
	bool shuffle = false;
};

const char *repeat_mode_name(RepeatMode mode);
bool parse_repeat_mode(const std::string &value, RepeatMode &mode);

class RandomSource {
public:
	virtual ~RandomSource() = default;
	virtual std::uint32_t uniform(std::uint32_t upper_exclusive) = 0;
};

class XorShiftRandom final : public RandomSource {
public:
	explicit XorShiftRandom(std::uint32_t seed);
	std::uint32_t uniform(std::uint32_t upper_exclusive) override;

private:
	std::uint32_t state_;
};

enum class TraversalResult {
	Track,
	Stay,
	Complete
};

// Controller-owned traversal state. Indices always refer to the active
// directory/playlist snapshot and never escape into the Remote process.
class PlaybackTraversal {
public:
	explicit PlaybackTraversal(RandomSource &random);

	void reset(std::size_t count, std::size_t current,
			const PlaybackPreferences &preferences);
	void set_preferences(const PlaybackPreferences &preferences,
			std::size_t current);
	void select(std::size_t current);

	TraversalResult next(std::size_t current, bool automatic,
			bool native_looping, std::size_t &selected);
	TraversalResult previous(std::size_t current, std::size_t &selected);

	const PlaybackPreferences &preferences() const { return preferences_; }
	std::size_t remaining_count() const { return remaining_.size(); }
	const std::vector<std::size_t> &history() const { return history_; }

private:
	void build_bag(std::size_t current, bool include_current);
	void append_history(std::size_t index);
	bool take_bag(std::size_t current, std::size_t &selected);

	RandomSource &random_;
	PlaybackPreferences preferences_;
	std::size_t count_ = 0;
	std::vector<std::size_t> remaining_;
	std::vector<std::size_t> history_;
	std::size_t history_position_ = 0;
};

bool load_playback_preferences(const std::string &path,
		PlaybackPreferences &preferences, std::string &detail);
bool save_playback_preferences(const std::string &path,
		const PlaybackPreferences &preferences, std::string &detail);

} // namespace megavgm_playlist

#endif
