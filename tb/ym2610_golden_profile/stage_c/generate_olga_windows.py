#!/usr/bin/env python3
"""Emit non-copyright Stage C replay-window hashes for Olga Breeze."""

from __future__ import annotations

import hashlib
import json
from dataclasses import replace
from pathlib import Path
import sys

from stage_c_reference import FNV_OFFSET, WriteEvent, hash_event, parse_vgm


EXPECTED_SHA = "7fd15fe7bf9537128bc2eb2db957a8ccf40cdac394675137a40ba2a9daa66246"
REPLAY_AUDIO_HASHES = {
    "first_fm_key_on": "bda45f7a067cf72d",
    "first_sustained_fm": "dc663bb0b7349cd5",
    "mid_song_fm": "184eec59e4466a7d",
    "loop_target_first_pass": "a4a707ca22e4bb61",
    "loop_crossing": "87a5398c48b391c1",
}


def digest(events: list[WriteEvent]) -> dict[str, object]:
    value = FNV_OFFSET
    packed = hashlib.sha256()
    for event in events:
        value = hash_event(value, event)
        packed.update(
            event.command_pc.to_bytes(4, "little")
            + event.sample.to_bytes(4, "little")
            + bytes((event.port, event.address, event.data,
                     event.semantic, int(event.forwarded)))
            + event.next_pc.to_bytes(4, "little")
        )
    return {
        "events": len(events),
        "first_pc": events[0].command_pc,
        "last_pc": events[-1].command_pc,
        "first_sample": events[0].sample,
        "last_sample": events[-1].sample,
        "trace_hash": f"{value:016x}",
        "metadata_sha256": packed.hexdigest(),
    }


def key_on(event: WriteEvent) -> bool:
    return (
        event.forwarded and event.port == 0 and event.address == 0x28
        and event.data & 0xF0 and event.data & 7 in {1, 2, 5, 6}
    )


def nearest_key_index(events: list[WriteEvent], target: int) -> int:
    choices = [index for index, event in enumerate(events) if key_on(event)]
    return min(choices, key=lambda index: abs(events[index].sample - target))


def centered(events: list[WriteEvent], index: int, count: int = 256) -> list[WriteEvent]:
    start = max(0, min(index - count // 2, len(events) - count))
    return events[start:start + count]


def write_trace(path: Path, events: list[WriteEvent]) -> None:
    with path.open("w") as handle:
        for event in events:
            handle.write(
                f"{event.command_pc:08x} {event.sample} {event.port} "
                f"{event.address:02x} {event.data:02x} {event.semantic} "
                f"{int(event.forwarded)} {event.next_pc:08x}\n"
            )


def main() -> int:
    if len(sys.argv) not in {3, 5} or (
        len(sys.argv) == 5 and sys.argv[3] != "--trace"
    ):
        raise SystemExit(
            "usage: generate_olga_windows.py OLGA.vgm OUTPUT.json "
            "[--trace OUTPUT.trace]"
        )
    source = Path(sys.argv[1])
    data = source.read_bytes()
    if hashlib.sha256(data).hexdigest() != EXPECTED_SHA:
        raise SystemExit("Olga source SHA mismatch")
    result, all_events = parse_vgm(data)
    events = [event for event in all_events if event.forwarded]
    targets = {
        "first_fm_key_on": result.first_fm_key_on_sample,
        "first_sustained_fm": result.first_fm_key_on_sample + 441_000,
        "mid_song_fm": result.total_samples // 2,
        "loop_target_first_pass": result.loop_boundary_sample,
    }
    all_index_by_pc = {
        event.command_pc: index for index, event in enumerate(all_events)
    }
    windows = {}
    for name, sample in targets.items():
        center_index = nearest_key_index(events, sample)
        window = centered(events, center_index)
        windows[name] = digest(window)
        windows[name]["arm_trace_event"] = all_index_by_pc[
            events[center_index].command_pc
        ]
    loop_target_events = [
        event for event in events if event.command_pc >= result.loop_target
    ][:128]
    loop_target_events = [
        replace(event, sample=event.sample + result.loop_samples)
        for event in loop_target_events
    ]
    windows["loop_crossing"] = digest(events[-128:] + loop_target_events)
    windows["loop_crossing"]["arm_trace_event"] = all_index_by_pc[
        events[-128].command_pc
    ]
    for name, replay_hash in REPLAY_AUDIO_HASHES.items():
        windows[name]["replay_final_lr_hash"] = replay_hash
        windows[name]["replay_fm_lane_hash"] = replay_hash

    loop_trace: list[WriteEvent] = []
    forwarded = 0
    for event in all_events:
        if event.command_pc < result.loop_target:
            continue
        adjusted = replace(event, sample=event.sample + result.loop_samples)
        loop_trace.append(adjusted)
        if event.forwarded:
            forwarded += 1
            if forwarded == 128:
                break
    extended_trace = all_events + loop_trace
    output = {
        "audio_measurement_contract": (
            "512 public sample rises after nonzero, VGM sample tick accelerated "
            "to one clk, exact 8 MHz header CEN, retained state through loop"
        ),
        "source_sha256": EXPECTED_SHA,
        "forwarded_events": len(events),
        "extended_trace_events": len(extended_trace),
        "window_contract": "256 forwarded events centered on nearest standard FM key-on",
        "windows": windows,
    }
    Path(sys.argv[2]).write_text(json.dumps(output, indent=2, sort_keys=True) + "\n")
    if len(sys.argv) == 5:
        write_trace(Path(sys.argv[4]), extended_trace)
    print(json.dumps(output, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
