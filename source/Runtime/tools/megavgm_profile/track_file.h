#pragma once

#include <string>

namespace megavgm_track {

inline bool has_exact_suffix(const std::string &value,
		const char *suffix, std::size_t suffix_size)
{
	return value.size() > suffix_size &&
		value.compare(value.size() - suffix_size, suffix_size, suffix) == 0;
}

// Production track-name contract shared by Supervisor admission and controller
// directory/snapshot discovery. Matching is intentionally case-sensitive.
inline bool is_supported_track(const std::string &value)
{
	return has_exact_suffix(value, ".vgm", 4) ||
		has_exact_suffix(value, ".mvgmsid", 8) ||
		has_exact_suffix(value, ".sid", 4) ||
		has_exact_suffix(value, ".nsf", 4) || has_exact_suffix(value, ".nsfe", 5);
}

inline bool is_direct_playlist_member(const std::string &directory,
		const std::string &path)
{
	const std::size_t separator = path.find_last_of('/');
	return separator != std::string::npos &&
		path.substr(0, separator) == directory &&
		is_supported_track(path);
}

} // namespace megavgm_track
