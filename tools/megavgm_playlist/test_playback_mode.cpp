#include "playback_mode.h"

#include <cassert>
#include <cstdlib>
#include <fstream>
#include <set>
#include <string>
#include <unistd.h>
#include <vector>

using namespace megavgm_playlist;

namespace {

class SequenceRandom final : public RandomSource {
public:
	explicit SequenceRandom(std::vector<std::uint32_t> values)
		: values_(std::move(values)) {}
	std::uint32_t uniform(std::uint32_t upper) override
	{
		if (upper <= 1) return 0;
		const std::uint32_t value = values_.empty() ? 0 :
			values_[position_++ % values_.size()];
		return value % upper;
	}
private:
	std::vector<std::uint32_t> values_;
	std::size_t position_ = 0;
};

void test_normal_and_repeat()
{
	SequenceRandom random({0});
	PlaybackTraversal traversal(random);
	PlaybackPreferences preferences;
	traversal.reset(3, 0, preferences);
	std::size_t selected = 99;
	assert(traversal.next(0, true, false, selected) == TraversalResult::Track &&
		selected == 1);
	assert(traversal.next(2, true, false, selected) == TraversalResult::Complete);

	preferences.repeat = RepeatMode::All;
	traversal.set_preferences(preferences, 2);
	assert(traversal.next(2, true, false, selected) == TraversalResult::Track &&
		selected == 0);
	assert(traversal.previous(0, selected) == TraversalResult::Track &&
		selected == 2);

	preferences.repeat = RepeatMode::One;
	traversal.set_preferences(preferences, 1);
	assert(traversal.next(1, true, false, selected) == TraversalResult::Track &&
		selected == 1);
	assert(traversal.next(1, true, true, selected) == TraversalResult::Stay);
	// Manual navigation always overrides Repeat One.
	assert(traversal.next(1, false, false, selected) == TraversalResult::Track &&
		selected == 2);

	preferences.shuffle = true;
	traversal.reset(3, 1, preferences);
	assert(traversal.next(1, true, false, selected) == TraversalResult::Track &&
		selected == 1); // Repeat One dominates shuffle automatic traversal.
	assert(traversal.next(1, false, false, selected) == TraversalResult::Track &&
		selected != 1); // Manual NEXT still consumes the shuffle bag.
}

void test_shuffle_bag_history_and_cycle()
{
	SequenceRandom random({3, 1, 0, 2, 1, 0});
	PlaybackTraversal traversal(random);
	PlaybackPreferences preferences;
	preferences.shuffle = true;
	traversal.reset(5, 2, preferences);
	std::set<std::size_t> first_cycle{2};
	std::vector<std::size_t> actual{2};
	std::size_t current = 2;
	for (int step = 0; step < 4; ++step) {
		std::size_t selected = 99;
		assert(traversal.next(current, true, false, selected) ==
			TraversalResult::Track);
		assert(selected != current);
		first_cycle.insert(selected);
		actual.push_back(selected);
		current = selected;
	}
	assert(first_cycle.size() == 5);
	std::size_t selected = 99;
	assert(traversal.next(current, true, false, selected) ==
		TraversalResult::Complete);

	preferences.repeat = RepeatMode::All;
	traversal.set_preferences(preferences, current);
	assert(traversal.next(current, true, false, selected) ==
		TraversalResult::Track);
	assert(selected != current); // cycle boundary cannot immediately repeat.
	const std::size_t after_cycle = selected;
	assert(traversal.previous(after_cycle, selected) == TraversalResult::Track);
	assert(selected == current); // PREV follows actual playback history.
	assert(traversal.next(selected, false, false, selected) ==
		TraversalResult::Track && selected == after_cycle);

	traversal.select(4);
	assert(traversal.history().back() == 4);
	preferences.shuffle = false;
	traversal.set_preferences(preferences, 4);
	assert(traversal.next(4, false, false, selected) ==
		TraversalResult::Track && selected == 0); // Repeat All ordered wrap.
}

void test_single_track_shuffle()
{
	SequenceRandom random({0});
	PlaybackTraversal traversal(random);
	PlaybackPreferences preferences;
	preferences.shuffle = true;
	preferences.repeat = RepeatMode::All;
	traversal.reset(1, 0, preferences);
	std::size_t selected = 1;
	assert(traversal.next(0, true, false, selected) == TraversalResult::Track);
	assert(selected == 0);

	traversal.reset(0, 0, preferences);
	assert(traversal.next(0, true, false, selected) ==
		TraversalResult::Complete);

	preferences.shuffle = false;
	traversal.reset(2, 0, preferences);
	assert(traversal.previous(0, selected) == TraversalResult::Track &&
		selected == 1); // two-track Repeat All PREV wrap.
}

void test_twenty_five_track_shuffle_once()
{
	SequenceRandom random({8, 3, 21, 1, 13, 5});
	PlaybackTraversal traversal(random);
	PlaybackPreferences preferences;
	preferences.shuffle = true;
	constexpr std::size_t count = 25;
	std::size_t current = 11;
	traversal.reset(count, current, preferences);
	std::set<std::size_t> seen{current};
	for (std::size_t step = 1; step < count; ++step) {
		std::size_t selected = count;
		assert(traversal.next(current, true, false, selected) ==
			TraversalResult::Track);
		assert(seen.insert(selected).second);
		current = selected;
	}
	std::size_t selected = count;
	assert(traversal.next(current, true, false, selected) ==
		TraversalResult::Complete);
}

void test_large_shuffle_stress()
{
	SequenceRandom random({0, 17, 4, 99, 3, 51, 7, 1});
	PlaybackTraversal traversal(random);
	PlaybackPreferences preferences;
	preferences.shuffle = true;
	preferences.repeat = RepeatMode::All;
	constexpr std::size_t count = 128;
	std::size_t current = 73;
	traversal.reset(count, current, preferences);
	for (int cycle = 0; cycle < 20; ++cycle) {
		std::set<std::size_t> seen{current};
		for (std::size_t step = 1; step < count; ++step) {
			std::size_t selected = count;
			assert(traversal.next(current, true, false, selected) ==
				TraversalResult::Track);
			assert(selected != current);
			assert(seen.insert(selected).second);
			current = selected;
		}
		std::size_t first_next_cycle = count;
		assert(traversal.next(current, true, false, first_next_cycle) ==
			TraversalResult::Track);
		assert(first_next_cycle != current);
		current = first_next_cycle;
		// The first item of the new cycle is the retained starting point for
		// the following cycle coverage check.
	}
}

void test_preferences_persistence()
{
	char directory_template[] = "/tmp/megavgm-mode-test.XXXXXX";
	char *directory = mkdtemp(directory_template);
	assert(directory);
	const std::string path = std::string(directory) + "/nested/playback_modes.conf";
	PlaybackPreferences preferences;
	std::string detail;
	assert(!load_playback_preferences(path, preferences, detail));
	assert(preferences.repeat == RepeatMode::Off && !preferences.shuffle);
	preferences.repeat = RepeatMode::All;
	preferences.shuffle = true;
	assert(save_playback_preferences(path, preferences, detail));
	PlaybackPreferences loaded;
	assert(load_playback_preferences(path, loaded, detail));
	assert(loaded.repeat == RepeatMode::All && loaded.shuffle);
	{
		std::ofstream malformed(path, std::ios::trunc);
		malformed << "not valid\n";
	}
	assert(!load_playback_preferences(path, loaded, detail));
	assert(loaded.repeat == RepeatMode::Off && !loaded.shuffle);
	assert(access((path + ".tmp." +
		std::to_string(static_cast<unsigned long>(getpid()))).c_str(), F_OK) != 0);
	assert(unlink(path.c_str()) == 0);
	assert(rmdir((std::string(directory) + "/nested").c_str()) == 0);
	assert(rmdir(directory) == 0);
}

} // namespace

int main()
{
	test_normal_and_repeat();
	test_shuffle_bag_history_and_cycle();
	test_single_track_shuffle();
	test_twenty_five_track_shuffle_once();
	test_large_shuffle_stress();
	test_preferences_persistence();
	return 0;
}
