# Historical provenance gap

`BASELINE_496_START.tsv` is the last complete historical identity manifest.
The later 513 and 519 checkpoints were reported by count and scope, but no
independent path/SHA/size manifests for those moments survive.

Current evidence supports the composition `496 + 17 + 6 + 6 = 525` and shows
no mutation in the 496 files. It does not prove the historical 513/519 file
identities retroactively.

The six failed runner-observation files are classified
`FAILED_ATTEMPT_NONAUTHORITY`; they are preserved but cannot be used as
simulation evidence.

Past documents that labelled seconds-valued `st_mtime` as `mtime_ns` are
recorded as `MTIME-LABEL-BUG`; this is separate from path/SHA/size identity.

**PROVENANCE GAP ACKNOWLEDGED, NOT RETROACTIVELY FILLED.**
