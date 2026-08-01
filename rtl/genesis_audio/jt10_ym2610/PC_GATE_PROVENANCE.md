# JT10 YM2610 PC-GATE source candidate

## Upstream baseline

- Upstream repository: `https://github.com/jotego/jt12`
- Upstream commit: `6d51e0b6f64728c73408079b2f5ffe911bfd88a9`
- Pristine test pin: `tb/jt10_pinned/6d51e0b6/`
- Pinned blob manifest: `tb/jt10_compat/pristine_blobs.tsv`
- Candidate role: standalone/test-only YM2610 source overlay
- Production build connection: none; `files.qip` and QSF do not reference this directory

The four `standard_jt10/adpcm` files below are derived byte-for-byte from the
pinned upstream source and the Phase 4A-X/4A-P generators.  The divider is
derived from the matching local JT12 source at
`rtl/genesis_audio/jt12/adpcm/jt10_adpcm_div.v`; its base Git blob is
`ef9c541ba7d597fe08dd1ef97800f3b1053fe9f6` and base SHA-256 is
`b8b30c1cae5bb3fadbe4b3fdc68a980a9007cd124a24b7931221a474d32bcd31`.

| Upstream source path | Pristine Git blob | Pristine SHA-256 | Patched SHA-256 |
|---|---|---|---|
| `hdl/jt12/adpcm/jt10_adpcm_div.v` | `ef9c541ba7d597fe08dd1ef97800f3b1053fe9f6` | `b8b30c1cae5bb3fadbe4b3fdc68a980a9007cd124a24b7931221a474d32bcd31` | `ff7ec22d2662b8e837e58e14877fabe62cb8a4a73015736e81e03e9723638856` |
| `hdl/jt12/standard_jt10/adpcm/jt10_adpcm_drvB.v` | `2b3307a2eea025e1f9e95e88f58277e839abe298` | `5c4aece1eef311c53136ab5d3aee0ef6b635b8d524b55dc502820ff69b0d9133` | `183a4143885a17757b0788c268157fc36056e47f06136b20e5595dc5d87e4731` |
| `hdl/jt12/standard_jt10/adpcm/jt10_adpcmb_cnt.v` | `596ab3a8f6f31a2357b23d0a4c35e6db78c0a518` | `dadaef9d2e9b28b19f9c41516d0370722ac0f3439b6a6e4a84f23f5a3994dc2f` | `34e956261947b1257fdd4a0d151d2b147ed6a6b7d684b3c66866cc64b9c95a75` |
| `hdl/jt12/standard_jt10/adpcm/jt10_adpcmb_gain.v` | `e501c7d89816791a2fe5c06885956f24d16184f0` | `e8ce4953be4ef31cb7929d5d3d12a9d16cc97c7212a0ca09093c4d24a5b653a5` | `5f5098aacce66460b0918e7a8daa944bd1193840bfad69a796c489dd77e52fee` |
| `hdl/jt12/standard_jt10/adpcm/jt10_adpcmb_interpol.v` | `8c0284c87a909b4f840c20a0089ff9a2e41f596a` | `bb6262f41aea467bc53b41f76126bb1f5ec561fad817128ff4cda4927905481d` | `33079ac1bef4782c0e58177e69d12c64d7bebfcfd622065887818b39f1398100` |

## Diagnostic classifications and selection

- Phase 4A-X: **X-A**.  Cold-start unknowns were caused by missing global
  reset coverage.  V1 adds asynchronous active-low chip reset to every
  ADPCM-B interpolator state register and divider `d/r`, without changing
  natural-end or command-RESET semantics.
- Phase 4A-RV1: **O-A / R-B**.  The V1 core held the final digital
  contribution after natural end/command RESET and continued raw ROM requests
  while inactive, even though logical consumption, address, decoder, and
  audio progression had stopped.
- Phase 4A-P: **PC-GATE selected**.  PC-GATE is V1 plus the PO-GATE output
  ownership fix, PR request qualification, and PS accepted-START lifecycle
  reset.
- PC-CLEAR was rejected because `RESET=01 -> Control=00 -> START=80` exposed
  one stale public sample.  No PC-CLEAR stop-state clearing is present here.

## Module-level changes

- `jt10_adpcm_div`: V1 only; globally resets `d/r` together with `cycle`.
- `jt10_adpcmb_interpol`: V1 globally resets all interpolation state; PS also
  clears its validity and working state on accepted START.
- `jt10_adpcmb_gain`: clears the held gain result on accepted START only; no
  additional global reset is introduced.
- `jt10_adpcmb_cnt`: accepted START clears EOS/pending terminal state, resets
  Delta-N phase to the source-defined inactive phase, and retains the existing
  address/nibble/active reload on `restart && adv`.
- `jt10_adpcm_drvB`: qualifies raw requests with `(chon | restart)`, clears
  stale gain/lane pipeline state on accepted START, and gates only the
  ADPCM-B L/R lane contribution with `chon`.

## Lifecycle contract

- Natural end consumes exactly 512 nibbles for range `002000-0020ff`, leaves
  cursor at `0020ff` low nibble, sets EOS, clears active, stops raw request and
  capture, and reaches public digital zero after four public samples.
- Command RESET after 100 logical consumes clears active, stops request,
  capture, logical/decoder progression, and reaches public zero after three
  samples.  It is distinct from global chip reset.
- Accepted START is `acmd_up_b && acmd_on_b`.  It clears EOS and stale
  interpolation/gain/lane tags, restores Delta-N phase, and uses the existing
  `restart && adv` address/nibble/active reload and decoder clear.
- Natural-end restart, direct RESET restart, and RESET-to-00 restart reproduce
  the primary request/state/audio hashes and landmarks with stale prefix zero.
- Request qualification is registered as
  `roe_n <= ~(adv & cen55 & (chon | restart))`; `restart` preserves the first
  fetch and old `chon` preserves the terminal fetch/low nibble.

## Future upstream reproduction

Use standard JT10/YM2610 with repeat disabled, CPU memory/record modes off,
start/end registers `0020/0020` (effective bytes `002000-0020ff`), Delta-N
`8000`, pan `c0`, and level `ff`.  Compare configure-before-START, natural end,
RESET after logical consume 100, natural restart, direct RESET restart, and
RESET-to-00 restart.  Observe raw request/capture, logical consumption,
address/nibble, EOS/active, interpolation/gain/lane, and public stereo output.

This candidate has only been simulated and linted on macOS.  Quartus was not
run.  Repeat, ADPCM-A concurrency, VGM/parser/data-block/DDR integration, and
production routing remain outside this candidate.
