# Host K053260 resource preflight

Pinned capability: 192*2048 bytes, matching A source a78ada2c and RBF16089238. Header declaration remains logical, not allocated storage. Validated first-traversal BA writes update all four literal start/length/key/reverse shadows. Every active intermediate envelope and cached fully-audited tuple is checked. Carried-loop BA writes are replayed three times; no page-count fixed-point heuristic is used.

Capacity overflow returns Unsupported/resource_capacity_exceeded before profile request or index1. required_pages193 on overflow is a lower bound, never a claimed197 count. resource_page_mask excludes the first unaccepted page, matching the page-audit mask at fault. Empty plan and declared-ROM page bounds follow existing FPGA readiness guards. Status ABI, Main/FPGA, transport and traversal policy are unchanged.

The CLI probe capacity_probe.cpp supports nonhardware differential/performance measurements. Build with CAPACITY_CANDIDATE and the same effective K/MSM flags for new fields; baseline probe omits that define. Read time, classifier time and total measured Host preparation are separate. No hardware transfer/PLAYING timing is inferred.

Previous metadata-only overlay fixture had no activated voice, so it could not pass FPGA E6. Its positive fixture now uses key-on; the empty-plan negative remains explicit.

Cold Supervisor and resident Controller use the same classifier. Rejected targets have no new accepted FPGA session. Existing classification-reject stop/rollback remains; no new automatic skip or queue pruning. Generic error code propagation changes only reason presentation.

Tests must compare accept/reject, retained/intermediate page sets and first capacity PC/traversal with the unchanged Parser/admission/preload harness, including exact192/193, actual197, carried-state capacity, wrap, overlay/gap, malformed, valid corpus, reload and stale ownership. Full hardware is separately gated.

The Host audit skips pitch/volume/panning envelope rechecks only after the preceding semantic WRITE completed all active checks. Start/length/key/reverse writes retain full checks; no pending audit is skipped. Every WRITE still appears in the offline intermediate-state observer. This reduces preparation cost without changing the four-traversal proof.
