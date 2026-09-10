#!/usr/bin/env python3
"""MVGMSID v1 host validator, codec, inspector and exact timing reference.

No FPGA, importer, profile selection or production runtime integration.
"""
from __future__ import annotations

import argparse
from dataclasses import dataclass
from fractions import Fraction
import json
from pathlib import Path
import struct
import sys
from typing import Iterator

MAGIC = b"MVGMSID\x00"
HEADER_SIZE = 128
EVENT_SIZE = 16
U64_MAX = (1 << 64) - 1
DURATION_KNOWN = 1 << 0
LOOP_VALID = 1 << 1
END_IS_CAPTURE_LIMIT = 1 << 2
MODEL_EXPLICIT_OVERRIDE = 1 << 3
CLOCK_EXPLICIT_OVERRIDE = 1 << 4
KNOWN_FLAGS = (1 << 5) - 1
WAIT, WRITE, EOF = 0x00, 0x01, 0xFF
EVENT_STRUCT = struct.Struct("<BBB5sQ")


class FormatError(ValueError):
    """Malformed, unsupported or internally inconsistent stream."""


def uint(value: int, bits: int, name: str) -> int:
    if type(value) is not int or not 0 <= value < (1 << bits):
        raise FormatError(f"{name}: expected unsigned {bits}-bit integer")
    return value


def checked_add(a: int, b: int, name: str) -> int:
    uint(a, 64, name)
    uint(b, 64, name)
    return uint(a + b, 64, name)


@dataclass(frozen=True)
class Header:
    flags: int = 0
    clock_num: int = 985248
    clock_den: int = 1
    sid_model: int = 1
    timing_standard: int = 1
    subtune_id: int = 1
    event_count: int = 1
    stream_bytes: int = EVENT_SIZE
    stream_cycles: int = 0
    duration_cycles: int = 0
    loop_event_index: int = 0
    loop_start_cycle: int = 0
    loop_end_cycle: int = 0
    source_sha256: bytes = bytes(32)

    def validate(self) -> None:
        for field in ("flags", "clock_num", "clock_den", "subtune_id"):
            uint(getattr(self, field), 32, field)
        for field in ("event_count", "stream_bytes", "stream_cycles",
                      "duration_cycles", "loop_event_index", "loop_start_cycle",
                      "loop_end_cycle"):
            uint(getattr(self, field), 64, field)
        uint(self.sid_model, 8, "sid_model")
        uint(self.timing_standard, 8, "timing_standard")
        if self.flags & ~KNOWN_FLAGS:
            raise FormatError("unknown flags")
        if self.sid_model not in (1, 2) or self.timing_standard not in (1, 2):
            raise FormatError("unknown SID model or timing standard")
        if not self.clock_num or not self.clock_den:
            raise FormatError("clock numerator and denominator must be nonzero")
        if not self.subtune_id:
            raise FormatError("subtune_id must be 1-based")
        if type(self.source_sha256) is not bytes or len(self.source_sha256) != 32:
            raise FormatError("source_sha256 must be 32 bytes")
        if not self.event_count:
            raise FormatError("event_count must include EOF")
        expected = uint(self.event_count * EVENT_SIZE, 64, "stream size product")
        if self.stream_bytes != expected:
            raise FormatError("event_count / stream_bytes mismatch")
        checked_add(HEADER_SIZE, self.stream_bytes, "file size")
        if bool(self.flags & DURATION_KNOWN) != bool(self.duration_cycles):
            raise FormatError("duration flag / duration_cycles mismatch")
        if self.flags & LOOP_VALID:
            if not 0 <= self.loop_start_cycle < self.loop_end_cycle:
                raise FormatError("loop must have positive duration")
            if self.loop_end_cycle != self.stream_cycles:
                raise FormatError("v1 loop must end at stream_cycles")
            if self.loop_event_index >= self.event_count - 1:
                raise FormatError("loop target must precede EOF")
        elif any((self.loop_event_index, self.loop_start_cycle, self.loop_end_cycle)):
            raise FormatError("loop metadata present without LOOP_VALID")

    def encode(self) -> bytes:
        self.validate()
        raw = bytearray(HEADER_SIZE)
        raw[:8] = MAGIC
        struct.pack_into("<HHHHIII4BI", raw, 8, 1, 0, HEADER_SIZE,
                         EVENT_SIZE, self.flags, self.clock_num, self.clock_den,
                         self.sid_model, self.timing_standard, 1, 0, self.subtune_id)
        struct.pack_into("<7Q", raw, 0x28, self.event_count, self.stream_bytes,
                         self.stream_cycles, self.duration_cycles,
                         self.loop_event_index, self.loop_start_cycle, self.loop_end_cycle)
        raw[0x60:0x80] = self.source_sha256
        return bytes(raw)

    @classmethod
    def decode(cls, raw: bytes) -> Header:
        if len(raw) != HEADER_SIZE:
            raise FormatError("truncated or incorrectly sized header")
        if raw[:8] != MAGIC:
            raise FormatError("bad magic")
        major, minor, size, event_size = struct.unpack_from("<4H", raw, 8)
        if (major, minor) != (1, 0):
            raise FormatError("unsupported version (C0 accepts v1.0 only)")
        if (size, event_size) != (HEADER_SIZE, EVENT_SIZE):
            raise FormatError("unsupported header/event size")
        if raw[0x1F] or any(raw[0x24:0x28]):
            raise FormatError("nonzero header reserved fields")
        if raw[0x1E] != 1:
            raise FormatError("v1 supports single SID only")
        flags, num, den = struct.unpack_from("<3I", raw, 0x10)
        subtune, = struct.unpack_from("<I", raw, 0x20)
        header = cls(flags, num, den, raw[0x1C], raw[0x1D], subtune,
                     *struct.unpack_from("<7Q", raw, 0x28), raw[0x60:0x80])
        header.validate()
        return header


@dataclass(frozen=True)
class Event:
    opcode: int
    addr: int = 0
    data: int = 0
    operand: int = 0

    def validate(self) -> None:
        uint(self.opcode, 8, "opcode")
        uint(self.addr, 8, "register address")
        uint(self.data, 8, "register data")
        uint(self.operand, 64, "operand")
        if self.opcode == WRITE:
            if self.addr > 0x18 or self.operand:
                raise FormatError("WRITE requires addr 0x00..0x18 and zero operand")
        elif self.opcode == WAIT:
            if self.addr or self.data or not self.operand:
                raise FormatError("WAIT requires positive cycles and zero addr/data")
        elif self.opcode == EOF:
            if self.addr or self.data or self.operand:
                raise FormatError("EOF payload must be zero")
        else:
            raise FormatError(f"unknown opcode 0x{self.opcode:02x}")

    def encode(self) -> bytes:
        self.validate()
        return EVENT_STRUCT.pack(self.opcode, self.addr, self.data, bytes(5), self.operand)

    @classmethod
    def decode(cls, raw: bytes) -> Event:
        if len(raw) != EVENT_SIZE:
            raise FormatError("truncated event")
        opcode, addr, data, reserved, operand = EVENT_STRUCT.unpack(raw)
        if any(reserved):
            raise FormatError("nonzero event reserved fields")
        event = cls(opcode, addr, data, operand)
        event.validate()
        return event


@dataclass(frozen=True)
class Stream:
    header: Header
    events: tuple[Event, ...]

    def validate(self) -> None:
        self.header.validate()
        if len(self.events) != self.header.event_count:
            raise FormatError("actual event count mismatch")
        cycle = 0
        last_write = None
        target_cycle = None
        first_loop_write = None
        for index, event in enumerate(self.events):
            event.validate()
            if index == self.header.loop_event_index:
                target_cycle = cycle
            if event.opcode == EOF:
                if index != len(self.events) - 1:
                    raise FormatError("EOF must be the final event, exactly once")
            elif index == len(self.events) - 1:
                raise FormatError("missing final EOF")
            if event.opcode == WAIT:
                cycle = checked_add(cycle, event.operand, "WAIT cycle sum")
            elif event.opcode == WRITE:
                if last_write == cycle:
                    raise FormatError(f"same-cycle WRITE at event {index}, cycle {cycle}")
                last_write = cycle
                if index >= self.header.loop_event_index and first_loop_write is None:
                    first_loop_write = cycle
        if cycle != self.header.stream_cycles:
            raise FormatError("WAIT sum / stream_cycles mismatch")
        if self.header.flags & LOOP_VALID:
            if target_cycle != self.header.loop_start_cycle:
                raise FormatError("loop event timestamp / loop_start_cycle mismatch")
            # Also enforce the write invariant across the implicit EOF -> loop jump.
            if last_write == cycle and first_loop_write == self.header.loop_start_cycle:
                raise FormatError("same-cycle WRITE across loop boundary")

    def encode(self) -> bytes:
        self.validate()
        return self.header.encode() + b"".join(event.encode() for event in self.events)

    @classmethod
    def decode(cls, raw: bytes) -> Stream:
        header = Header.decode(raw[:HEADER_SIZE])
        if len(raw) != HEADER_SIZE + header.stream_bytes:
            raise FormatError("file length mismatch (truncated body or trailing bytes)")
        events = tuple(Event.decode(raw[i:i + EVENT_SIZE])
                       for i in range(HEADER_SIZE, len(raw), EVENT_SIZE))
        stream = cls(header, events)
        stream.validate()
        return stream


@dataclass(frozen=True)
class Clock:
    """Exact rational SID frequency; Python integers intentionally do not wrap."""
    num: int
    den: int = 1

    def __post_init__(self) -> None:
        uint(self.num, 32, "clock numerator")
        uint(self.den, 32, "clock denominator")
        if not self.num or not self.den:
            raise FormatError("clock numerator/denominator must be nonzero")

    def transport_position(self, cycles: int) -> tuple[int, int]:
        """Return floor 44.1kHz ticks and remainder with denominator num."""
        uint(cycles, 64, "cycle position")
        return divmod(cycles * 44100 * self.den, self.num)

    def seconds(self, cycles: int) -> Fraction:
        uint(cycles, 64, "cycle position")
        return Fraction(cycles * self.den, self.num)

    def threshold(self, sys_hz: int) -> int:
        uint(sys_hz, 64, "system clock")
        if not sys_hz or self.num > sys_hz * self.den:
            raise FormatError("system clock must permit at most one SID CE per edge")
        return sys_hz * self.den

    def ce_position(self, sys_edges: int, sys_hz: int) -> tuple[int, int]:
        """CE count and accumulator after sys_edges, initial accumulator zero."""
        uint(sys_edges, 64, "system edges")
        return divmod(sys_edges * self.num, self.threshold(sys_hz))

    def ce_edge(self, ordinal: int, sys_hz: int) -> int:
        """1-based system edge emitting the 1-based SID CE ordinal."""
        uint(ordinal, 64, "CE ordinal")
        if not ordinal:
            raise FormatError("CE ordinal must be 1-based")
        return (ordinal * self.threshold(sys_hz) + self.num - 1) // self.num


@dataclass
class FractionalCE:
    clock: Clock
    sys_hz: int
    accumulator: int = 0

    def __post_init__(self) -> None:
        self.clock.threshold(self.sys_hz)
        if type(self.accumulator) is not int or not 0 <= self.accumulator < self.clock.threshold(self.sys_hz):
            raise FormatError("CE accumulator out of range")

    def advance(self, sys_edges: int) -> int:
        uint(sys_edges, 64, "system edges")
        count, self.accumulator = divmod(
            self.accumulator + sys_edges * self.clock.num,
            self.clock.threshold(self.sys_hz))
        return count


@dataclass
class TransportCursor:
    clock: Clock
    cycles: int = 0

    def __post_init__(self) -> None:
        uint(self.cycles, 64, "cycle position")

    def advance(self, cycles: int) -> tuple[int, int]:
        self.cycles = checked_add(self.cycles, cycles, "transport cycle sum")
        return self.clock.transport_position(self.cycles)


@dataclass(frozen=True)
class ScheduledEvent:
    index: int
    iteration: int
    cycle: int
    transport_tick: int
    transport_remainder: int
    event: Event


def schedule(stream: Stream, loop_repeats: int = 0) -> Iterator[ScheduledEvent]:
    """WAIT is timestamped at its start. EOF at a repeated boundary is consumed.

    loop_repeats counts EXTRA traversals of the loop section. It is a bounded
    reference option, not a production loop policy. Absolute time never rebases.
    """
    stream.validate()
    uint(loop_repeats, 64, "loop repeats")
    h = stream.header
    if loop_repeats and not h.flags & LOOP_VALID:
        raise FormatError("loop repeats requested without loop metadata")
    uint(h.stream_cycles + loop_repeats * (h.loop_end_cycle - h.loop_start_cycle),
         64, "expanded timeline")
    clock = Clock(h.clock_num, h.clock_den)
    cycle = index = iteration = 0
    while True:
        event = stream.events[index]
        if event.opcode == EOF and iteration < loop_repeats:
            index = h.loop_event_index
            iteration += 1
            continue
        tick, remainder = clock.transport_position(cycle)
        yield ScheduledEvent(index, iteration, cycle, tick, remainder, event)
        if event.opcode == EOF:
            return
        if event.opcode == WAIT:
            cycle = checked_add(cycle, event.operand, "scheduled cycle")
        index += 1


def inspect(stream: Stream) -> dict:
    stream.validate()
    h = stream.header
    clock = Clock(h.clock_num, h.clock_den)
    def time_value(cycles: int) -> dict:
        value = clock.seconds(cycles)
        return {"cycles": cycles, "seconds_num": value.numerator,
                "seconds_den": value.denominator}
    tick, remainder = clock.transport_position(h.stream_cycles)
    return {
        "format": "MVGMSID", "version": "1.0",
        "model": {1: "6581", 2: "8580"}[h.sid_model],
        "clock": {"num": h.clock_num, "den": h.clock_den, "unit": "Hz"},
        "timing_standard": {1: "PAL", 2: "NTSC"}[h.timing_standard],
        "subtune": h.subtune_id, "flags": h.flags,
        "duration": time_value(h.duration_cycles) if h.flags & DURATION_KNOWN else None,
        "capture_limit": bool(h.flags & END_IS_CAPTURE_LIMIT),
        "loop": {"event_index": h.loop_event_index, "start_cycle": h.loop_start_cycle,
                 "end_cycle": h.loop_end_cycle} if h.flags & LOOP_VALID else None,
        "event_count": h.event_count,
        "write_count": sum(e.opcode == WRITE for e in stream.events),
        "stream_bytes": h.stream_bytes, "final_cycle": h.stream_cycles,
        "stream_duration": time_value(h.stream_cycles),
        "transport_tick": tick, "transport_remainder": remainder,
        "transport_remainder_den": h.clock_num, "source_sha256": h.source_sha256.hex(),
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("artifact", type=Path)
    parser.add_argument("--dump", action="store_true", help="emit timestamped events after JSON summary")
    args = parser.parse_args(argv)
    try:
        stream = Stream.decode(args.artifact.read_bytes())
        print(json.dumps(inspect(stream), indent=2))
        if args.dump:
            for item in schedule(stream):
                event = item.event
                print(f"#{item.index} cycle={item.cycle} tick44100={item.transport_tick} "
                      f"remainder={item.transport_remainder}/{stream.header.clock_num} "
                      f"{ {WAIT: 'WAIT', WRITE: 'WRITE', EOF: 'EOF'}[event.opcode]} "
                      f"addr=0x{event.addr:02x} data=0x{event.data:02x} operand={event.operand}")
    except (OSError, ValueError) as exc:
        print(f"MVGMSID rejected: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
