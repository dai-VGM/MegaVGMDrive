# Large VGM Storage Plan

## Current State

`REGION_MODE=5` currently loads an uncompressed VGM into internal BRAM through
`vgm_file_loader`. The active hardware capacity is `ADDR_WIDTH=18`, or 256 KiB.
This is enough for the small mode5 probes and demo excerpts, but not for the
1 MiB+ `/Users/daizo/Downloads/test.vgm` source file.

The first abstraction step keeps the proven BRAM path but moves
`vgm_loaded_player` away from direct synchronous BRAM reads. The player now uses
a byte-oriented read interface:

```systemverilog
mem_rd_req
mem_rd_addr
mem_rd_ready
mem_rd_valid
mem_rd_data
```

The existing BRAM is connected through `vgm_bram_read_adapter`, which accepts a
byte request, drives the synchronous BRAM read address, and returns valid data
after the BRAM read data has settled.

## Player Contract

The player issues one byte request at a time and waits for a matching valid byte
before advancing the VGM parser FSM. This applies to:

- command fetches
- YM2612, PSG, wait, block, and seek operands
- YM2612 DAC PCM byte reads from the type-0 PCM bank

The VGM parser meaning is unchanged. `0x67` data block handling, `0xE0` PCM
seek, `0x80..0x8f` DAC stream commands, OOB PCM behavior, waits, loops, and END
handling remain player-level behavior.

## Next SDRAM/Streaming Shape

A future large-file backend can replace the BRAM adapter with an SDRAM, DDR, or
streaming cache adapter that implements the same byte-read contract.

Likely backend blocks:

- request arbiter for player byte reads
- sector/cache line fetcher from SDRAM/DDR or HPS-backed storage
- small prefetch FIFO or direct-mapped cache for sequential VGM command reads
- separate handling or shared cache for PCM bank byte reads
- bounds checker using full file size wider than the current BRAM address width

The current player still uses `ADDR_WIDTH` for addresses. A later large-file
step should widen `ADDR_WIDTH` and the loader/file-size plumbing before enabling
files above 256 KiB.

## Timing Notes

The memory backend may add read latency or wait states. The player is expected
to stall only the parser while waiting for `mem_rd_valid`; it must not change
JT12/JT89 internals, genmix, filters, gain, CEN generation, or the VGM wait tick
source.

For command-stream reads, a prefetch cache should hide most latency. For PCM DAC
stream reads, the backend must be able to supply one PCM byte per DAC stream
command at the VGM command rate. If the backend stalls, playback timing will
pause at the parser level; that is acceptable for bring-up but should be avoided
for final large-file playback.

## Bring-Up Steps

1. Keep the existing BRAM adapter as the reference path.
2. Add a wider-address simulation backend with artificial latency and wait
   states.
3. Add a cache or FIFO adapter that presents the same byte-read interface.
4. Widen mode5 file-size/address plumbing once the storage backend can address
   beyond 256 KiB.
5. Only after the storage path is stable, test full 1 MiB+ VGM files.

## Non-Goals For This Step

- No JT12/JT89 changes.
- No genmix, LPF, ladder, CEN, gain, or audio-quality tuning.
- No VGM wait timing changes.
- No PCM/DAC parser semantic changes.
- No mute-gate changes.
- No changes to the known-good fixed-ROM mode3 path.
