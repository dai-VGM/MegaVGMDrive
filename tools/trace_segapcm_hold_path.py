#!/usr/bin/env python3
"""Compare a libvgm-style SegaPCM oracle with the tagged prefetch path."""

from __future__ import annotations

import argparse
import csv
import pathlib

from analyze_segapcm_channel_timing import load_vgm, parse_vgm


def sat16(value: int) -> int:
    return max(-32768, min(32767, value))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("vgm", type=pathlib.Path)
    parser.add_argument("--seconds", type=float, default=2.0)
    parser.add_argument("--csv", type=pathlib.Path, required=True)
    args = parser.parse_args()

    data = load_vgm(args.vgm)
    _header, blocks, writes = parse_vgm(data)
    clock = int.from_bytes(data[0x38:0x3C], "little")
    interface = int.from_bytes(data[0x3C:0x40], "little")
    bank_mask = 0x70 | ((interface >> 16) & 0xFC)
    bank_shift = interface & 0x0F
    states = [dict(cur_mid=0, cur_high=0, loop_mid=0, loop_high=0,
                   end=0, delta=0, vol_l=0, vol_r=0, ctrl=1,
                   current=0) for _ in range(16)]
    write_index = 0
    rows: list[dict[str, object]] = []
    counts = dict(RR=0, GR=0, NN=0, CN=0, NZ=0, OM=0)
    first_response_mismatch: tuple[float, int] | None = None
    first_consume_mismatch: tuple[float, int] | None = None

    for tick in range(int(args.seconds * clock / 128)):
        vgm_sample = tick * 44_100 * 128 // clock
        while (write_index < len(writes) and
               writes[write_index].sample_time <= vgm_sample):
            write = writes[write_index]
            state = states[write.channel]
            if write.reg in state:
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
            hit = next((block for block in blocks
                        if block.rom_dest <= address < block.rom_end), None)
            any_below = any(address < block.rom_dest for block in blocks)
            any_above = any(address >= block.rom_end for block in blocks)
            gap = hit is None and any_below and any_above
            payload_index = None
            oracle_byte = 0x80
            response_source = "drop"
            response_byte = None

            # Tagged prefetch presents the response for this exact slot. A
            # valid mapped/gap request never falls back to the prior byte.
            consume_byte = 0x80
            if hit is not None:
                payload_index = hit.local_base + address - hit.rom_dest
                oracle_byte = data[hit.payload_start + address - hit.rom_dest]
                response_source = "DDR"
                response_byte = oracle_byte
                counts["RR"] += 1
            elif gap:
                response_source = "GAP"
                response_byte = 0x80
                counts["GR"] += 1

            if response_byte is not None:
                consume_byte = response_byte

            if response_byte is not None and response_byte != 0x80:
                counts["NN"] += 1
            counts["CN"] += 1
            if consume_byte != 0x80:
                counts["NZ"] += 1
            centered = consume_byte - 0x80
            output = sat16(centered * ((state["vol_l"] & 0x7F) +
                                       (state["vol_r"] & 0x7F)))
            if output:
                counts["OM"] += 1

            time_s = tick * 128 / clock
            response_match = response_byte == oracle_byte
            consume_match = consume_byte == oracle_byte
            if not response_match and first_response_mismatch is None:
                first_response_mismatch = (time_s, channel)
            if not consume_match and first_consume_mismatch is None:
                first_consume_mismatch = (time_s, channel)
            rows.append({
                "time": f"{time_s:.9f}",
                "channel": channel,
                "rom_request_address": f"0x{address:05X}",
                "table": f"hit{hit.index}" if hit is not None else
                         ("gap" if gap else "miss"),
                "payload_index": "" if payload_index is None else
                                 f"0x{payload_index:05X}",
                "response_source": response_source,
                "response_byte": "" if response_byte is None else
                                 f"0x{response_byte:02X}",
                "consume_byte": f"0x{consume_byte:02X}",
                "jt_output": output,
                "oracle_byte": f"0x{oracle_byte:02X}",
                "response_match": int(response_match),
                "consume_match": int(consume_match),
            })

            state["current"] = (state["current"] + state["delta"]) & 0xFFFFFF
            if ((state["current"] >> 16) & 0xFF) == state["end"]:
                if state["ctrl"] & 2:
                    state["ctrl"] |= 1
                else:
                    state["current"] = (
                        ((state["loop_high"] << 8) | state["loop_mid"]) << 8
                    )

    args.csv.parent.mkdir(parents=True, exist_ok=True)
    with args.csv.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)

    print(" ".join(f"{name}={min(value, 0xFFFF):04X}"
                   for name, value in counts.items()))
    print("raw " + " ".join(f"{name}={value}" for name, value in counts.items()))
    print(f"rows={len(rows)} csv={args.csv}")
    print(f"first_response_mismatch={first_response_mismatch}")
    print(f"first_consume_mismatch={first_consume_mismatch}")


if __name__ == "__main__":
    main()
