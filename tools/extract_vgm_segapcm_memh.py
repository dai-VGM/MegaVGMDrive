#!/usr/bin/env python3
"""Extract sparse SegaPCM ROM ranges from VGM type-0x80 blocks as memh."""

from __future__ import annotations

import argparse
import pathlib

from analyze_segapcm_channel_timing import load_vgm, parse_vgm


def parse_range(text: str) -> tuple[int, int]:
    first, last = text.split(":", 1)
    start = int(first, 0)
    end = int(last, 0)
    if end <= start:
        raise argparse.ArgumentTypeError("range end must be greater than start")
    return start, end


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("vgm", type=pathlib.Path)
    parser.add_argument("output", type=pathlib.Path)
    parser.add_argument("--range", dest="ranges", action="append",
                        type=parse_range, required=True,
                        help="full ROM half-open range, e.g. 0x11d100:0x11d900")
    args = parser.parse_args()

    data = load_vgm(args.vgm)
    _header, blocks, _writes = parse_vgm(data)

    def read_rom(address: int) -> int:
        for block in blocks:
            if block.rom_dest <= address < block.rom_end:
                return data[block.payload_start + address - block.rom_dest]
        return 0x80

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="ascii") as stream:
        for start, end in args.ranges:
            # JT exposes a 19-bit {bank,current[23:8]} address. The VGM bank
            # bits occupy the corresponding high region plus bit 20.
            jt_start = start & 0x7ffff
            stream.write(f"@{jt_start:05x}\n")
            for address in range(start, end):
                stream.write(f"{read_rom(address):02x}\n")

    total = sum(end - start for start, end in args.ranges)
    print(f"bytes={total} ranges={len(args.ranges)} output={args.output}")


if __name__ == "__main__":
    main()
