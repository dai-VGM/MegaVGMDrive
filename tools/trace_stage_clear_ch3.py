#!/usr/bin/env python3
"""Emit a SegaPCM ch3 reference trace for Stage Clear-style VGM files."""

from __future__ import annotations

import argparse
import csv
import dataclasses
import pathlib
import sys

from analyze_segapcm_vgm import Shadow, load_vgm, parse


def cv_for(sample: int, fmt: str) -> int:
    sample &= 0xFF
    signed8 = sample - 0x100 if sample & 0x80 else sample
    if fmt == "u8":
        return sample - 0x80
    if fmt == "invu8":
        return 0x80 - sample
    if fmt == "s8":
        return signed8
    if fmt == "invs8":
        return -signed8
    raise ValueError(f"unknown format: {fmt}")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("vgm", type=pathlib.Path)
    ap.add_argument("--channel", type=int, default=3)
    ap.add_argument("--block-index", type=int, default=2)
    ap.add_argument("--events", type=int, default=8)
    ap.add_argument("--samples-per-event", type=int, default=64)
    ap.add_argument("--decimate", type=int, default=1)
    ap.add_argument("--mode", choices=("pm3_x4", "mame_exact"),
                    default="pm3_x4")
    ap.add_argument("--delta-shift", type=int, default=2,
                    help="override mode delta shift")
    ap.add_argument("--format", choices=("u8", "invu8", "s8", "invs8"),
                    default="u8")
    ap.add_argument("--csv", type=pathlib.Path)
    args = ap.parse_args()
    if args.mode == "mame_exact" and args.delta_shift == 2:
        args.delta_shift = 0

    data = load_vgm(args.vgm)
    _header, blocks, writes = parse(data)
    type80 = [b for b in blocks if b.block_type == 0x80]
    if args.block_index >= len(type80):
        raise SystemExit(
            f"type80 block index {args.block_index} missing; found {len(type80)}"
        )
    block = type80[args.block_index]
    if block.rom_dest is None:
        raise SystemExit("selected type80 block has no ROM destination")
    payload_start = block.data_start + 8
    payload_len = max(0, block.size - 8)
    payload = data[payload_start:payload_start + payload_len]
    block_dest = block.rom_dest

    shadows = {ch: Shadow() for ch in range(16)}
    events: list[tuple[object, Shadow, int, int, int]] = []
    for w in writes:
        sh = shadows.setdefault(w.channel, Shadow())
        reg = sh.apply(w.mapped, w.data)
        if w.channel != args.channel:
            continue

        event_ctrl = sh.ctrl
        event_current = (sh.cur_high << 8) | sh.cur_mid
        event_bank = (event_ctrl & 0xF8) << 13
        full_addr = event_bank + event_current
        audible = (sh.vol_l & 0x7F) != 0 or (sh.vol_r & 0x7F) != 0
        in_block = block_dest <= full_addr < (block_dest + payload_len)
        retrigger_reg = reg in ("ctrl", "cur_mid", "cur_high", "vol_l", "vol_r")
        if audible and in_block and retrigger_reg:
            snap = Shadow()
            snap.__dict__.update(sh.__dict__)
            events.append((dataclasses.replace(w, reg=reg), snap,
                           event_bank, full_addr, full_addr - block_dest))

    fields = [
        "event", "event_sample_time", "emit", "current_seed", "bank",
        "full_rom_addr", "local_pi", "sb", "cv", "delta_raw",
        "delta_effective", "phase", "frac", "vol_l", "vol_r",
        "end_boundary", "stop",
    ]
    rows: list[dict[str, int | str]] = []
    for event_index, (w, sh, bank, full_addr, local_pi) in enumerate(events[:args.events]):
        raw_delta = sh.delta if sh.delta != 0 else 0xA0
        effective_delta = raw_delta << args.delta_shift
        phase = local_pi << 8
        end_boundary = (
            (sh.end << 8) if args.mode == "mame_exact"
            else (((sh.end + 1) & 0xFF) << 8)
        )
        for emit in range(args.samples_per_event):
            pi = phase >> 8
            frac = phase & 0xFF
            cur_addr = (full_addr + pi - local_pi) & 0x1FFFFF
            stop = "ok"
            if pi >= payload_len:
                stop = "pi>=len"
            elif args.mode == "mame_exact" and (((cur_addr >> 8) & 0xFF) == sh.end):
                stop = "addr_hi==end"
            elif args.mode != "mame_exact" and ((cur_addr & 0xFFFF) >= end_boundary):
                stop = "cur>=end"
            sb = payload[pi] if pi < payload_len else 0x80
            if emit % args.decimate == 0 or emit == args.samples_per_event - 1:
                rows.append({
                    "event": event_index,
                    "event_sample_time": w.sample,
                    "emit": emit,
                    "current_seed": f"0x{((sh.cur_high << 8) | sh.cur_mid):04X}",
                    "bank": f"0x{bank:05X}",
                    "full_rom_addr": f"0x{full_addr:05X}",
                    "local_pi": f"0x{pi:04X}",
                    "sb": f"0x{sb:02X}",
                    "cv": cv_for(sb, args.format),
                    "delta_raw": f"0x{raw_delta:02X}",
                    "delta_effective": f"0x{effective_delta:03X}",
                    "phase": f"0x{phase:07X}",
                    "frac": f"0x{frac:02X}",
                    "vol_l": f"0x{sh.vol_l:02X}",
                    "vol_r": f"0x{sh.vol_r:02X}",
                    "end_boundary": f"0x{end_boundary:04X}",
                    "stop": stop,
                })
            if stop != "ok":
                break
            phase += effective_delta

    out = sys.stdout
    close_out = False
    if args.csv:
        args.csv.parent.mkdir(parents=True, exist_ok=True)
        out = args.csv.open("w", newline="")
        close_out = True
    try:
        writer = csv.DictWriter(out, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)
    finally:
        if close_out:
            out.close()

    print(
        f"trace_rows={len(rows)} events={min(len(events), args.events)} "
        f"type80_block={args.block_index} dest=0x{block_dest:05X} "
        f"payload_len=0x{payload_len:X} mode={args.mode} "
        f"delta_shift={args.delta_shift}",
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
