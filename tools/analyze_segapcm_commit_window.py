#!/usr/bin/env python3
"""Check whether a VGM ever requests bytes beyond the committed payload.

This is a diagnostic companion to trace_segapcm_hold_path.py.  It applies
the VGM C0 writes at their 44.1 kHz timestamps, advances SegaPCM at
header_clock / 128, and reports the largest cumulative type80 payload index
requested by an enabled channel.
"""

from __future__ import annotations

import argparse
import pathlib

from analyze_segapcm_channel_timing import load_vgm, parse_vgm


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("vgm", type=pathlib.Path)
    parser.add_argument("--committed-length", type=lambda value: int(value, 0))
    args = parser.parse_args()

    data = load_vgm(args.vgm)
    header, blocks, writes = parse_vgm(data)
    clock = int.from_bytes(data[0x38:0x3C], "little")
    interface = int.from_bytes(data[0x3C:0x40], "little")
    bank_mask = 0x70 | ((interface >> 16) & 0xFC)
    bank_shift = interface & 0x0F
    expected = sum(block.payload_len for block in blocks)
    committed = (expected & ~7) if args.committed_length is None else (
        args.committed_length
    )
    states = [
        dict(
            cur_mid=0,
            cur_high=0,
            loop_mid=0,
            loop_high=0,
            end=0,
            delta=0,
            vol_l=0,
            vol_r=0,
            ctrl=1,
            current=0,
        )
        for _ in range(16)
    ]

    write_index = 0
    first_uncommitted: tuple[float, int, int, int, int, int] | None = None
    maximum: tuple[int, float, int, int, int] | None = None
    ticks = (header["total_samples"] * clock // 44_100 + 127) // 128

    for tick in range(ticks):
        vgm_sample = tick * 44_100 * 128 // clock
        while (write_index < len(writes) and (
            writes[write_index].sample_time <= vgm_sample
        )):
            write = writes[write_index]
            state = states[write.channel]
            if write.reg in state:
                state[write.reg] = write.data
            if write.reg in ("cur_mid", "cur_high"):
                state["current"] = (
                    ((state["cur_high"] << 8) | state["cur_mid"]) << 8
                )
            write_index += 1

        time_s = tick * 128 / clock
        for channel, state in enumerate(states):
            if state["ctrl"] & 1:
                continue

            address = (
                ((state["ctrl"] & bank_mask) << bank_shift)
                | ((state["current"] >> 8) & 0xFFFF)
            )
            hit = next(
                (
                    block
                    for block in blocks
                    if block.rom_dest <= address < block.rom_end
                ),
                None,
            )
            if hit is not None:
                payload_index = hit.local_base + address - hit.rom_dest
                if maximum is None or payload_index > maximum[0]:
                    maximum = (
                        payload_index,
                        time_s,
                        channel,
                        address,
                        hit.index,
                    )
                if payload_index >= committed and first_uncommitted is None:
                    source_index = hit.payload_start + address - hit.rom_dest
                    first_uncommitted = (
                        time_s,
                        channel,
                        address,
                        payload_index,
                        hit.index,
                        data[source_index],
                    )

            state["current"] = (
                state["current"] + state["delta"]
            ) & 0xFFFFFF
            if ((state["current"] >> 16) & 0xFF) == state["end"]:
                if state["ctrl"] & 2:
                    state["ctrl"] |= 1
                else:
                    state["current"] = (
                        ((state["loop_high"] << 8) | state["loop_mid"]) << 8
                    )

    print(
        f"duration={header['total_samples'] / 44_100:.6f} "
        f"expected=0x{expected:05X} committed=0x{committed:05X} "
        f"maximum={maximum} first_uncommitted={first_uncommitted}"
    )


if __name__ == "__main__":
    main()
