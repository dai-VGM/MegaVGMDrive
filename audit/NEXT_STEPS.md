# Remaining work before a formal integrated RC

1. Inspect the exact A fitted database read-only to recover failing setup endpoints, path delays, applied SDC and constraints. Establish whether the −88.815 ns core result is a real data-path violation or a constraint/report issue. Neither cause is presumed. No Timing exception, seed change, source change or recompile is authorized by this audit.
2. Resolve A's observed QSF provenance mismatch through reviewed Mac source/config authority; do not copy a Windows-only change back silently. A true all4corner signoff or explicit reviewed exception is required before claiming the new formal baseline meets that gate.
3. Preserve selected C registry/source unchanged. Recover its original producing build if available; until then record RBF reproduction as NOT_PROVEN. Do not use the differing old Windows C RBF as provenance and do not migrate C's SID timebase.
4. Once the blocking gate is resolved, assemble per-engine immutable source artifacts/RBFs with independent builds, acceptance receipts, checksums, release notes and limitations. Keep build revision names separate from deployed canonical names. No source merger is required.
5. Reconcile canonical documents minimally using verified facts: A/B/D common infrastructure and thin adapter reuse; C native-cycle exception; synchronous RAM metadata and qualified comparator sharing; ALM plus LAB/routing/timing evidence; fixed seeds and independent rebuilds; Mac-source/Windows-SSH build provenance; scoped hardware UI/PWA/loop/reset acceptance. Never claim long-run/full-admission hardware PASS without evidence.

## Engineering knowledge queued for canonical review (not new normative rules)

- B metadata RAM and tag-comparator sharing are demonstrated functional/resource techniques. Keep the 256-word semantic capacity, epoch/tag priority, raw prefix and arbitration ordering. Reuse latency-insensitive access phases only where existing tests prove equivalence.
- Lower ALM alone does not prove fit/packing improvement: earlier B ALM reductions raised LAB count. Seed3's measured 31,787 ALM / 3,995 LAB and positive timing must be distinguished from failing seed1/2 results.
- Record tool version, source/input hashes, defines, seed, resources, all4corner setup/hold/recovery/removal/pulse/TNS/counts and reproduction. Parent/child hierarchy resources must not be summed twice. No timing exceptions to hide failures.
- Raw resource facts and playback execution remain outside Common Parser. Do not add parallel CAMs for preflight work merely to achieve one-cycle lookup without a proved deadline requirement.
- Future engines needing unknown grammar require a reviewed generic extension; adapter reuse does not guarantee every future opcode needs zero parser change.
