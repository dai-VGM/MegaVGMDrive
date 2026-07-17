#!/usr/bin/env python3
"""Compare lab/DDR SegaPCM traces after normalizing by consume slot."""

from __future__ import annotations

import argparse
import csv
import pathlib


TIMING_ONLY = {"vgm_sample", "sys_cycle", "response_cycle", "consume_cycle"}


def read(path: pathlib.Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8") as stream:
        return list(csv.DictReader(stream))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("lab", type=pathlib.Path)
    parser.add_argument("ddr", type=pathlib.Path)
    args = parser.parse_args()
    lab = read(args.lab)
    ddr = read(args.ddr)
    shared = min(len(lab), len(ddr))
    fields = [field for field in lab[0] if field not in TIMING_ONLY]
    first = None
    for index in range(shared):
        for field in fields:
            if lab[index][field] != ddr[index][field]:
                first = (index, field, lab[index], ddr[index])
                break
        if first:
            break

    print(f"lab_slots={len(lab)} ddr_slots={len(ddr)} shared={shared}")
    if first is None and len(lab) == len(ddr):
        print("first_difference=none")
        return
    if first is None:
        print(f"first_difference=slot_count lab={len(lab)} ddr={len(ddr)}")
        return
    index, field, lrow, drow = first
    print(f"first_differing_consume_slot={index}")
    print(f"channel={lrow['channel']} rom_address={lrow['rom_request_address']}")
    print(f"first_differing_signal={field}")
    print(f"lab={lrow[field]} ddr={drow[field]}")
    for name in ("response_byte", "consume_byte", "multiply_l", "multiply_r",
                 "channel_contribution_l", "channel_contribution_r",
                 "jt_snd_left", "jt_snd_right", "jt_output_valid",
                 "wrapper_pcm_l", "wrapper_pcm_r"):
        print(f"{name}: lab={lrow[name]} ddr={drow[name]}")


if __name__ == "__main__":
    main()
