#!/usr/bin/env python3
"""Export a time-bounded SegaPCM C0-write timeline with channel state."""

from __future__ import annotations

import argparse
import csv
import pathlib
from collections import defaultdict

from analyze_segapcm_channel_timing import (
    CHANNELS,
    Shadow,
    apply_write,
    load_vgm,
    map_block,
    parse_vgm,
    u32le,
)


FIELDS = (
    "time_s", "sample_time", "file_offset", "c0_address", "mapped_address",
    "channel", "register", "data", "same_wait_order_all",
    "same_wait_order_selected", "current_frac", "current_low",
    "current_high", "current_16_8", "loop_low", "loop_high", "loop_16",
    "end", "delta", "volume_l", "volume_r", "control", "bank",
    "full_rom_address", "type80_block", "payload_index", "enabled", "audible",
    "start_retrigger",
)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("vgm", type=pathlib.Path)
    parser.add_argument("--start", type=float, default=85.0)
    parser.add_argument("--end", type=float, default=100.0)
    parser.add_argument("--channels", default="1,2")
    parser.add_argument("--csv", type=pathlib.Path, required=True)
    args = parser.parse_args()

    selected = {int(item, 0) for item in args.channels.split(",")}
    data = load_vgm(args.vgm)
    _header, blocks, writes = parse_vgm(data)
    # VGM 1.51+ stores the SegaPCM interface modifier at 0x3c.  Match
    # MAME's set_bank() decoding instead of assuming the Galaxy Force
    # 0x00f8000d layout for every title.
    interface = u32le(data, 0x3C)
    bank_shift = interface & 0x0F
    bank_mask = 0x70 | ((interface >> 16) & 0xFC)
    # MAME initializes the SegaPCM register RAM/voice fields to 0xff.  In
    # particular, control bit 0 starts disabled; treating it as zero falsely
    # labels setup writes before the first control write as active playback.
    shadows = [Shadow(
        ctrl=0xFF, vol_l=0xFF, vol_r=0xFF, delta=0xFF,
        cur_low=0xFF, cur_mid=0xFF, cur_high=0xFF,
        loop_mid=0xFF, loop_high=0xFF, end=0xFF, ctrl_ext=0xFF,
    ) for _ in range(CHANNELS)]
    current_pair_pending = [False] * CHANNELS
    all_order: defaultdict[int, int] = defaultdict(int)
    selected_order: defaultdict[int, int] = defaultdict(int)
    rows: list[dict[str, object]] = []

    for write in writes:
        ch = write.channel
        before = shadows[ch].copy()
        apply_write(shadows[ch], write.reg, write.data)
        after = shadows[ch].copy()
        order_all = all_order[write.sample_time]
        all_order[write.sample_time] += 1
        order_selected = selected_order[write.sample_time]
        if ch in selected:
            selected_order[write.sample_time] += 1

        marker = ""
        if write.reg == "cur_mid":
            current_pair_pending[ch] = True
            marker = "current_low_write"
        elif write.reg == "cur_high":
            marker = "current_pair_complete" if current_pair_pending[ch] else "current_high_only"
        elif write.reg == "ctrl":
            enabled_edge = bool((before.ctrl & 1) and not (after.ctrl & 1))
            if enabled_edge:
                marker = "control_enable"
            elif current_pair_pending[ch] and after.enabled and after.audible:
                marker = "retrigger_commit"
            elif after.enabled:
                marker = "control_active"
            current_pair_pending[ch] = False
        elif write.reg in ("vol_l", "vol_r") and not before.audible and after.audible:
            marker = "volume_on"

        seconds = write.sample_time / 44100.0
        if ch not in selected or seconds < args.start or seconds > args.end:
            continue

        bank = (after.ctrl & bank_mask) << bank_shift
        full_rom_addr = bank | after.current
        block, offset = map_block(blocks, full_rom_addr)
        payload_index = ""
        if block is not None and offset is not None:
            payload_index = f"0x{block.local_base + offset:05X}"
        rows.append({
            "time_s": f"{seconds:.6f}",
            "sample_time": write.sample_time,
            "file_offset": f"0x{write.pc:06X}",
            "c0_address": f"0x{write.addr:04X}",
            "mapped_address": f"0x{write.mapped:02X}",
            "channel": ch,
            "register": write.reg,
            "data": f"0x{write.data:02X}",
            "same_wait_order_all": order_all,
            "same_wait_order_selected": order_selected,
            "current_frac": f"0x{after.cur_low:02X}",
            "current_low": f"0x{after.cur_mid:02X}",
            "current_high": f"0x{after.cur_high:02X}",
            "current_16_8": f"0x{after.current:04X}{after.cur_low:02X}",
            "loop_low": f"0x{after.loop_mid:02X}",
            "loop_high": f"0x{after.loop_high:02X}",
            "loop_16": f"0x{after.loop:04X}",
            "end": f"0x{after.end:02X}",
            "delta": f"0x{after.delta:02X}",
            "volume_l": f"0x{after.vol_l:02X}",
            "volume_r": f"0x{after.vol_r:02X}",
            "control": f"0x{after.ctrl:02X}",
            "bank": f"0x{bank:05X}",
            "full_rom_address": f"0x{full_rom_addr:06X}",
            "type80_block": "" if block is None else block.index,
            "payload_index": payload_index,
            "enabled": int(after.enabled),
            "audible": int(after.audible),
            "start_retrigger": marker,
        })

    args.csv.parent.mkdir(parents=True, exist_ok=True)
    with args.csv.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(rows)

    print(f"rows={len(rows)} csv={args.csv}")
    for ch in sorted(selected):
        ch_rows = [row for row in rows if row["channel"] == ch]
        starts = [row for row in ch_rows if row["start_retrigger"] in
                  ("control_enable", "retrigger_commit")]
        print(f"ch{ch}: writes={len(ch_rows)} starts={len(starts)}")
        if starts:
            first = starts[0]
            print(
                f"  first={first['time_s']}s pc={first['file_offset']} "
                f"current={first['current_16_8']} block={first['type80_block']}"
            )


if __name__ == "__main__":
    main()
