#!/usr/bin/env python3
"""Combine MiSTer RBF read and switch measurements."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
import statistics


def stats(values: list[float]) -> dict[str, float]:
    ordered = sorted(values)
    return {
        "min": min(values),
        "median": statistics.median(values),
        "mean": statistics.mean(values),
        "p95": ordered[max(0, math.ceil(len(ordered) * 0.95) - 1)],
        "stdev": statistics.pstdev(values),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--reads", type=Path, required=True)
    parser.add_argument("--fat", type=Path, required=True)
    parser.add_argument("--tmp", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    reads = json.loads(args.reads.read_text())
    fat = json.loads(args.fat.read_text())
    ram = json.loads(args.tmp.read_text())
    pairs = {}
    for pair in ("A-C", "C-A", "B-C", "C-B"):
        left = [result for result in fat["results"]
                if f'{result["from"]}-{result["to"]}' == pair]
        right = [result for result in ram["results"]
                 if f'{result["from"]}-{result["to"]}' == pair]
        metrics = {}
        for metric in left[0]["durations_ms"]:
            fat_stats = stats([result["durations_ms"][metric] for result in left])
            tmp_stats = stats([result["durations_ms"][metric] for result in right])
            delta = fat_stats["median"] - tmp_stats["median"]
            metrics[metric] = {
                "fat": fat_stats,
                "tmp": tmp_stats,
                "median_delta_ms": delta,
                "median_improvement_percent":
                    (delta * 100 / fat_stats["median"] if fat_stats["median"] else 0),
            }
        pairs[pair] = metrics
    result = {
        "schema": "MegaVGMPlayer-RBF-benchmark-analysis-v1",
        "reads": reads,
        "pairs": pairs,
    }
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
