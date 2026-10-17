#include "autoplay2.h"

#include <iostream>

int main(int argc, char **argv)
{
	if (argc != 3) {
		std::cerr << "Usage: megavgm_autoplay2 <Track A.vgm> <Track B.vgm>\n";
		return 2;
	}

	megavgm_autoplay2::PosixRuntime runtime;
	megavgm_autoplay2::ControllerConfig config;
	const megavgm_autoplay2::RunResult result = megavgm_autoplay2::run(
			runtime, config, argv[1], argv[2], std::cout);
	if (result == megavgm_autoplay2::RunResult::Pass) return 0;
	std::cerr << "AUTOPLAY2 FAIL: "
	          << megavgm_autoplay2::run_result_name(result) << '\n';
	return 1;
}
