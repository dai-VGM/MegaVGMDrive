# Preservation record V2

## Start authority

- Branch: `jt10-gatee-te-ownership-fix`
- HEAD: `b531ed016c7d1f701f5c00501e995db756629a72`
- Tracked/staged diff: 0 / 0
- Untracked baseline: 496
- Quarantine: 19
- Stash entries: 4

`BASELINE_496_START.tsv` records path, SHA-256, size, mtime_ns, and inode for
all 496 start files.  `QUARANTINE_19_V2_START.tsv`,
`FROZEN_ASSETS_V2_START.tsv`, and `STASH_4_V2_START.tsv` provide the separate
authorities required by Gate A.

Every validation gate rechecked the 496 baseline, quarantine 19, 37 frozen
assets, and stash count before compile or simulation.  Candidate generation
was reproduced twice in isolated temporary directories and produced identical
SHA-256 values.

## New scope only

Only new files under these paths are eligible for the task commit:

- `tb/jt10_semantic_zero_attempt_normalize/`
- new V2 audit files under `docs/jt10_semantic_zero_attempt_normalize/`

The eight documentation files that existed in the 496 baseline remain
untracked and are not eligible for staging.  Simulation VVPs and logs remain
under `/private/tmp/jt10-semantic-zero-attempt-normalize-v2.RBbUY2/` and are
not versioned.

## Execution count

- Unit: 4 compiles, 4 simulations.
- Two-layer negative: 1 compile, 1 simulation.
- Offline Z0-Z3 replay: 4 compiles, 4 simulations.
- Targeted integrated: 1 compile, 1 simulation.
- Bounded two-loop: 1 compile, 1 simulation.
- Total: 11 compiles and 11 simulations.
- FAST_SIM complete: 0.
- FAST_SIM=0: 0.
- Three-run: 0.
- Quartus/RBF: 0/0.

Final identity, git diff, staged-scope, Sacred TB, and stash checks are recorded
after the functional gates and before commit.
