#!/usr/bin/env python3
"""Extract concatenated VGM type-0x80 payload bytes into payload-index memh."""

from __future__ import annotations

import argparse
import pathlib

from analyze_segapcm_channel_timing import load_vgm, parse_vgm


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("vgm", type=pathlib.Path)
    parser.add_argument("output", type=pathlib.Path)
    args = parser.parse_args()

    data = load_vgm(args.vgm)
    _header, blocks, _writes = parse_vgm(data)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="ascii") as stream:
        stream.write("@00000\n")
        for block in blocks:
            payload = data[
                block.payload_start:block.payload_start + block.payload_len
            ]
            for value in payload:
                stream.write(f"{value:02x}\n")
            print(
                f"block={block.index} local=0x{block.local_base:05X} "
                f"len=0x{block.payload_len:X} dest=0x{block.rom_dest:05X} "
                f"first={payload[:8].hex(' ')}"
            )

    total = sum(block.payload_len for block in blocks)
    print(f"bytes=0x{total:X} blocks={len(blocks)} output={args.output}")


if __name__ == "__main__":
    main()
