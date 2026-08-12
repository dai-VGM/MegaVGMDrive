# 525-file provenance checkpoint

Status: **PASS**. This is a one-time provenance reset, not a retroactive
claim that the historical 513 or 519 manifests existed.

The complete historical checkpoint is 496 files. The current 525 untracked
set is classified as:

- `HISTORICAL_496`: 496
- `FINAL_DWELL_SCOPE`: 17
- `RUNNER_AUDIT`: 6
- `FAILED_ATTEMPT_NONAUTHORITY`: 6

Total: 525, with zero duplicate, missing, or unclassified paths. The failed
runner-observation six are retained and explicitly excluded as simulation
authority.

The 496 path/SHA/size identity was rechecked with zero mismatches. The
historical 513 and 519 counts can be composed from scopes, but their
independent manifests are absent. Therefore this checkpoint does not fill
that historical gap.

**PROVENANCE GAP ACKNOWLEDGED, NOT RETROACTIVELY FILLED.**

The manifest uses Python `st_mtime_ns` and records the true nanosecond value.
No VVP, compile, simulation, HDL, candidate, or protected asset was changed.
