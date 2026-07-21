#!/usr/bin/env python3
"""Summarize SegaPCM block use with the VGM header interface bank rule."""

from __future__ import annotations

import argparse
import collections
import csv
import pathlib

from analyze_segapcm_channel_timing import load_vgm, parse_vgm


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("vgm", type=pathlib.Path)
    parser.add_argument("--csv", type=pathlib.Path)
    args = parser.parse_args()

    data = load_vgm(args.vgm)
    _header, blocks, writes = parse_vgm(data)
    interface = int.from_bytes(data[0x3C:0x40], "little")

    regs = [dict(cur_low=0, cur_mid=0, cur_high=0, loop_mid=0,
                 loop_high=0, end=0, delta=0, vol_l=0, vol_r=0,
                 ctrl=1) for _ in range(16)]
    rows: list[dict[str, object]] = []

    def bank_for(control: int) -> int:
        if interface == 0x0C:
            return (control & 0x70) << 12
        if interface == 0x0D:
            return (control & 0xF8) << 13
        return (control & 0x70) << 12

    def emit(write: object, trigger: str) -> None:
        state = regs[write.channel]
        current = (state["cur_high"] << 8) | state["cur_mid"]
        bank = bank_for(state["ctrl"])
        full = bank | current
        hit = next((block for block in blocks
                    if block.rom_dest <= full < block.rom_end), None)
        payload_index = None
        first = ""
        if hit is not None:
            payload_index = hit.local_base + full - hit.rom_dest
            start = hit.payload_start + full - hit.rom_dest
            first = data[start:start + 8].hex(" ").upper()
        rows.append({
            "seconds": write.sample_time / 44100.0,
            "pc": f"0x{write.pc:06X}",
            "channel": write.channel,
            "trigger": trigger,
            "control": f"0x{state['ctrl']:02X}",
            "bank": f"0x{bank:05X}",
            "current": f"0x{current:04X}",
            "loop": f"0x{((state['loop_high'] << 8) | state['loop_mid']):04X}",
            "end": f"0x{state['end']:02X}",
            "delta": f"0x{state['delta']:02X}",
            "vol_l": f"0x{state['vol_l']:02X}",
            "vol_r": f"0x{state['vol_r']:02X}",
            "full_rom": f"0x{full:05X}",
            "block": "" if hit is None else hit.index,
            "block_dest": "" if hit is None else f"0x{hit.rom_dest:05X}",
            "block_len": "" if hit is None else f"0x{hit.payload_len:X}",
            "payload_index": "" if payload_index is None else f"0x{payload_index:05X}",
            "first8": first,
            "active": int((state["ctrl"] & 1) == 0 and
                          state["delta"] != 0 and
                          (state["vol_l"] != 0 or state["vol_r"] != 0)),
        })

    for write in writes:
        state = regs[write.channel]
        if write.reg in state:
            state[write.reg] = write.data
        if write.reg == "cur_high":
            emit(write, "current_high")
        elif write.reg == "ctrl":
            emit(write, "control")

    active_controls = [row for row in rows
                       if row["trigger"] == "control" and row["active"]]
    print(f"interface=0x{interface:08X} events={len(rows)} "
          f"active_control_commits={len(active_controls)}")
    for block in blocks:
        selected = [row for row in active_controls if row["block"] == block.index]
        channels = sorted({int(row["channel"]) for row in selected})
        controls = sorted({str(row["control"]) for row in selected})
        currents = sorted(int(str(row["current"]), 16) for row in selected)
        print(
            f"block={block.index} dest=0x{block.rom_dest:05X} "
            f"base=0x{block.local_base:05X} len=0x{block.payload_len:X} "
            f"uses={len(selected)} ch={channels} ctrl={controls} "
            f"current={('-' if not currents else f'0x{min(currents):04X}..0x{max(currents):04X}') }"
        )
    misses = [row for row in active_controls if row["block"] == ""]
    print(f"active_mapper_misses={len(misses)}")
    for key, count in collections.Counter(
        (row["channel"], row["control"], row["current"], row["full_rom"])
        for row in misses
    ).most_common(20):
        print(f"  miss count={count} ch={key[0]} ctrl={key[1]} "
              f"current={key[2]} full={key[3]}")

    if args.csv:
        args.csv.parent.mkdir(parents=True, exist_ok=True)
        with args.csv.open("w", newline="", encoding="utf-8") as stream:
            writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
            writer.writeheader()
            writer.writerows(rows)
        print(f"csv={args.csv}")


if __name__ == "__main__":
    main()
