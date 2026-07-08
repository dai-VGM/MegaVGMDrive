#!/usr/bin/env python3
"""Analyze SegaPCM channel timing and type80 block ownership in a VGM.

The current lab flow needs an offline answer to a simple hardware question:
which C0 channel maps to which captured SegaPCM type80 block, and when should
that channel fire?  This script parses VGM timing, type-0x80 SegaPCM blocks,
and 0xC0 RAM writes, then emits candidate per-channel retrigger events.
"""

from __future__ import annotations

import argparse
import csv
import dataclasses
import gzip
import pathlib
import struct
import wave
from collections import Counter, defaultdict
from typing import Iterable


SAMPLE_RATE = 44_100
CHANNELS = 16


def u32le(data: bytes, off: int) -> int:
    return struct.unpack_from("<I", data, off)[0] if off + 4 <= len(data) else 0


def u16le(data: bytes, off: int) -> int:
    return struct.unpack_from("<H", data, off)[0] if off + 2 <= len(data) else 0


def clamp16(value: int) -> int:
    return max(-32768, min(32767, value))


def cv_invu8(sample: int) -> int:
    return 0x80 - (sample & 0xFF)


@dataclasses.dataclass
class Type80Block:
    index: int
    pc: int
    block_size: int
    rom_size: int
    rom_dest: int
    payload_start: int
    payload_len: int
    local_base: int

    @property
    def local_end(self) -> int:
        return self.local_base + self.payload_len

    @property
    def rom_end(self) -> int:
        return self.rom_dest + self.payload_len


@dataclasses.dataclass
class C0Write:
    index: int
    pc: int
    sample_time: int
    addr: int
    mapped: int
    data: int
    channel: int
    reg: str


@dataclasses.dataclass
class Shadow:
    ctrl: int = 0
    vol_l: int = 0
    vol_r: int = 0
    delta: int = 0
    cur_low: int = 0
    cur_mid: int = 0
    cur_high: int = 0
    loop_mid: int = 0
    loop_high: int = 0
    end: int = 0
    ctrl_ext: int = 0

    def copy(self) -> "Shadow":
        return dataclasses.replace(self)

    @property
    def current(self) -> int:
        return ((self.cur_high & 0xFF) << 8) | (self.cur_mid & 0xFF)

    @property
    def current_alt_high_low(self) -> int:
        return ((self.cur_high & 0xFF) << 8) | (self.cur_low & 0xFF)

    @property
    def loop(self) -> int:
        return ((self.loop_high & 0xFF) << 8) | (self.loop_mid & 0xFF)

    @property
    def end_addr(self) -> int:
        return (self.end & 0xFF) << 8

    @property
    def bank(self) -> int:
        return (self.ctrl & 0xF8) << 13

    @property
    def full_rom_addr(self) -> int:
        return self.bank + self.current

    @property
    def audible(self) -> bool:
        return bool((self.vol_l & 0x7F) or (self.vol_r & 0x7F))

    @property
    def enabled(self) -> bool:
        return (self.ctrl & 0x01) == 0


@dataclasses.dataclass
class Event:
    event_index: int
    write: C0Write
    reason: str
    event_class: str
    strict_start: bool
    prev_ctrl: int
    prev_volume_nonzero: bool
    prev_current: int
    shadow: Shadow
    block: Type80Block | None
    offset: int | None
    block_hit: bool
    role_hint: str
    notes: str


@dataclasses.dataclass
class PM3State:
    active: bool = False
    current: int = 0
    offset: int = 0
    delta: int = 0
    block: Type80Block | None = None
    end_offset: int | None = None
    sample_time: int = 0


@dataclasses.dataclass
class QualifiedCurrentInfo:
    index: int
    event: Event
    active_before: bool
    old_current: int
    new_current: int
    old_offset: int
    new_offset: int
    old_payload_index: int | None
    new_payload_index: int | None
    old_block_index: int | None
    delta_current: int
    class_tags: list[str]


def load_vgm(path: pathlib.Path) -> bytes:
    raw = path.read_bytes()
    if raw[:2] == b"\x1f\x8b":
        raw = gzip.decompress(raw)
    if raw[:4] != b"Vgm ":
        raise SystemExit(f"not a VGM/VGZ file: {path}")
    return raw


def reg_name_for(mapped: int) -> tuple[int, str]:
    channel = (mapped >> 3) & 0x0F
    low_base = mapped & 0x78
    high_base = 0x84 + low_base
    off_low = mapped - low_base
    off_high = mapped - high_base
    low_names = {
        0: "cur_low",
        2: "vol_l",
        3: "vol_r",
        4: "loop_mid",
        5: "loop_high",
        6: "end",
        7: "delta",
    }
    high_names = {
        0: "cur_mid",
        1: "cur_high",
        2: "ctrl",
        3: "ctrl_ext",
    }
    if off_low in low_names:
        return channel, low_names[off_low]
    if off_high in high_names:
        return channel, high_names[off_high]
    return channel, "unknown"


def apply_write(shadow: Shadow, reg: str, data: int) -> None:
    if hasattr(shadow, reg):
        setattr(shadow, reg, data & 0xFF)


def parse_vgm(data: bytes) -> tuple[dict[str, int], list[Type80Block], list[C0Write]]:
    data_rel = u32le(data, 0x34)
    data_off = 0x40 if data_rel == 0 else 0x34 + data_rel
    header = {
        "version": u32le(data, 0x08),
        "eof_absolute": 0x04 + u32le(data, 0x04),
        "total_samples": u32le(data, 0x18),
        "loop_samples": u32le(data, 0x20),
        "data_offset": data_off,
        "parse_end": data_off,
    }

    pc = data_off
    sample_time = 0
    blocks: list[Type80Block] = []
    writes: list[C0Write] = []
    local_base = 0
    unknown = Counter()

    def need(count: int) -> bool:
        return pc + count <= len(data)

    while pc < len(data):
        cmd_pc = pc
        cmd = data[pc]
        pc += 1
        if cmd == 0x66:
            break
        if cmd == 0x61 and need(2):
            sample_time += u16le(data, pc)
            pc += 2
        elif cmd == 0x62:
            sample_time += 735
        elif cmd == 0x63:
            sample_time += 882
        elif 0x70 <= cmd <= 0x7F:
            sample_time += (cmd & 0x0F) + 1
        elif cmd == 0x67 and need(6):
            compat = data[pc]
            block_type = data[pc + 1]
            size = u32le(data, pc + 2)
            block_data_start = pc + 6
            block_data_end = block_data_start + size
            if compat != 0x66:
                unknown[(cmd, compat)] += 1
            if block_type == 0x80 and block_data_start + 8 <= len(data):
                payload_len = max(0, size - 8)
                blocks.append(
                    Type80Block(
                        index=len(blocks),
                        pc=cmd_pc,
                        block_size=size,
                        rom_size=u32le(data, block_data_start),
                        rom_dest=u32le(data, block_data_start + 4),
                        payload_start=block_data_start + 8,
                        payload_len=payload_len,
                        local_base=local_base,
                    )
                )
                local_base += payload_len
            pc = block_data_end
        elif cmd == 0xC0 and need(3):
            lo = data[pc]
            hi = data[pc + 1]
            value = data[pc + 2]
            addr = (hi << 8) | lo
            mapped = addr & 0xFF
            channel, reg = reg_name_for(mapped)
            writes.append(
                C0Write(
                    index=len(writes),
                    pc=cmd_pc,
                    sample_time=sample_time,
                    addr=addr,
                    mapped=mapped,
                    data=value,
                    channel=channel,
                    reg=reg,
                )
            )
            pc += 3
        elif cmd in (0x4F, 0x50, 0x30) and need(1):
            pc += 1
        elif 0x51 <= cmd <= 0x5F and need(2):
            pc += 2
        elif cmd == 0x68 and need(11):
            pc += 11
        elif 0x80 <= cmd <= 0x8F:
            sample_time += cmd & 0x0F
        elif cmd in (0x90, 0x91) and need(4):
            pc += 4
        elif cmd == 0x92 and need(5):
            pc += 5
        elif cmd == 0x93 and need(10):
            pc += 10
        elif cmd == 0x94 and need(1):
            pc += 1
        elif cmd == 0x95 and need(4):
            pc += 4
        elif cmd == 0xA0 and need(2):
            pc += 2
        elif 0xB0 <= cmd <= 0xBF and need(2):
            pc += 2
        elif 0xC1 <= cmd <= 0xCF and need(3):
            pc += 3
        elif 0xD0 <= cmd <= 0xDF and need(3):
            pc += 3
        elif cmd == 0xE0 and need(4):
            pc += 4
        else:
            unknown[(cmd,)] += 1
            break

    header["parse_end"] = pc
    header["unknown_count"] = sum(unknown.values())
    return header, blocks, writes


def map_block(blocks: Iterable[Type80Block], full_addr: int) -> tuple[Type80Block | None, int | None]:
    for block in blocks:
        if block.rom_dest <= full_addr < block.rom_end:
            return block, full_addr - block.rom_dest
    return None, None


def classify_event(reg: str, before: Shadow, after: Shadow) -> str:
    if reg == "ctrl" and before.ctrl & 1 and after.enabled:
        return "ctrl_enable"
    if reg == "ctrl" and after.enabled:
        return "ctrl_write_active"
    if reg in ("vol_l", "vol_r") and not before.audible and after.audible:
        return "volume_on"
    if reg in ("cur_mid", "cur_high") and after.enabled:
        return "current_update_active"
    if reg == "delta" and after.enabled:
        return "delta_update_active"
    return "reg_update"


def role_hint_for(block: Type80Block | None, shadow: Shadow) -> str:
    if block is None:
        return "unknown"
    if block.index == 2 and shadow.current == 0x7100 and shadow.delta == 0xA0:
        return "snare/percussion"
    if block.index == 4:
        return "slap bass/tonal"
    if block.payload_len > 0x2000:
        return "long sample"
    return "unknown"


def reg_category(reg: str) -> str:
    if reg in ("cur_low", "cur_mid", "cur_high"):
        return "current/start"
    if reg == "end":
        return "end"
    if reg == "delta":
        return "delta"
    if reg in ("vol_l", "vol_r"):
        return "volume"
    if reg in ("ctrl", "ctrl_ext"):
        return "control"
    return "other"


def build_events(blocks: list[Type80Block], writes: list[C0Write]) -> tuple[list[Event], list[Shadow]]:
    shadows = [Shadow() for _ in range(CHANNELS)]
    strict_seen = [False] * CHANNELS
    events: list[Event] = []
    for write in writes:
        ch = write.channel
        before = shadows[ch].copy()
        apply_write(shadows[ch], write.reg, write.data)
        after = shadows[ch].copy()
        block, offset = map_block(blocks, after.full_rom_addr)
        block_hit = block is not None
        event_class = classify_event(write.reg, before, after)
        valid_play_state = after.enabled and after.audible and after.current != 0 and block_hit
        strict_start = False
        if valid_play_state:
            if event_class == "ctrl_enable":
                strict_start = True
            elif event_class == "volume_on":
                strict_start = True
            elif not strict_seen[ch]:
                strict_start = True
        if strict_start:
            strict_seen[ch] = True
        notes = []
        if block is None:
            notes.append("no_type80_block_hit")
        if after.current != after.current_alt_high_low:
            notes.append(f"alt_cur_high_low=0x{after.current_alt_high_low:04X}")
        events.append(
            Event(
                event_index=len(events),
                write=write,
                reason=event_class,
                event_class=event_class,
                strict_start=strict_start,
                prev_ctrl=before.ctrl,
                prev_volume_nonzero=before.audible,
                prev_current=before.current,
                shadow=after,
                block=block,
                offset=offset,
                block_hit=block_hit,
                role_hint=role_hint_for(block, after),
                notes=";".join(notes),
            )
        )
    return events, shadows


def estimated_span(event: Event) -> int:
    if event.block is None or event.offset is None:
        return 0
    return max(0, event.block.payload_len - event.offset)


def event_first_raw(data: bytes, event: Event, count: int = 8) -> str:
    if event.block is None or event.offset is None:
        return "-"
    block = event.block
    start = block.payload_start + event.offset
    end = min(block.payload_start + block.payload_len, start + count)
    if start < block.payload_start or start >= block.payload_start + block.payload_len:
        return "-"
    return "".join(f"{byte:02X}" for byte in data[start:end])


def signed16_delta(new: int, old: int) -> int:
    delta = (new & 0xFFFF) - (old & 0xFFFF)
    if delta >= 0x8000:
        delta -= 0x10000
    if delta < -0x8000:
        delta += 0x10000
    return delta


def effective_end_offset(event: Event) -> int | None:
    if event.block is None:
        return None
    end_full = event.shadow.bank + event.shadow.end_addr
    if event.shadow.end_addr and event.block.rom_dest < end_full <= event.block.rom_end:
        return end_full - event.block.rom_dest
    return event.block.payload_len


def advance_pm3_state(state: PM3State, sample_time: int) -> None:
    if not state.active:
        state.sample_time = sample_time
        return
    elapsed = max(0, sample_time - state.sample_time)
    step = (state.delta or 0xA0) << 2
    state.offset += (elapsed * step) >> 8
    if state.end_offset is not None and state.offset >= state.end_offset:
        state.offset = state.end_offset
        state.active = False
    elif state.block is not None and state.offset >= state.block.payload_len:
        state.offset = state.block.payload_len
        state.active = False
    state.sample_time = sample_time


def start_pm3_state(state: PM3State, event: Event) -> None:
    state.active = event.block is not None and event.offset is not None
    state.current = event.shadow.current
    state.offset = event.offset or 0
    state.delta = event.shadow.delta or 0xA0
    state.block = event.block
    state.end_offset = effective_end_offset(event)
    state.sample_time = event.write.sample_time


def classify_qualified_current(info: QualifiedCurrentInfo) -> None:
    event = info.event
    abs_delta = abs(info.delta_current)
    info.class_tags.clear()
    if not info.active_before:
        info.class_tags.append("inactive")
    if event.block is None or event.offset is None:
        info.class_tags.append("unmapped")
    if info.new_current == event.prev_current:
        info.class_tags.append("duplicate_register")
    if info.new_current == info.old_current:
        info.class_tags.append("duplicate_runtime")
    if info.delta_current < 0:
        info.class_tags.append("backward")
    elif info.delta_current > 0:
        info.class_tags.append("forward")
    else:
        info.class_tags.append("same_current")
    if abs_delta <= 0x0200:
        info.class_tags.append("near")
    else:
        info.class_tags.append("far")
    if event.block is not None and event.offset is not None:
        if info.old_block_index == event.block.index:
            info.class_tags.append("same_block")
        elif info.old_block_index is not None:
            info.class_tags.append("block_change")
        end_offset = effective_end_offset(event)
        if end_offset is not None and event.offset >= max(0, end_offset - 0x0200):
            info.class_tags.append("end_near")
        if event.offset >= max(0, event.block.payload_len - 0x0200):
            info.class_tags.append("range_risk")


def build_ch3_qualified_current_infos(events: list[Event]) -> list[QualifiedCurrentInfo]:
    state = PM3State()
    infos: list[QualifiedCurrentInfo] = []
    for event in events:
        if event.write.channel != 3:
            continue
        advance_pm3_state(state, event.write.sample_time)
        is_qualified_current = (
            event.write.reg == "cur_high"
            and event.block_hit
            and event.shadow.enabled
            and event.shadow.audible
            and event.shadow.current != 0
        )
        if is_qualified_current:
            old_payload_index = (
                state.block.local_base + state.offset
                if state.active and state.block is not None else None
            )
            new_payload_index = (
                event.block.local_base + event.offset
                if event.block is not None and event.offset is not None else None
            )
            old_current = (state.current + state.offset) & 0xFFFF if state.active else event.prev_current
            info = QualifiedCurrentInfo(
                index=len(infos),
                event=event,
                active_before=state.active,
                old_current=old_current,
                new_current=event.shadow.current,
                old_offset=state.offset if state.active else 0,
                new_offset=event.offset or 0,
                old_payload_index=old_payload_index,
                new_payload_index=new_payload_index,
                old_block_index=state.block.index if state.active and state.block is not None else None,
                delta_current=signed16_delta(event.shadow.current, old_current),
                class_tags=[],
            )
            classify_qualified_current(info)
            infos.append(info)
            # This mirrors the lab's QualRst interpretation for offline
            # comparison: a qualified current event becomes the new playback
            # origin. Other hardware policies are filters over this set.
            start_pm3_state(state, event)
        elif event.strict_start:
            start_pm3_state(state, event)
    return infos


def write_event_csv(path: pathlib.Path, events: list[Event]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fields = [
        "event_index",
        "pc",
        "sample_time",
        "seconds",
        "channel",
        "addr",
        "mapped",
        "reg",
        "reg_category",
        "value",
        "event_reason",
        "event_class",
        "strict_start",
        "restart_yes",
        "prev_ctrl",
        "prev_volume_nonzero",
        "prev_current",
        "ctrl",
        "vol_l",
        "vol_r",
        "delta",
        "current",
        "loop",
        "end",
        "bank",
        "full_rom_addr",
        "block_index",
        "block_hit",
        "block_dest",
        "block_len",
        "block_offset",
        "estimated_span",
        "role_hint",
        "qs_class",
        "qs_active_before",
        "qs_old_current",
        "qs_new_current",
        "qs_old_payload_index",
        "qs_new_payload_index",
        "qs_delta_current",
        "notes",
    ]
    ch3_qs_by_event = {
        info.event.event_index: info
        for info in build_ch3_qualified_current_infos(events)
    }
    with path.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        for event in events:
            sh = event.shadow
            block = event.block
            qs_info = ch3_qs_by_event.get(event.event_index)
            writer.writerow({
                "event_index": event.event_index,
                "pc": f"0x{event.write.pc:06X}",
                "sample_time": event.write.sample_time,
                "seconds": f"{event.write.sample_time / SAMPLE_RATE:.6f}",
                "channel": event.write.channel,
                "addr": f"0x{event.write.addr:04X}",
                "mapped": f"0x{event.write.mapped:02X}",
                "reg": event.write.reg,
                "reg_category": reg_category(event.write.reg),
                "value": f"0x{event.write.data:02X}",
                "event_reason": event.reason,
                "event_class": event.event_class,
                "strict_start": int(event.strict_start),
                "restart_yes": int(event.strict_start),
                "prev_ctrl": f"0x{event.prev_ctrl:02X}",
                "prev_volume_nonzero": int(event.prev_volume_nonzero),
                "prev_current": f"0x{event.prev_current:04X}",
                "ctrl": f"0x{sh.ctrl:02X}",
                "vol_l": f"0x{sh.vol_l:02X}",
                "vol_r": f"0x{sh.vol_r:02X}",
                "delta": f"0x{sh.delta:02X}",
                "current": f"0x{sh.current:04X}",
                "loop": f"0x{sh.loop:04X}",
                "end": f"0x{sh.end_addr:04X}",
                "bank": f"0x{sh.bank:05X}",
                "full_rom_addr": f"0x{sh.full_rom_addr:05X}",
                "block_index": "" if block is None else block.index,
                "block_hit": int(event.block_hit),
                "block_dest": "" if block is None else f"0x{block.rom_dest:05X}",
                "block_len": "" if block is None else f"0x{block.payload_len:X}",
                "block_offset": "" if event.offset is None else f"0x{event.offset:X}",
                "estimated_span": estimated_span(event),
                "role_hint": event.role_hint,
                "qs_class": "" if qs_info is None else "|".join(qs_info.class_tags),
                "qs_active_before": "" if qs_info is None else int(qs_info.active_before),
                "qs_old_current": "" if qs_info is None else f"0x{qs_info.old_current:04X}",
                "qs_new_current": "" if qs_info is None else f"0x{qs_info.new_current:04X}",
                "qs_old_payload_index": (
                    "" if qs_info is None or qs_info.old_payload_index is None
                    else f"0x{qs_info.old_payload_index:05X}"
                ),
                "qs_new_payload_index": (
                    "" if qs_info is None or qs_info.new_payload_index is None
                    else f"0x{qs_info.new_payload_index:05X}"
                ),
                "qs_delta_current": "" if qs_info is None else qs_info.delta_current,
                "notes": (
                    event.notes if qs_info is None else
                    f"{event.notes};qs={'|'.join(qs_info.class_tags)}"
                ).strip(";"),
            })


def role_guess(ch: int, ch_events: list[Event]) -> str:
    if not ch_events:
        return "unknown"
    blocks = Counter(event.block.index for event in ch_events if event.block is not None)
    currents = Counter(event.shadow.current for event in ch_events)
    deltas = Counter(event.shadow.delta for event in ch_events)
    first = ch_events[0].write.sample_time
    last = ch_events[-1].write.sample_time
    duration = (last - first) / SAMPLE_RATE
    max_vol = max(max(e.shadow.vol_l & 0x7F, e.shadow.vol_r & 0x7F) for e in ch_events)
    gaps = [
        ch_events[i].write.sample_time - ch_events[i - 1].write.sample_time
        for i in range(1, len(ch_events))
    ]
    min_gap = min(gaps) if gaps else 0
    varied_pitch = len([d for d in deltas if d != 0]) >= 3
    if blocks.get(2, 0) and currents.get(0x7100, 0) and deltas.get(0xA0, 0):
        return "snare/percussion"
    if blocks.get(4, 0):
        return "slap bass/tonal"
    if varied_pitch or (len(currents) >= 3 and duration > 1.0):
        return "slap bass/tonal"
    if max(estimated_span(e) for e in ch_events) > 0x2000:
        return "long sample"
    if len(ch_events) >= 4 and min_gap and min_gap < SAMPLE_RATE // 8:
        return "snare/percussion"
    if max_vol:
        return "unknown"
    return "unknown"


def print_summary(data: bytes, header: dict[str, int], blocks: list[Type80Block],
                  writes: list[C0Write], events: list[Event],
                  csv_path: pathlib.Path | None) -> None:
    print("VGM")
    print(f"  version=0x{header['version']:08X}")
    print(f"  data_offset=0x{header['data_offset']:X}")
    print(f"  total_samples={header['total_samples']} seconds={header['total_samples'] / SAMPLE_RATE:.3f}")
    print(f"  C0_writes={len(writes)} type80_blocks={len(blocks)}")
    if csv_path:
        print(f"  csv={csv_path}")
    print()

    print("Type80 Blocks")
    for block in blocks:
        print(
            f"  block{block.index}: dest=0x{block.rom_dest:05X} "
            f"len=0x{block.payload_len:X} local=0x{block.local_base:05X} "
            f"end=0x{block.local_end:05X} pc=0x{block.pc:06X}"
        )
    print()

    print("Channel Summary")
    by_channel: dict[int, list[Event]] = defaultdict(list)
    for event in events:
        by_channel[event.write.channel].append(event)

    for ch in range(CHANNELS):
        ch_events = by_channel.get(ch, [])
        strict_events = [event for event in ch_events if event.strict_start]
        writes_for_ch = [w for w in writes if w.channel == ch]
        if not ch_events and not writes_for_ch:
            continue
        diag_blocks = sorted({e.block.index for e in ch_events if e.block is not None})
        strict_blocks = sorted({e.block.index for e in strict_events if e.block is not None})
        strict_currents = sorted({e.shadow.current for e in strict_events})
        strict_deltas = sorted({e.shadow.delta for e in strict_events})
        max_vol = max(
            [max(e.shadow.vol_l & 0x7F, e.shadow.vol_r & 0x7F) for e in ch_events] or [0]
        )
        if ch_events:
            first = ch_events[0].write.sample_time
            last = ch_events[-1].write.sample_time
            diag_range = f"{first / SAMPLE_RATE:.3f}..{last / SAMPLE_RATE:.3f}s"
            first_diag = f"{first / SAMPLE_RATE:.3f}s"
        else:
            diag_range = "-"
            first_diag = "-"
        first_strict = (
            f"{strict_events[0].write.sample_time / SAMPLE_RATE:.3f}s"
            if strict_events else "-"
        )
        role_events = strict_events if strict_events else ch_events
        print(
            f"  ch{ch:02d}: diag={len(ch_events):4d} strict={len(strict_events):3d} "
            f"first_diag={first_diag:>8} first_strict={first_strict:>8} "
            f"diag_range={diag_range:>17} diag_blocks={diag_blocks or '-'} "
            f"strict_blocks={strict_blocks or '-'} "
            f"strict_currents={[f'0x{x:04X}' for x in strict_currents[:8]]} "
            f"strict_deltas={[f'0x{x:02X}' for x in strict_deltas[:8]]} "
            f"max_vol=0x{max_vol:02X} role={role_guess(ch, role_events)}"
        )
    print()

    print("First Strict Starts")
    strict_all = [event for event in events if event.strict_start]
    for event in strict_all[:64]:
        block_idx = "-" if event.block is None else str(event.block.index)
        offset = "-" if event.offset is None else f"0x{event.offset:X}"
        first8 = event_first_raw(data, event, 8)
        print(
            f"  event{event.event_index:03d} t={event.write.sample_time / SAMPLE_RATE:.3f}s "
            f"ch{event.write.channel:02d} block={block_idx:>2} {event.event_class:21s} "
            f"cur=0x{event.shadow.current:04X} bank=0x{event.shadow.bank:05X} "
            f"full=0x{event.shadow.full_rom_addr:05X} off={offset:>6} "
            f"delta=0x{event.shadow.delta:02X} "
            f"vol={event.shadow.vol_l:02X}/{event.shadow.vol_r:02X} "
            f"first8={first8:16s} role={event.role_hint}"
        )
    print()

    print("Strict Starts Under First 4 Seconds")
    under4 = [event for event in strict_all if event.write.sample_time < 4 * SAMPLE_RATE]
    for event in under4:
        block_idx = "-" if event.block is None else str(event.block.index)
        end_addr = event.shadow.end_addr
        first8 = event_first_raw(data, event, 8)
        print(
            f"  t={event.write.sample_time / SAMPLE_RATE:7.3f}s "
            f"ch{event.write.channel:02d} block={block_idx:>2} "
            f"cur=0x{event.shadow.current:04X} end=0x{end_addr:04X} "
            f"delta=0x{event.shadow.delta:02X} "
            f"vol={event.shadow.vol_l:02X}/{event.shadow.vol_r:02X} "
            f"full=0x{event.shadow.full_rom_addr:05X} "
            f"first8={first8:16s} role={event.role_hint}"
        )
    print()

    print("Candidate Blocks Under First 4 Seconds")
    block_events: dict[int, list[Event]] = defaultdict(list)
    for event in under4:
        if event.block is not None:
            block_events[event.block.index].append(event)
    for block_idx in sorted(block_events):
        block_strict = block_events[block_idx]
        channels = sorted({event.write.channel for event in block_strict})
        first = min(event.write.sample_time for event in block_strict) / SAMPLE_RATE
        currents = sorted({event.shadow.current for event in block_strict})
        deltas = sorted({event.shadow.delta for event in block_strict})
        first_event = min(block_strict, key=lambda event: event.write.sample_time)
        print(
            f"  block{block_idx}: count={len(block_strict):3d} "
            f"first={first:.3f}s channels={channels} "
            f"currents={[f'0x{x:04X}' for x in currents[:8]]} "
            f"deltas={[f'0x{x:02X}' for x in deltas[:8]]} "
            f"first8={event_first_raw(data, first_event, 8):16s} "
            f"role={role_hint_for(first_event.block, first_event.shadow)}"
        )
    print()

    print("Diagnostic Events Under First 2 Seconds")
    for event in [e for e in events if e.write.sample_time < 2 * SAMPLE_RATE]:
        block_idx = "-" if event.block is None else str(event.block.index)
        strict = "S" if event.strict_start else "-"
        print(
            f"  {strict} event{event.event_index:03d} "
            f"t={event.write.sample_time / SAMPLE_RATE:.3f}s "
            f"ch{event.write.channel:02d} block={block_idx:>2} "
            f"{event.event_class:21s} reg={event.write.reg:8s} "
            f"cur=0x{event.shadow.current:04X} "
            f"full=0x{event.shadow.full_rom_addr:05X} "
            f"delta=0x{event.shadow.delta:02X} "
            f"vol={event.shadow.vol_l:02X}/{event.shadow.vol_r:02X}"
        )
    print()

    print_ch3_write_summary(data, writes, events)


def print_ch3_write_summary(data: bytes, writes: list[C0Write],
                            events: list[Event]) -> None:
    ch3_writes = [write for write in writes if write.channel == 3]
    ch3_events = [event for event in events if event.write.channel == 3]
    ch3_restart_events = [event for event in ch3_events if event.strict_start]
    broad_restart_regs = {"cur_mid", "cur_high", "ctrl", "vol_l", "vol_r"}
    # Mirrors the current lab PM3 broad retrigger predicate:
    # current/ctrl/volume writes while mapped, audible, and ctrl-enabled.
    rtl_broad_events = [
        event for event in ch3_events
        if event.write.reg in broad_restart_regs
        and event.block_hit
        and event.shadow.audible
        and event.shadow.enabled
    ]
    write_category_counts = Counter(reg_category(write.reg) for write in ch3_writes)
    restart_category_counts = Counter(reg_category(event.write.reg) for event in ch3_restart_events)
    broad_reg_counts = Counter(event.write.reg for event in rtl_broad_events)
    broad_category_counts = Counter(reg_category(event.write.reg) for event in rtl_broad_events)
    qs_infos = build_ch3_qualified_current_infos(events)
    qs_class_counts = Counter(tag for info in qs_infos for tag in info.class_tags)

    print("Ch3 C0 Write / Restart Summary")
    print(f"  total_writes={len(ch3_writes)}")
    for category in ("current/start", "end", "delta", "volume", "control", "other"):
        print(
            f"  {category:13s}: writes={write_category_counts.get(category, 0):4d} "
            f"restart_yes={restart_category_counts.get(category, 0):3d}"
        )
    print(f"  inferred_true_restarts={len(ch3_restart_events)}")
    print(f"  rtl_broad_pm3_restart_estimate={len(rtl_broad_events)}")
    print(f"  rtl_broad_by_category={dict(sorted(broad_category_counts.items()))}")
    print(f"  rtl_broad_by_reg={dict(sorted(broad_reg_counts.items()))}")
    print(f"  qualified_current_count={len(qs_infos)}")
    print(f"  qualified_current_classes={dict(sorted(qs_class_counts.items()))}")
    if ch3_restart_events:
        first = ch3_restart_events[0].write.sample_time / SAMPLE_RATE
        last = ch3_restart_events[-1].write.sample_time / SAMPLE_RATE
        print(f"  restart_time_range={first:.3f}..{last:.3f}s")
    print()

    print("Ch3 Qualified-Current Events")
    for info in qs_infos:
        event = info.event
        block_idx = "-" if event.block is None else str(event.block.index)
        old_block = "-" if info.old_block_index is None else str(info.old_block_index)
        old_pi = "-" if info.old_payload_index is None else f"0x{info.old_payload_index:05X}"
        new_pi = "-" if info.new_payload_index is None else f"0x{info.new_payload_index:05X}"
        print(
            f"  qs{info.index:02d} t={event.write.sample_time / SAMPLE_RATE:7.3f}s "
            f"pc=0x{event.write.pc:06X} active={int(info.active_before)} "
            f"old_blk={old_block:>2} new_blk={block_idx:>2} "
            f"old_cur=0x{info.old_current:04X} new_cur=0x{info.new_current:04X} "
            f"dcur={info.delta_current:+6d} "
            f"old_off=0x{info.old_offset:04X} new_off=0x{info.new_offset:04X} "
            f"old_pi={old_pi:>7} new_pi={new_pi:>7} "
            f"delta=0x{event.shadow.delta:02X} "
            f"vol={event.shadow.vol_l:02X}/{event.shadow.vol_r:02X} "
            f"ctrl=0x{event.shadow.ctrl:02X} "
            f"class={','.join(info.class_tags)}"
        )
    print()

    print("Ch3 Restart Events")
    for event in ch3_restart_events:
        block_idx = "-" if event.block is None else str(event.block.index)
        first8 = event_first_raw(data, event, 8)
        print(
            f"  t={event.write.sample_time / SAMPLE_RATE:7.3f}s "
            f"pc=0x{event.write.pc:06X} "
            f"addr=0x{event.write.addr:04X}/0x{event.write.mapped:02X} "
            f"reg={event.write.reg:8s} cat={reg_category(event.write.reg):13s} "
            f"val=0x{event.write.data:02X} restart=1 "
            f"class={event.event_class:21s} "
            f"ctrl=0x{event.shadow.ctrl:02X} cur=0x{event.shadow.current:04X} "
            f"end=0x{event.shadow.end_addr:04X} delta=0x{event.shadow.delta:02X} "
            f"vol={event.shadow.vol_l:02X}/{event.shadow.vol_r:02X} "
            f"full=0x{event.shadow.full_rom_addr:05X} block={block_idx:>2} "
            f"first8={first8:16s}"
        )
    print()

    print("Ch3 C0 Write Table")
    for event in ch3_events:
        block_idx = "-" if event.block is None else str(event.block.index)
        restart = 1 if event.strict_start else 0
        print(
            f"  t={event.write.sample_time / SAMPLE_RATE:7.3f}s "
            f"pc=0x{event.write.pc:06X} "
            f"addr=0x{event.write.addr:04X}/0x{event.write.mapped:02X} "
            f"reg={event.write.reg:8s} cat={reg_category(event.write.reg):13s} "
            f"val=0x{event.write.data:02X} restart={restart} "
            f"class={event.event_class:21s} "
            f"ctrl=0x{event.shadow.ctrl:02X} cur=0x{event.shadow.current:04X} "
            f"end=0x{event.shadow.end_addr:04X} delta=0x{event.shadow.delta:02X} "
            f"vol={event.shadow.vol_l:02X}/{event.shadow.vol_r:02X} "
            f"full=0x{event.shadow.full_rom_addr:05X} block={block_idx:>2}"
        )


def render_channel_wavs(data: bytes, events: list[Event], out_dir: pathlib.Path,
                        max_seconds: float, suffix: str) -> None:
    total_samples = max((e.write.sample_time for e in events), default=0)
    total_samples += int(max_seconds * SAMPLE_RATE)
    total_samples = max(total_samples, SAMPLE_RATE)
    events_by_ch: dict[int, list[Event]] = defaultdict(list)
    for event in events:
        if event.block is not None and event.offset is not None:
            events_by_ch[event.write.channel].append(event)

    out_dir.mkdir(parents=True, exist_ok=True)
    for ch in range(CHANNELS):
        samples = [0] * total_samples
        for event in events_by_ch.get(ch, []):
            block = event.block
            if block is None or event.offset is None:
                continue
            payload = data[block.payload_start:block.payload_start + block.payload_len]
            phase = event.offset << 8
            delta = (event.shadow.delta or 0xA0) << 2
            gain = max(event.shadow.vol_l & 0x7F, event.shadow.vol_r & 0x7F)
            limit = min(total_samples, event.write.sample_time + int(max_seconds * SAMPLE_RATE))
            t = event.write.sample_time
            while t < limit:
                pi = phase >> 8
                if pi < 0 or pi >= len(payload):
                    break
                sample = cv_invu8(payload[pi]) * gain
                samples[t] = clamp16(samples[t] + sample)
                phase += delta
                t += 1
        path = out_dir / f"segapcm_ch{ch:02d}_{suffix}_pm3.wav"
        with wave.open(str(path), "wb") as wav:
            wav.setnchannels(1)
            wav.setsampwidth(2)
            wav.setframerate(SAMPLE_RATE)
            wav.writeframes(b"".join(struct.pack("<h", s) for s in samples))


def print_pm3_probe(data: bytes, blocks: list[Type80Block], full_addr: int,
                    delta: int, count: int, invert: bool,
                    vol_l: int, vol_r: int, output_shift: int) -> None:
    block, offset = map_block(blocks, full_addr)
    print()
    print("PM3 Probe")
    if block is None or offset is None:
        print(f"  full=0x{full_addr:05X} no type80 block hit")
        return
    payload = data[block.payload_start:block.payload_start + block.payload_len]
    seq = payload[offset:offset + count]
    print(
        f"  full=0x{full_addr:05X} block={block.index} "
        f"dest=0x{block.rom_dest:05X} offset=0x{offset:X} "
        f"local=0x{block.local_base + offset:05X} delta=0x{delta:02X} "
        f"polarity={'invert' if invert else 'normal'} "
        f"vol_l=0x{vol_l & 0x7f:02X} vol_r=0x{vol_r & 0x7f:02X} "
        f"out_shift={min(max(output_shift, 0), 3)}"
    )
    print("  sequential_raw:")
    print("   ", " ".join(f"{b:02X}" for b in seq))
    phase = offset << 8
    step = (delta & 0xFF) << 2
    out_shift = min(max(output_shift, 0), 3)
    consumed: list[tuple[int, int, int, int, int, int, int, int]] = []
    for _ in range(count):
        pi = phase >> 8
        if pi < 0 or pi >= len(payload):
            break
        raw = payload[pi]
        cv = (0x80 - raw) if invert else (raw - 0x80)
        out_l = (cv * (vol_l & 0x7f)) >> out_shift
        out_r = (cv * (vol_r & 0x7f)) >> out_shift
        current = (full_addr + pi - offset) & 0xffff
        payload_index = block.local_base + pi
        consumed.append((pi, phase & 0xFF, raw, cv, current,
                         payload_index, out_l, out_r))
        phase += step
    print("  pm3_consumed:")
    print(
        "    idx current payload_i off frac raw   cv   vol_l vol_r "
        "out_l  out_r"
    )
    for i, (pi, frac, raw, cv, current, payload_index, out_l, out_r) in enumerate(consumed):
        print(
            f"    {i:02d}: 0x{current:04X} 0x{payload_index:05X} "
            f"0x{pi:04X} 0x{frac:02X} 0x{raw:02X} "
            f"{cv:+4d} 0x{vol_l & 0x7f:02X} 0x{vol_r & 0x7f:02X} "
            f"0x{out_l & 0xffff:04X} 0x{out_r & 0xffff:04X}"
        )
    packed_raw = []
    packed_dec = []
    for i in range(0, min(16, len(consumed)), 2):
        raw0 = consumed[i][2]
        raw1 = consumed[i + 1][2] if i + 1 < len(consumed) else 0
        cv0 = consumed[i][3] & 0xFF
        cv1 = consumed[i + 1][3] & 0xFF if i + 1 < len(consumed) else 0
        packed_raw.append((raw0 << 8) | raw1)
        packed_dec.append((cv0 << 8) | cv1)
    print("  expected_overlay:")
    for i, value in enumerate(packed_raw):
        print(f"    S{i}=0x{value:04X}")
    for i, value in enumerate(packed_dec):
        print(f"    D{i}=0x{value:04X}")
    print("  expected_rv001e_first4:")
    for i, (_pi, _frac, raw, cv, current, payload_index, out_l, _out_r) in enumerate(consumed[:4]):
        print(
            f"    F{i}=0x{((raw << 8) | (cv & 0xff)):04X} "
            f"A{i}=0x{current:04X} I{i}=0x{payload_index & 0xffff:04X} "
            f"O{i}=0x{out_l & 0xffff:04X}"
        )


def main() -> None:
    parser = argparse.ArgumentParser(
        epilog=(
            "Examples:\n"
            "  python3 tools/analyze_segapcm_channel_timing.py "
            "\"/Users/daizo/Downloads/09 Stage Clear.vgm\" "
            "--csv /tmp/segapcm_channel_events.csv\n"
            "  python3 tools/analyze_segapcm_channel_timing.py "
            "\"/Users/daizo/Downloads/09 Stage Clear.vgm\" "
            "--strict-wavs --wav-dir /tmp/segapcm_stageclear\n"
            "  python3 tools/analyze_segapcm_channel_timing.py "
            "\"/Users/daizo/Downloads/09 Stage Clear.vgm\" "
            "--probe-pm3 --probe-full-addr 0x17100 --probe-delta 0xA0"
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("vgm", type=pathlib.Path)
    parser.add_argument("--csv", type=pathlib.Path,
                        default=pathlib.Path("/tmp/segapcm_channel_events.csv"))
    parser.add_argument("--render-wavs", action="store_true",
                        help="legacy alias for --all-event-wavs")
    parser.add_argument("--strict-wavs", action="store_true",
                        help="render per-channel WAVs from strict starts only")
    parser.add_argument("--all-event-wavs", action="store_true",
                        help="render per-channel WAVs from all diagnostic events")
    parser.add_argument("--wav-dir", type=pathlib.Path, default=pathlib.Path("/tmp"))
    parser.add_argument("--wav-event-seconds", type=float, default=0.35)
    parser.add_argument("--probe-pm3", action="store_true",
                        help="print expected PM3 consumed bytes/CV for a full ROM address")
    parser.add_argument("--probe-full-addr", type=lambda s: int(s, 0),
                        default=0x17100)
    parser.add_argument("--probe-delta", type=lambda s: int(s, 0),
                        default=0xA0)
    parser.add_argument("--probe-count", type=int, default=16)
    parser.add_argument("--probe-normal-polarity", action="store_true",
                        help="use normal u8 center instead of the lab's invert default")
    parser.add_argument("--probe-vol-l", type=lambda s: int(s, 0),
                        default=0x3f)
    parser.add_argument("--probe-vol-r", type=lambda s: int(s, 0),
                        default=0x3f)
    parser.add_argument("--probe-output-shift", type=int, default=1,
                        help="PM3 internal output shift; RTL default is 1")
    args = parser.parse_args()

    data = load_vgm(args.vgm)
    header, blocks, writes = parse_vgm(data)
    events, _shadows = build_events(blocks, writes)
    write_event_csv(args.csv, events)
    print_summary(data, header, blocks, writes, events, args.csv)
    if args.strict_wavs:
        strict_events = [event for event in events if event.strict_start]
        render_channel_wavs(data, strict_events, args.wav_dir,
                            args.wav_event_seconds, "strict")
        print()
        print(f"Rendered strict PM3 channel WAVs to {args.wav_dir}/segapcm_chXX_strict_pm3.wav")
    if args.all_event_wavs or args.render_wavs:
        render_channel_wavs(data, events, args.wav_dir,
                            args.wav_event_seconds, "all")
        print()
        print(f"Rendered all-event PM3 channel WAVs to {args.wav_dir}/segapcm_chXX_all_pm3.wav")
    if args.probe_pm3:
        print_pm3_probe(data, blocks, args.probe_full_addr, args.probe_delta,
                        args.probe_count, not args.probe_normal_polarity,
                        args.probe_vol_l, args.probe_vol_r,
                        args.probe_output_shift)


if __name__ == "__main__":
    main()
