#pragma once

#include "supervisor.h"

#include <cstdint>
#include <functional>
#include <string>
#include <vector>

namespace megavgm_supervisor {

struct ProcessIdentity {
	bool alive = false;
	std::uint64_t starttime = 0;
	std::uint64_t executable_device = 0;
	std::uint64_t executable_inode = 0;
	std::string executable;
	std::string role;
	std::vector<std::string> arguments;
};

struct ProcessExpectation {
	std::vector<std::string> executable_paths;
	std::string role;
	std::vector<std::string> arguments;
};

struct ProcessStabilizationConfig {
	unsigned int poll_ms = 50;
	unsigned int minimum_observation_ms = 250;
	unsigned int identity_appearance_timeout_ms = 1000;
};

using ProcessObserver = std::function<OperationResult(ProcessIdentity &)>;
using MonotonicMilliseconds = std::function<std::uint64_t()>;
using StabilizationSleep = std::function<void(unsigned int)>;
using FinalProcessVerifier = std::function<OperationResult()>;

inline bool expected_process_identity(const ProcessIdentity &identity,
	const ProcessExpectation &expected)
{
	bool path_matches = false;
	for (const std::string &path : expected.executable_paths)
		if (identity.executable == path) path_matches = true;
	return identity.alive && path_matches && identity.role == expected.role &&
		identity.arguments == expected.arguments;
}

inline bool same_process_identity(const ProcessIdentity &left,
	const ProcessIdentity &right)
{
	return left.starttime == right.starttime &&
		left.executable_device == right.executable_device &&
		left.executable_inode == right.executable_inode &&
		left.executable == right.executable && left.role == right.role &&
		left.arguments == right.arguments;
}

inline OperationResult stabilize_process(const std::string &name,
	const ProcessExpectation &expected, const ProcessStabilizationConfig &config,
	const ProcessObserver &observe, const MonotonicMilliseconds &monotonic_ms,
	const StabilizationSleep &sleep_ms, const FinalProcessVerifier &final_verify)
{
	if (!config.poll_ms || !config.minimum_observation_ms ||
		config.identity_appearance_timeout_ms < config.poll_ms)
		return OperationResult::failure(name + " invalid stabilization configuration");

	const std::uint64_t begin = monotonic_ms();
	std::uint64_t first_starttime = 0;
	bool have_starttime = false;
	bool stabilizing = false;
	std::uint64_t stable_since = 0;
	unsigned int stable_samples = 0;
	ProcessIdentity baseline;

	for (;;) {
		ProcessIdentity current;
		OperationResult observed = observe(current);
		if (!observed.ok)
			return OperationResult::failure(name + " identity unavailable: " +
				observed.detail);
		if (!current.alive)
			return OperationResult::failure(name + " exited during stabilization");
		if (!have_starttime) {
			first_starttime = current.starttime;
			have_starttime = true;
		} else if (current.starttime != first_starttime) {
			return OperationResult::failure(name + " PID/starttime identity changed");
		}

		const std::uint64_t now = monotonic_ms();
		if (!stabilizing) {
			if (expected_process_identity(current, expected)) {
				baseline = current;
				stable_since = now;
				stable_samples = 1;
				stabilizing = true;
				OperationResult verified = final_verify();
				if (!verified.ok) return verified;
				ProcessIdentity after_verification;
				observed = observe(after_verification);
				if (!observed.ok ||
					!expected_process_identity(after_verification, expected) ||
					!same_process_identity(after_verification, baseline))
					return OperationResult::failure(name +
						" identity changed during executable verification");
				++stable_samples;
			} else if (now - begin >= config.identity_appearance_timeout_ms) {
				return OperationResult::failure(name +
					" expected executable/role/argv did not appear");
			}
		} else {
			if (!expected_process_identity(current, expected))
				return OperationResult::failure(name +
					" executable/role/argv changed during stabilization");
			if (!same_process_identity(current, baseline))
				return OperationResult::failure(name +
					" process identity changed during stabilization");
			++stable_samples;
			if (now - stable_since >= config.minimum_observation_ms &&
				stable_samples >= 3) {
				return OperationResult::success();
			}
		}

		sleep_ms(config.poll_ms);
	}
}

} // namespace megavgm_supervisor
