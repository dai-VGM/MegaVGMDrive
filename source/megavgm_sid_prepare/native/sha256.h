#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <string>

namespace megavgm_sid {

class Sha256 {
public:
	Sha256();
	void update(const void *data, std::size_t size);
	std::array<std::uint8_t, 32> finish();

private:
	void transform(const std::uint8_t block[64]);
	std::uint32_t state_[8];
	std::uint64_t bytes_ = 0;
	std::uint8_t buffer_[64] = {};
	std::size_t buffered_ = 0;
	bool finished_ = false;
};

bool sha256_file(const std::string &path, std::array<std::uint8_t, 32> &digest,
		std::string &detail);
std::string hex_digest(const std::array<std::uint8_t, 32> &digest);

} // namespace megavgm_sid
