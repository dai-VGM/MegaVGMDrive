#!/usr/bin/env python3
"""Summarize passive RTL captures; numeric results are simulation, not hardware."""
import argparse
import csv
import json
from pathlib import Path


def record(line):
    return {k: int(v) for k, v in (item.split("=") for item in line.split()[1:])}


def main():
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument("log", type=Path)
    parser.add_argument("--csv-dir", type=Path)
    parser.add_argument("--expect-silent", action="store_true")
    args = parser.parse_args()
    samples, events, checks = [], [], []
    for line in args.log.read_text().splitlines():
        if line.startswith("TEARDOWN_SAMPLE "):
            samples.append(record(line))
        elif line.startswith("TEARDOWN_EVENT "):
            events.append(record(line))
        elif line.startswith("TEARDOWN_ZERO_CHECK "):
            checks.append(record(line))
    zero = next(e for e in events if e["session"] == 1 and
                e["released"] and e["gain"] == 0)
    load = next(e for e in events if e["load"] and e["cycle"] >= zero["cycle"])
    handoff = [s for s in samples if zero["cycle"] <= s["cycle"] < load["cycle"]]
    leaks = [s for s in handoff if s["out_l"] or s["out_r"]]
    windows = {
        "last64_before_zero": [s for s in samples if s["cycle"] < zero["cycle"]][-64:],
        "zero_to_load": handoff,
    }
    eof = next((e for e in events if e["session"] == 1 and e["eof"]), None)
    if eof:
        windows["last64_before_eof"] = [s for s in samples if s["cycle"] < eof["cycle"]][-64:]
    result = {
        "zero_event": zero, "next_load_event": load,
        "nonzero_valid_samples_before_load": len(leaks),
        "first_nonzero_before_load": leaks[0] if leaks else None,
        "cycle_zero_check": checks,
        "max_delta_before_load": {
            side: max(handoff, key=lambda s: abs(s["delta_" + side]), default=None)
            for side in ("l", "r")
        },
        "fade_start_events": [e for i, e in enumerate(events) if e["session"] == 1
                              and e["fade"] and (i == 0 or not events[i-1]["fade"])],
    }
    if args.csv_dir:
        args.csv_dir.mkdir(parents=True, exist_ok=True)
        for name, rows in windows.items():
            if rows:
                with (args.csv_dir / (name + ".csv")).open("w", newline="") as output:
                    writer = csv.DictWriter(output, fieldnames=rows[0].keys())
                    writer.writeheader()
                    writer.writerows(rows)
    print(json.dumps(result, indent=2))
    if args.expect_silent:
        assert checks and all(c["violations"] == 0 for c in checks), "cycle-level leak"
        assert not leaks, "nonzero old-session output after zero before load"


if __name__ == "__main__":
    main()
