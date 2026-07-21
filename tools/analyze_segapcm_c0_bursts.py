#!/usr/bin/env python3
"""Group consecutive SegaPCM C0 writes by VGM time and channel."""

from __future__ import annotations

import argparse
import pathlib
import sys
from itertools import groupby

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from analyze_segapcm_channel_timing import load_vgm, parse_vgm


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("vgm", type=pathlib.Path)
    parser.add_argument("--bursts", type=int, default=20)
    parser.add_argument("--min-writes", type=int, default=2)
    args = parser.parse_args()

    _header, _blocks, writes = parse_vgm(load_vgm(args.vgm))
    shown = 0
    burst_id = 0
    for sample_time, same_time_iter in groupby(writes, key=lambda w: w.sample_time):
        same_time = list(same_time_iter)
        for channel, channel_iter in groupby(same_time, key=lambda w: w.channel):
            channel_writes = list(channel_iter)
            if len(channel_writes) < args.min_writes:
                continue
            first = channel_writes[0]
            last = channel_writes[-1]
            order = " ".join(
                f"{write.reg}={write.data:02X}@{write.pc:06X}"
                for write in channel_writes
            )
            print(
                f"burst={burst_id} sample={sample_time} "
                f"time={sample_time / 44100:.9f} "
                f"seq={first.index}-{last.index} ch={channel} "
                f"writes={len(channel_writes)} order={order}"
            )
            burst_id += 1
            shown += 1
            if shown >= args.bursts:
                return


if __name__ == "__main__":
    main()
