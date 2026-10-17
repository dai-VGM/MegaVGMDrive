#!/usr/bin/env python3
"""Measure cold-ish FAT, warm page-cache, and /tmp RBF reads on MiSTer."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import shutil
import statistics
import time


RBF = {
    "A": ("MegaVGMDrive_A.rbf", 3348228,
          "5755b74d9b1e10e1da1d6c101892bc95ca8960851a851cc9076d1861c9571f1e"),
    "B": ("MegaVGMDrive_B.rbf", 3087284,
          "b435417f268a81a39af6bf2408f364945d151e391425775ab7d01ed4899bec95"),
    "C": ("MegaVGMDrive_C.rbf", 2677792,
          "d6d7bb22beed1366be41b34ab12699cbc3174c46f00705c8f36cd16fd1510dc5"),
}


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def verify(path: Path, size: int, expected: str) -> None:
    if not path.is_file() or path.is_symlink():
        raise RuntimeError(f"not a regular non-symlink file: {path}")
    if path.stat().st_size != size or digest(path) != expected:
        raise RuntimeError(f"frozen RBF mismatch: {path}")


def one_read(path: Path, coldish: bool) -> tuple[float, int, bool]:
    fd = os.open(path, os.O_RDONLY | os.O_CLOEXEC)
    advised = False
    try:
        if coldish and hasattr(os, "posix_fadvise"):
            try:
                os.posix_fadvise(fd, 0, 0, os.POSIX_FADV_DONTNEED)
                advised = True
            except OSError:
                pass
        started = time.monotonic_ns()
        total = 0
        while True:
            block = os.read(fd, 256 * 1024)
            if not block:
                break
            total += len(block)
        elapsed_ms = (time.monotonic_ns() - started) / 1_000_000
        if coldish and advised:
            try:
                os.posix_fadvise(fd, 0, 0, os.POSIX_FADV_DONTNEED)
            except OSError:
                advised = False
        return elapsed_ms, total, advised
    finally:
        os.close(fd)


def stats(values: list[float]) -> dict[str, float]:
    ordered = sorted(values)
    p95 = ordered[max(0, math.ceil(len(ordered) * 0.95) - 1)]
    return {
        "min_ms": min(values),
        "median_ms": statistics.median(values),
        "mean_ms": statistics.mean(values),
        "p95_ms": p95,
        "stdev_ms": statistics.pstdev(values),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--fat-root", type=Path,
                        default=Path("/media/fat/_Custom Cores/Cores"))
    parser.add_argument("--tmp-root", type=Path,
                        default=Path("/tmp/megavgm-rbf-bench"))
    parser.add_argument("--trials", type=int, default=10)
    parser.add_argument("--output", type=Path,
                        default=Path("/tmp/megavgm-rbf-bench/read-results.json"))
    args = parser.parse_args()
    if args.trials < 10:
        raise SystemExit("at least 10 trials are required")
    args.tmp_root.mkdir(mode=0o700, parents=True, exist_ok=True)

    report: dict[str, object] = {
        "clock": "CLOCK_MONOTONIC",
        "trials": args.trials,
        "global_drop_caches": False,
        "coldish_method": "POSIX_FADV_DONTNEED per file when supported",
        "engines": {},
    }
    for profile, (name, size, expected) in RBF.items():
        fat = args.fat_root / name
        ram = args.tmp_root / name
        verify(fat, size, expected)
        with fat.open("rb") as source, ram.open("wb") as destination:
            shutil.copyfileobj(source, destination, 1024 * 1024)
            destination.flush()
            os.fsync(destination.fileno())
        verify(ram, size, expected)

        coldish, warm, tmp = [], [], []
        advice = []
        for _ in range(args.trials):
            value, count, advised = one_read(fat, True)
            if count != size:
                raise RuntimeError("short FAT read")
            coldish.append(value)
            advice.append(advised)
        one_read(fat, False)
        for _ in range(args.trials):
            value, count, _ = one_read(fat, False)
            if count != size:
                raise RuntimeError("short warm FAT read")
            warm.append(value)
        for _ in range(args.trials):
            value, count, _ = one_read(ram, False)
            if count != size:
                raise RuntimeError("short /tmp read")
            tmp.append(value)

        report["engines"][profile] = {
            "name": name,
            "bytes": size,
            "sha256": expected,
            "fat": str(fat),
            "tmp": str(ram),
            "tmp_sha256": digest(ram),
            "coldish_advice_all_trials": all(advice),
            "coldish_fat_ms": coldish,
            "warm_fat_ms": warm,
            "tmp_ms": tmp,
            "coldish_fat_stats": stats(coldish),
            "warm_fat_stats": stats(warm),
            "tmp_stats": stats(tmp),
        }
    args.output.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
