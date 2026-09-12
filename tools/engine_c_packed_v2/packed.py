#!/usr/bin/env python3
"""Host-only MVGMSID Packed v2.0 reference. Frozen C0 is the v1 authority."""
from __future__ import annotations

import argparse
from collections import Counter
from dataclasses import asdict, dataclass
import hashlib
import json
from pathlib import Path
import struct
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'engine_c_c0'))
import mvgmsid as v1

FormatError = v1.FormatError
EOF_TAG = 0xff
ENCODING = 1


def uleb(value: int) -> bytes:
    v1.uint(value, 64, 'delta')
    out = bytearray()
    while value >= 128:
        out.append((value & 127) | 128)
        value >>= 7
    out.append(value)
    return bytes(out)


def read_uleb(raw: bytes, pos: int) -> tuple[int, int]:
    start, value = pos, 0
    for group in range(10):
        if pos >= len(raw):
            raise FormatError('truncated ULEB128')
        byte = raw[pos]
        pos += 1
        if group == 9 and byte > 1:
            raise FormatError('ULEB128 u64 overflow')
        value |= (byte & 127) << (group * 7)
        if not byte & 128:
            if raw[start:pos] != uleb(value):
                raise FormatError('noncanonical ULEB128')
            return value, pos
    raise FormatError('overlong ULEB128')


@dataclass(frozen=True)
class Metadata:
    flags: int = 0
    clock_num: int = 985248
    clock_den: int = 1
    sid_model: int = 1
    timing_standard: int = 1
    subtune_id: int = 1
    stream_cycles: int = 0
    duration_cycles: int = 0
    loop_write_index: int = 0
    loop_start_cycle: int = 0
    loop_end_cycle: int = 0
    source_sha256: bytes = bytes(32)

    def validate(self, write_count: int) -> None:
        # Reuse frozen C0 metadata constraints, not its fixed-record coordinates.
        v1.uint(self.flags, 32, 'flags')
        v1.Header(flags=self.flags & ~v1.LOOP_VALID,
                  clock_num=self.clock_num, clock_den=self.clock_den,
                  sid_model=self.sid_model, timing_standard=self.timing_standard,
                  subtune_id=self.subtune_id, stream_cycles=self.stream_cycles,
                  duration_cycles=self.duration_cycles,
                  source_sha256=self.source_sha256).validate()
        v1.uint(write_count, 64, 'write_count')
        for name in ('loop_write_index', 'loop_start_cycle', 'loop_end_cycle'):
            v1.uint(getattr(self, name), 64, name)
        if self.flags & v1.LOOP_VALID:
            if not self.loop_start_cycle < self.loop_end_cycle == self.stream_cycles:
                raise FormatError('invalid loop cycle range')
            if self.loop_write_index > write_count:
                raise FormatError('loop WRITE ordinal out of range')
        elif any((self.loop_write_index, self.loop_start_cycle, self.loop_end_cycle)):
            raise FormatError('loop metadata without LOOP_VALID')


@dataclass(frozen=True)
class Trace:
    metadata: Metadata
    writes: tuple[tuple[int, int, int], ...]  # absolute cycle, address, data

    def validate(self) -> None:
        m = self.metadata
        m.validate(len(self.writes))
        previous = None
        for cycle, addr, data in self.writes:
            v1.uint(cycle, 64, 'WRITE cycle')
            v1.uint(addr, 8, 'WRITE address')
            v1.uint(data, 8, 'WRITE data')
            if addr > 0x18:
                raise FormatError('invalid SID register')
            if previous is not None and cycle <= previous:
                raise FormatError('same-cycle or unordered WRITE')
            if cycle > m.stream_cycles:
                raise FormatError('WRITE after EOF')
            previous = cycle
        if m.flags & v1.LOOP_VALID:
            i, start = m.loop_write_index, m.loop_start_cycle
            if i and self.writes[i - 1][0] > start:
                raise FormatError('loop excludes WRITE after loop start')
            if i < len(self.writes):
                first = self.writes[i][0]
                if first < start:
                    raise FormatError('loop includes WRITE before loop start')
                if first == start and previous == m.stream_cycles:
                    raise FormatError('same-cycle WRITE across loop boundary')


@dataclass(frozen=True)
class Header:
    metadata: Metadata
    write_count: int
    stream_bytes: int

    def validate(self) -> None:
        self.metadata.validate(self.write_count)
        v1.uint(self.stream_bytes, 64, 'packed stream bytes')
        v1.checked_add(128, self.stream_bytes, 'file size')
        # Every WRITE needs >=3 bytes; EOF >=2. Do not allocate by header count.
        if not 3 * self.write_count + 2 <= self.stream_bytes <= 12 * self.write_count + 11:
            raise FormatError('impossible WRITE count / packed size')

    def encode(self) -> bytes:
        self.validate()
        m, raw = self.metadata, bytearray(128)
        raw[:8] = v1.MAGIC
        struct.pack_into('<4H3I4BI', raw, 8, 2, 0, 128, ENCODING,
                         m.flags, m.clock_num, m.clock_den,
                         m.sid_model, m.timing_standard, 1, 0, m.subtune_id)
        struct.pack_into('<7Q', raw, 0x28, self.write_count, self.stream_bytes,
                         m.stream_cycles, m.duration_cycles, m.loop_write_index,
                         m.loop_start_cycle, m.loop_end_cycle)
        raw[0x60:] = m.source_sha256
        return bytes(raw)

    @classmethod
    def decode(cls, raw: bytes) -> Header:
        if len(raw) != 128 or raw[:8] != v1.MAGIC:
            raise FormatError('bad magic or header length')
        if struct.unpack_from('<4H', raw, 8) != (2, 0, 128, ENCODING):
            raise FormatError('unsupported version/header/encoding')
        if raw[0x1e] != 1 or raw[0x1f] or any(raw[0x24:0x28]):
            raise FormatError('unsupported SID count or nonzero reserved bytes')
        flags, num, den = struct.unpack_from('<3I', raw, 0x10)
        subtune, = struct.unpack_from('<I', raw, 0x20)
        count, size, cycles, duration, ordinal, start, end = struct.unpack_from('<7Q', raw, 0x28)
        result = cls(Metadata(flags, num, den, raw[0x1c], raw[0x1d], subtune,
                              cycles, duration, ordinal, start, end, raw[0x60:]), count, size)
        result.validate()
        return result


def canonical_v1(stream: v1.Stream) -> Trace:
    stream.validate()
    h, writes, cycle, ordinal = stream.header, [], 0, 0
    for index, event in enumerate(stream.events):
        if h.flags & v1.LOOP_VALID and index == h.loop_event_index:
            ordinal = len(writes)
        if event.opcode == v1.WAIT:
            cycle = v1.checked_add(cycle, event.operand, 'v1 cycle')
        elif event.opcode == v1.WRITE:
            writes.append((cycle, event.addr, event.data))
    m = Metadata(h.flags, h.clock_num, h.clock_den, h.sid_model, h.timing_standard,
                 h.subtune_id, h.stream_cycles, h.duration_cycles, ordinal,
                 h.loop_start_cycle, h.loop_end_cycle, h.source_sha256)
    trace = Trace(m, tuple(writes))
    trace.validate()
    return trace


def encode(trace: Trace) -> bytes:
    trace.validate()
    body, previous = bytearray(), 0
    for cycle, addr, data in trace.writes:
        body.extend(uleb(cycle - previous))
        body.extend((addr, data))
        previous = cycle
    body.extend(uleb(trace.metadata.stream_cycles - previous))
    body.append(EOF_TAG)
    return Header(trace.metadata, len(trace.writes), len(body)).encode() + body


def decode(raw: bytes) -> Trace:
    header = Header.decode(raw[:128])
    if len(raw) != 128 + header.stream_bytes:
        raise FormatError('file length mismatch: truncated or trailing data')
    pos, cycle, writes = 128, 0, []
    while pos < len(raw):
        delta, pos = read_uleb(raw, pos)
        cycle = v1.checked_add(cycle, delta, 'absolute cycle')
        if pos >= len(raw):
            raise FormatError('missing register / EOF tag')
        tag, pos = raw[pos], pos + 1
        if tag == EOF_TAG:
            if pos != len(raw):
                raise FormatError('trailing bytes after EOF')
            if len(writes) != header.write_count or cycle != header.metadata.stream_cycles:
                raise FormatError('WRITE count / EOF cycle mismatch')
            trace = Trace(header.metadata, tuple(writes))
            trace.validate()
            return trace
        if tag > 0x18:
            raise FormatError('invalid register / unknown tag')
        if pos >= len(raw):
            raise FormatError('truncated WRITE data')
        if writes and not delta:
            raise FormatError('same-cycle WRITE')
        if len(writes) >= header.write_count:
            raise FormatError('excess WRITE count')
        writes.append((cycle, tag, raw[pos]))
        pos += 1
    raise FormatError('missing EOF')


def pack(raw_v1: bytes) -> bytes:
    trace = canonical_v1(v1.Stream.decode(raw_v1))
    packed = encode(trace)
    if decode(packed) != trace:
        raise FormatError('internal round-trip mismatch')
    return packed


def equivalent(raw_v1: bytes, raw_v2: bytes) -> None:
    a, b = canonical_v1(v1.Stream.decode(raw_v1)), decode(raw_v2)
    if a.metadata != b.metadata:
        raise FormatError('metadata mismatch')
    if len(a.writes) != len(b.writes):
        raise FormatError('WRITE count mismatch')
    for i, (left, right) in enumerate(zip(a.writes, b.writes)):
        if left != right:
            raise FormatError(f'WRITE {i} differs: {left} != {right}')


def inspect(raw: bytes) -> dict:
    trace = decode(raw)
    m, previous, deltas = trace.metadata, 0, []
    for cycle, _, _ in trace.writes:
        deltas.append(cycle - previous)
        previous = cycle
    eof_delta = m.stream_cycles - previous
    meta = asdict(m)
    meta['source_sha256'] = m.source_sha256.hex()
    count = len(trace.writes)
    return dict(metadata=meta, write_count=count, file_bytes=len(raw),
                packed_stream_bytes=len(raw) - 128,
                average_write_record_bytes=(sum(len(uleb(d)) + 2 for d in deltas) / count if count else None),
                maximum_delta=max(deltas + [eof_delta]),
                eof_delta=eof_delta,
                varint_length_histogram=dict(sorted(Counter(len(uleb(d)) for d in deltas + [eof_delta]).items())),
                sha256=hashlib.sha256(raw).hexdigest())


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    p = sub.add_parser('pack')
    p.add_argument('v1', type=Path)
    p.add_argument('-o', '--output', type=Path, required=True)
    for name in ('validate', 'inspect', 'dump'):
        p = sub.add_parser(name)
        p.add_argument('v2', type=Path)
    p = sub.add_parser('compare')
    p.add_argument('v1', type=Path)
    p.add_argument('v2', type=Path)
    args = parser.parse_args()
    try:
        if args.command == 'pack':
            raw = pack(args.v1.read_bytes())
            # Never silently replace a golden input or existing artifact.
            with args.output.open('xb') as out:
                out.write(raw)
        else:
            raw = args.v2.read_bytes()
        if args.command == 'compare':
            equivalent(args.v1.read_bytes(), raw)
            print('All WRITEs, EOF and metadata exactly equivalent')
        elif args.command == 'dump':
            trace = decode(raw)
            print(json.dumps(inspect(raw), sort_keys=True))
            for cycle, addr, data in trace.writes:
                print(json.dumps(dict(cycle=cycle, op='WRITE', addr=addr, data=data)))
            print(json.dumps(dict(cycle=trace.metadata.stream_cycles, op='EOF')))
        else:
            print(json.dumps(inspect(raw), indent=2, sort_keys=True))
        return 0
    except (OSError, FormatError) as exc:
        print(f'ERROR: {exc}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
