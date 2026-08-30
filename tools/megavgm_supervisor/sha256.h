#pragma once

#include <string>

namespace megavgm_supervisor {

bool sha256_file(const std::string &path, std::string &digest,
	std::string &detail);

} // namespace megavgm_supervisor
