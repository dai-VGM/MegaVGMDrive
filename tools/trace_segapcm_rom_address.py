#!/usr/bin/env python3
"""Trace MAME-style SegaPCM requests matching a ROM-address low word."""

from __future__ import annotations

import argparse
import pathlib

from analyze_segapcm_channel_timing import load_vgm, parse_vgm


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("vgm", type=pathlib.Path)
    parser.add_argument("address_low", type=lambda value: int(value, 0))
    parser.add_argument("--seconds", type=float, default=40.0)
    parser.add_argument(
        "--exact", action="store_true",
        help="match the complete banked ROM address instead of its low word",
    )
    args = parser.parse_args()

    data = load_vgm(args.vgm)
    _header, blocks, writes = parse_vgm(data)
    clock = int.from_bytes(data[0x38:0x3C], "little")
    interface = int.from_bytes(data[0x3C:0x40], "little")
    bank_mask = 0x70 | ((interface >> 16) & 0xFC)
    bank_shift = interface & 0x0F
    states = [dict(cur_mid=0, cur_high=0, loop_mid=0, loop_high=0,
                   end=0, delta=0, vol_l=0, vol_r=0, ctrl=0,
                   current=0) for _ in range(16)]
    write_index = 0
    pcm_ticks = int(args.seconds * clock / 128)
    matches = 0

    for tick in range(pcm_ticks):
        vgm_sample = tick * 44_100 * 128 // clock
        while (write_index < len(writes) and
               writes[write_index].sample_time <= vgm_sample):
            write = writes[write_index]
            state = states[write.channel]
            state[write.reg] = write.data
            if write.reg in ("cur_mid", "cur_high"):
                state["current"] = (
                    ((state["cur_high"] << 8) | state["cur_mid"]) << 8
                )
            write_index += 1

        for channel, state in enumerate(states):
            if state["ctrl"] & 1:
                continue
            bank = (state["ctrl"] & bank_mask) << bank_shift
            address = bank | ((state["current"] >> 8) & 0xFFFF)
            address_matches = (
                address == args.address_low if args.exact
                else (address & 0xFFFF) == args.address_low
            )
            if address_matches:
                block = next((entry for entry in blocks
                              if entry.rom_dest <= address < entry.rom_end),
                             None)
                payload = None if block is None else (
                    block.local_base + address - block.rom_dest
                )
                print(
                    f"t={tick * 128 / clock:.9f}s tick={tick} ch={channel} "
                    f"ctrl=0x{state['ctrl']:02X} delta=0x{state['delta']:02X} "
                    f"current=0x{state['current']:06X} rom=0x{address:05X} "
                    f"block={'miss' if block is None else block.index} "
                    f"payload={'-' if payload is None else f'0x{payload:05X}'}"
                )
                matches += 1
                if matches >= 32:
                    return

            state["current"] = (state["current"] + state["delta"]) & 0xFFFFFF
            if ((state["current"] >> 16) & 0xFF) == state["end"]:
                if state["ctrl"] & 2:
                    state["ctrl"] |= 1
                else:
                    state["current"] = (
                        ((state["loop_high"] << 8) | state["loop_mid"]) << 8
                    )

    if matches == 0:
        print(f"no match in first {args.seconds:.3f}s")


if __name__ == "__main__":
    main()
