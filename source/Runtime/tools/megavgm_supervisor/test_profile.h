#pragma once
#include "linux_runtime.h"

namespace megavgm_supervisor {
// Fixed, opt-in test selection only. No chip classification or active switch.
OperationResult apply_test_profile(Paths &paths);
OperationResult set_test_profile(const Paths &paths, const std::string &name);
} // namespace megavgm_supervisor
