# VGM Inspector

Minimal VGM command inspector for PC/Mac.

This tool reads an uncompressed `.vgm` file and prints a simple log for a small Mega Drive command set:

- `0x52` YM2612 port 0 write
- `0x53` YM2612 port 1 write
- `0x50` SN76489 write
- `0x61` wait n samples
- `0x62` wait 735 samples
- `0x63` wait 882 samples
- `0x70`-`0x7F` short wait
- `0x67` data block
- `0xE0` PCM data bank seek
- `0x80`-`0x8F` YM2612 DAC stream / wait command
- `0x4F` Game Gear stereo command
- `0x66` end

Unsupported for now:

- `.vgz`
- XGM
- PCM / DAC playback
- loop playback

## Build

```sh
cd tools/vgm_inspector
make
```

If you do not want to use `make`:

```sh
c++ -std=c++17 -Wall -Wextra -O2 -o vgm_inspector vgm_inspector.cpp
```

## Usage

```sh
./vgm_inspector path/to/file.vgm
```

To emit SystemVerilog task calls for `tb_md_sound_module.sv`, use:

```sh
./vgm_inspector --emit-sv 64 path/to/file.vgm
```

`--emit-sv N` prints up to `N` sound write commands. YM2612 and SN76489
writes count toward the limit; waits are emitted as `wait_samples(...)` calls
but do not count toward the limit.

To inspect the VGM header, command start, first commands, and YM2612 register
sanity counters, use:

```sh
./vgm_inspector --dump-header --stats --dump-commands 50 path/to/file.vgm
```

Example output:

```text
YM2612 P0 reg=22 data=00
YM2612 P1 reg=B4 data=C0
SN76489 data=9F
WAIT_SHORT 3
YM2612_DAC_STREAM_WAIT 2
DATA_BLOCK type=0x00 size=3
PCM_SEEK offset=305419896
WAIT 735
END

SUMMARY
YM2612 port0 writes: 1
YM2612 port1 writes: 1
SN76489 writes: 1
WAIT commands: 3
WAIT total samples: 740
Short wait commands: 1
Data blocks: 1
PCM seeks: 1
YM2612 DAC stream commands: 1
Game Gear stereo commands: 0
Unsupported commands:
  none
END reached: yes
Total bytes: 80
```

The command log is printed first. A summary is printed at the end with write counts, wait totals, data block counts, PCM seek counts, DAC stream command counts, unsupported command counts, whether `0x66` was reached, and the total number of bytes read from the VGM file.

Example SystemVerilog output:

```systemverilog
send_ym(1'b0, 8'h22, 8'h00);
wait_samples(735);
send_ym(1'b1, 8'hB4, 8'hC0);
send_psg(8'h9F);
// END
```

## Notes

The parser uses the VGM header data offset:

- VGM version `>= 1.50`: data starts at `0x34 + value_at_0x34`
- Older VGM: data starts at `0x40`

The tool is intentionally small and is meant for learning the command flow before looking at NanoDrive6's full player implementation.
