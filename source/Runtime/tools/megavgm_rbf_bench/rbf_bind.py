#!/usr/bin/env python3
"""Safely bind verified /tmp RBF copies over exact production paths."""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path
import subprocess

from rbf_read_bench import RBF, verify


FAT_ROOT = Path("/media/fat/_Custom Cores/Cores")
TMP_ROOT = Path("/tmp/megavgm-rbf-bench")


def mounted_targets() -> set[str]:
    result: set[str] = set()
    for line in Path("/proc/self/mountinfo").read_text().splitlines():
        fields = line.split()
        if len(fields) >= 5:
            result.add(fields[4].replace("\\040", " ").replace("\\011", "\t"))
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("mount", "unmount", "status"))
    args = parser.parse_args()
    targets = mounted_targets()
    for _, (name, size, expected) in RBF.items():
        target = FAT_ROOT / name
        source = TMP_ROOT / name
        if args.action == "mount":
            if str(target) in targets:
                raise RuntimeError(f"already mounted: {target}")
            verify(target, size, expected)
            verify(source, size, expected)
            subprocess.run(["mount", "--bind", str(source), str(target)], check=True)
            verify(target, size, expected)
            print(f"mounted {source} -> {target}")
        elif args.action == "unmount":
            if str(target) in mounted_targets():
                subprocess.run(["umount", str(target)], check=True)
                print(f"unmounted {target}")
            verify(target, size, expected)
        else:
            state = "RAM_BIND" if str(target) in targets else "FAT"
            verify(target, size, expected)
            print(f"{name} {state} {size} {expected}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
