#include "process_stabilization.h"

#include <cassert>
#include <cstdint>
#include <iostream>
#include <string>
#include <utility>
#include <vector>

using megavgm_supervisor::OperationResult;
using megavgm_supervisor::ProcessExpectation;
using megavgm_supervisor::ProcessIdentity;
using megavgm_supervisor::ProcessStabilizationConfig;
using megavgm_supervisor::stabilize_process;

namespace {

ProcessIdentity good_identity()
{
	ProcessIdentity identity;
	identity.alive = true;
	identity.starttime = 12345;
	identity.executable_device = 10;
	identity.executable_inode = 20;
	identity.executable = "/media/fat/MiSTer";
	identity.role = "MiSTer";
	identity.arguments = {
		"/media/fat/MiSTer", "/media/fat/_Custom Cores/Cores/MegaVGMDrive_C.rbf"};
	return identity;
}

struct TimedIdentity {
	std::uint64_t at_ms;
	ProcessIdentity identity;
};

class Scenario {
public:
	explicit Scenario(std::vector<TimedIdentity> states)
		: states_(std::move(states)) {}

	OperationResult observe(ProcessIdentity &identity)
	{
		std::size_t selected = 0;
		for (std::size_t index = 1; index < states_.size(); ++index) {
			if (states_[index].at_ms > now_ms_) break;
			selected = index;
		}
		identity = states_[selected].identity;
		++observations;
		return OperationResult::success();
	}

	std::uint64_t now() const { return now_ms_; }
	void sleep(unsigned int milliseconds) { now_ms_ += milliseconds; }

	std::uint64_t now_ms_ = 0;
	unsigned int observations = 0;

private:
	std::vector<TimedIdentity> states_;
};

OperationResult run(Scenario &scenario, bool final_ok = true,
	unsigned int verification_ms = 0, unsigned int *verification_calls = nullptr)
{
	const ProcessExpectation expected = {{"/media/fat/MiSTer",
		"/media/fat/MegaVGMPlayer/MiSTer.megavgm"}, "MiSTer",
		{"/media/fat/MiSTer",
		 "/media/fat/_Custom Cores/Cores/MegaVGMDrive_C.rbf"}};
	const ProcessStabilizationConfig config = {50, 200, 1000};
	return stabilize_process("test Main", expected, config,
		[&](ProcessIdentity &identity) { return scenario.observe(identity); },
		[&]() { return scenario.now(); },
		[&](unsigned int milliseconds) { scenario.sleep(milliseconds); },
		[&]() {
			if (verification_calls) ++*verification_calls;
			scenario.sleep(verification_ms);
			return final_ok ? OperationResult::success() :
				OperationResult::failure("test Main executable SHA-256 mismatch");
		});
}

void expect_failure_at(std::uint64_t exit_ms)
{
	ProcessIdentity exited = good_identity();
	exited.alive = false;
	Scenario scenario({{0, good_identity()}, {exit_ms, exited}});
	assert(!run(scenario).ok);
}

} // namespace

int main()
{
	{
		Scenario scenario({{0, good_identity()}});
		unsigned int verification_calls = 0;
		assert(run(scenario, true, 0, &verification_calls).ok);
		assert(scenario.now_ms_ == 200);
		assert(scenario.observations == 6); // baseline, post-SHA, and four polls.
		assert(verification_calls == 1);
	}
	{
		Scenario scenario({{0, good_identity()}});
		unsigned int verification_calls = 0;
		assert(run(scenario, true, 150, &verification_calls).ok);
		assert(scenario.now_ms_ == 200); // SHA work is inside the observation window.
		assert(scenario.observations == 3);
		assert(verification_calls == 1);
	}
	{
		ProcessIdentity exited = good_identity();
		exited.alive = false;
		Scenario scenario({{0, exited}});
		assert(!run(scenario).ok);
	}
	expect_failure_at(50);
	expect_failure_at(100);
	expect_failure_at(199);
	{
		ProcessIdentity wrong = good_identity();
		wrong.executable = "/tmp/not-MiSTer";
		Scenario scenario({{0, wrong}});
		assert(!run(scenario).ok);
		assert(scenario.now_ms_ == 1000);
	}
	{
		Scenario scenario({{0, good_identity()}});
		assert(!run(scenario, false).ok); // final SHA verifier is authoritative.
	}
	{
		ProcessIdentity wrong = good_identity();
		wrong.role = "wrong-role";
		Scenario scenario({{0, wrong}});
		assert(!run(scenario).ok);
	}
	{
		ProcessIdentity wrong = good_identity();
		wrong.arguments.pop_back();
		Scenario scenario({{0, wrong}});
		assert(!run(scenario).ok);
	}
	{
		ProcessIdentity changed = good_identity();
		changed.starttime++;
		Scenario scenario({{0, good_identity()}, {100, changed}});
		assert(!run(scenario).ok);
	}
	{
		ProcessIdentity replaced = good_identity();
		replaced.executable_inode++;
		Scenario scenario({{0, good_identity()}, {100, replaced}});
		assert(!run(scenario).ok);
	}
	{
		ProcessIdentity pre_exec = good_identity();
		pre_exec.executable = "/media/fat/MegaVGMPlayer/megavgm_supervisor";
		pre_exec.executable_inode = 19;
		pre_exec.role = "megavgm_supervi";
		pre_exec.arguments = {"megavgm_supervisor"};
		Scenario scenario({{0, pre_exec}, {50, good_identity()}});
		assert(run(scenario).ok);
		assert(scenario.now_ms_ == 250);
	}
	{
		Scenario first({{0, good_identity()}});
		Scenario second({{0, good_identity()}});
		assert(run(first).ok && run(second).ok);
		assert(first.now_ms_ == second.now_ms_);
		assert(first.observations == second.observations);
	}

	std::cout << "Process stabilization tests: PASS\n";
	return 0;
}
