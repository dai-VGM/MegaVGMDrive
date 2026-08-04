# YM2610 Golden Shell Stage B

Stage B is a compatibility scan only. It deliberately has no playback parser,
wait engine, register writer, JT sound device, PCM decoder/cache/client, or
audio behavior. The Stage A shell and its compatibility shim remain unchanged.
The Stage B QIP substitutes a versioned implementation of the existing
`ym2610_golden_stage_a` profile port contract.

## Load and read contract

The immutable `vgm_ddram_backend` asserts `load_done` only after download is
low and its partial pack, FIFO, pending write, write pop, and DDR busy state are
all clear. Stage B additionally observes that completion for two clocks. Its
only memory owner is a single-client byte adapter. The adapter captures address
and load generation, holds request/address through `req && ready`, permits one
outstanding response, and never reconstructs response ownership from a live
scanner address. Download/reset cancels the transaction and quarantines an
untagged stale response; timeout or an unowned response enters rejected idle.

Prepared files are identified by validating every field and padding byte of
the 128-byte `MVGMTTL` v1 trailer. This preflight occurs after formal upload
completion. A valid trailer supplies the exact original body size; otherwise
the physical size is the raw VGM size. The scanner starts only after the exact
size is valid and the complete fence remains true for two more clocks. It can
never read the trailer because every command/header access is bounded by that
exact original size.

## Classification

The sticky result classes are `0 STANDARD`, `1 B_COMPATIBLE`, `2 B_REQUIRED`,
`3 DUAL_UNSUPPORTED`, `4 MALFORMED`, and `5 UNSUPPORTED_COMMAND`. Register
meaning mirrors the pinned standard-YM2610 JT10/JT12 MMR decode, but no JT10
source is compiled. Both setup and key writes to selector zero in either FM
bank are B-only; selectors one/two are the four standard channels. Reserved
registers are rejected rather than treated as compatible.

Supported commands are `58`, `59`, `61`, `62`, `63`, `66`, `67`, and
`70`--`7F`. A command length is never guessed. The first unsupported or
malformed event retains PC, opcode/data, sample timestamp, port, register,
semantic, and target as applicable.

## ROM descriptors

Only uncompressed `82` (ADPCM-A) and `83` (DELTA-T/ADPCM-B) blocks are
accepted. A and B have separate 1 MiB and 512 KiB logical spaces. Each sticky
entry records validity, block type by table, logical ROM size, logical start,
exclusive end via start plus length, physical payload offset/length, and source
command PC. Bounds, subtraction/addition overflow, payload EOF, overlap, and
table overflow are rejected. The mapping surface is retained for test only and
is not connected to playback in Stage B.

## Idle contract

Accepted and rejected scans both stop with no outstanding read. Results remain
sticky until download/reset. Audio L/R, sample valid, playback activity,
parser start, sound write, and both reserved PCM request ports are hard zero.
The immutable title, video, OSD/Menu, reset, PLL, pin, and audio shell continue
unchanged; no renderer or automatic debug switching was added.
