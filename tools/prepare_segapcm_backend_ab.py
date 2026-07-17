#!/usr/bin/env python3
"""Prepare real VGM payload/C0 vectors for the backend A/B RTL trace."""

from __future__ import annotations

import argparse
import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from analyze_segapcm_channel_timing import load_vgm, parse_vgm


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("vgm", type=pathlib.Path)
    parser.add_argument("--out", type=pathlib.Path, required=True)
    parser.add_argument("--seconds", type=float, default=2.0)
    parser.add_argument("--sys-hz", type=int, default=8_053_974)
    args = parser.parse_args()

    data = load_vgm(args.vgm)
    _header, blocks, writes = parse_vgm(data)
    limit = int(args.seconds * 44_100)
    selected = [write for write in writes if write.sample_time <= limit]
    args.out.mkdir(parents=True, exist_ok=True)

    payload = bytearray()
    for block in blocks:
        assert len(payload) == block.local_base
        payload += data[block.payload_start:block.payload_start + block.payload_len]

    with (args.out / "payload.memh").open("w", encoding="ascii") as stream:
        for value in payload:
            stream.write(f"{value:02x}\n")

    with (args.out / "blocks.memh").open("w", encoding="ascii") as stream:
        for block in blocks:
            # [71:51] destination, [50:32] length, [31:13] local base.
            packed = (
                ((block.rom_dest & 0x1fffff) << 51)
                | ((block.payload_len & 0x7ffff) << 32)
                | ((block.local_base & 0x7ffff) << 13)
            )
            stream.write(f"{packed:018x}\n")

    scheduled_cycle = -1
    with (args.out / "events.memh").open("w", encoding="ascii") as stream:
        for write in selected:
            target = write.sample_time * args.sys_hz // 44_100
            # The real player serializes commands which share a VGM timestamp.
            scheduled_cycle = max(target, scheduled_cycle + 1)
            # [63:32] SYS playback cycle, [31:16] C0 address, [15:8] data.
            packed = (
                ((scheduled_cycle & 0xffffffff) << 32)
                | ((write.addr & 0xffff) << 16)
                | ((write.data & 0xff) << 8)
            )
            stream.write(f"{packed:016x}\n")

    metadata = {
        "vgm": str(args.vgm),
        "seconds": args.seconds,
        "sys_hz": args.sys_hz,
        "segapcm_clock": int.from_bytes(data[0x38:0x3c], "little"),
        "interface": int.from_bytes(data[0x3c:0x40], "little"),
        "block_count": len(blocks),
        "payload_length": len(payload),
        "event_count": len(selected),
        "last_cycle": scheduled_cycle,
    }
    (args.out / "metadata.json").write_text(
        json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(metadata, sort_keys=True))


if __name__ == "__main__":
    main()
