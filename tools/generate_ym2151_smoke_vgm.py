#!/usr/bin/env python3
"""Generate a tiny original YM2151-write smoke-test VGM.

The generated file is only meant to exercise MegaVGMDrive's experimental
0x54 parser path. It does not contain copyrighted song data.
"""

from __future__ import annotations

import argparse
import struct
from pathlib import Path

SAMPLE_RATE = 44_100
HEADER_SIZE = 0x40
DATA_OFFSET_FIELD = HEADER_SIZE - 0x34


def le32(value: int) -> bytes:
    return struct.pack("<I", value)


def ym2151(reg: int, data: int) -> bytes:
    return bytes((0x54, reg & 0xFF, data & 0xFF))


def wait(samples: int) -> bytes:
    return bytes((0x61, samples & 0xFF, (samples >> 8) & 0xFF))


def build_vgm() -> bytes:
    header = bytearray(HEADER_SIZE)
    header[0x00:0x04] = b"Vgm "
    header[0x08:0x0C] = le32(0x00000150)
    header[0x30:0x34] = le32(4_000_000)  # YM2151 clock field
    header[0x34:0x38] = le32(DATA_OFFSET_FIELD)  # data starts at 0x40

    data = bytearray()
    loop_start = HEADER_SIZE
    data += ym2151(0x08, 0x00)  # key off ch0
    data += ym2151(0x18, 0x00)  # LFO frequency
    data += ym2151(0x19, 0x00)  # PMD/AMD
    data += ym2151(0x1B, 0xC0)  # CT off, saw LFO

    # Channel 0: both outputs, feedback 4, algorithm 7 for an easy smoke tone.
    data += ym2151(0x20, 0xC7)
    data += ym2151(0x28, 0x4A)  # key code
    data += ym2151(0x30, 0x00)  # key fraction

    # Operator slots for channel 0 are spaced by 8 in each operator block.
    for op in (0, 8, 16, 24):
        data += ym2151(0x40 + op, 0x01)  # DT1/MUL
        data += ym2151(0x60 + op, 0x10)  # total level
        data += ym2151(0x80 + op, 0x1F)  # KS/AR
        data += ym2151(0xA0 + op, 0x08)  # AMS enable/D1R
        data += ym2151(0xC0 + op, 0x04)  # DT2/D2R
        data += ym2151(0xE0 + op, 0x0F)  # D1L/RR

    data += wait(SAMPLE_RATE // 10)
    data += ym2151(0x08, 0x78)  # key on ch0
    data += wait(SAMPLE_RATE)
    data += ym2151(0x28, 0x4E)
    data += wait(SAMPLE_RATE)
    data += ym2151(0x08, 0x00)  # key off ch0
    data += wait(SAMPLE_RATE // 10)
    data += bytes((0x66,))

    out = bytes(header) + bytes(data)
    eof_offset = len(out) - 4
    total_samples = (SAMPLE_RATE // 10) + SAMPLE_RATE + SAMPLE_RATE + (SAMPLE_RATE // 10)
    loop_offset = loop_start - 0x1C
    loop_samples = total_samples

    out = (
        out[:0x04] +
        le32(eof_offset) +
        out[0x08:0x18] +
        le32(total_samples) +
        le32(loop_offset) +
        le32(loop_samples) +
        out[0x24:]
    )
    return out


def write_memh(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(f"{byte:02x}\n" for byte in data), encoding="ascii")


def print_summary(path: Path, data: bytes) -> None:
    eof_offset = struct.unpack_from("<I", data, 0x04)[0]
    total_samples = struct.unpack_from("<I", data, 0x18)[0]
    loop_offset = struct.unpack_from("<I", data, 0x1C)[0]
    loop_samples = struct.unpack_from("<I", data, 0x20)[0]
    data_offset = struct.unpack_from("<I", data, 0x34)[0]
    data_start = 0x40 if data_offset == 0 else 0x34 + data_offset
    loop_pc = 0 if loop_offset == 0 else 0x1C + loop_offset
    first16 = " ".join(f"{byte:02x}" for byte in data[data_start:data_start + 16])
    print(f"output: {path}")
    print(f"file_size: {len(data)}")
    print(f"eof_offset: {eof_offset}")
    print(f"total_samples: {total_samples}")
    print(f"loop_offset_field: {loop_offset}")
    print(f"absolute_loop_start: 0x{loop_pc:02x}")
    print(f"loop_samples: {loop_samples}")
    print(f"data_offset_field: {data_offset}")
    print(f"absolute_data_start: 0x{data_start:02x}")
    print(f"first_16_command_bytes: {first16}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "output",
        nargs="?",
        default="testdata/YM2151_SMOKE.VGM",
        help="output VGM path, default: testdata/YM2151_SMOKE.VGM",
    )
    parser.add_argument(
        "--memh",
        help="optional byte-per-line hex dump for SystemVerilog testbenches",
    )
    args = parser.parse_args()

    output = Path(args.output)
    data = build_vgm()
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(data)
    if args.memh:
        write_memh(Path(args.memh), data)
    print_summary(output, data)


if __name__ == "__main__":
    main()
