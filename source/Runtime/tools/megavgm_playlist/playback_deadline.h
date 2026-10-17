#pragma once
#include <cstdint>
namespace megavgm_playlist {
// Owned by one iteration of Controller's existing track loop. Destruction or
// cancel discards all work; it cannot survive Reload or queue retarget.
class PlaybackDeadline {
 bool armed_=false, requested_=false;
 std::uint64_t generation_=0, started_=0, delay_=0;
 std::uint32_t session_=0;
public:
 void arm(std::uint64_t generation, std::uint32_t session, std::uint64_t now,
          std::uint64_t target_ms) {
  generation_=generation; session_=session; started_=now;
  delay_=target_ms>100?target_ms-100:0; armed_=true; requested_=false;
 }
 void cancel() { armed_=false; }
 bool due(std::uint64_t generation, std::uint32_t session, std::uint64_t now) const {
  return armed_ && !requested_ && generation==generation_ && session==session_ &&
         now>=started_ && now-started_>=delay_;
 }
 void requested() { requested_=true; }
 bool fading() const { return requested_; }
};
}
