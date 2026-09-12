from dataclasses import replace
from pathlib import Path
import random
import struct
import subprocess
import sys
import tempfile
import unittest

import packed as p

v = p.v1


def stream(events, **metadata):
    events = tuple(events)
    cycles = sum(e.operand for e in events if e.opcode == v.WAIT)
    return v.Stream(v.Header(event_count=len(events), stream_bytes=16 * len(events),
                             stream_cycles=cycles, **metadata), events)


def wire(body, count=0, cycles=0):
    # Build intentionally malformed bodies without changing the golden codec.
    raw = bytearray(p.encode(p.Trace(p.Metadata(), ())))
    struct.pack_into('<3Q', raw, 0x28, count, len(body), cycles)
    return bytes(raw[:128]) + body


class PackedTests(unittest.TestCase):
    def roundtrip(self, s):
        original = s.encode()
        raw = p.pack(original)
        p.equivalent(original, raw)
        self.assertEqual(p.decode(raw), p.canonical_v1(s))
        self.assertEqual(raw, p.pack(original))
        self.assertEqual(raw, p.encode(p.decode(raw)))
        return raw

    def test_first_write_zero_and_same_value_init_writes(self):
        raw = self.roundtrip(stream([v.Event(v.WRITE, 4, 17), v.Event(v.WAIT, operand=1),
                                     v.Event(v.WRITE, 4, 17), v.Event(v.EOF)]))
        self.assertEqual(raw[128:], b'\x00\x04\x11\x01\x04\x11\x00\xff')

    def test_delta_boundaries(self):
        for delta in (1, 127, 128, 16383, 16384, 1 << 32, 1 << 63, v.U64_MAX):
            with self.subTest(delta=delta):
                self.roundtrip(stream([v.Event(v.WAIT, operand=delta),
                                       v.Event(v.WRITE, 0x18, 255), v.Event(v.EOF)]))
                self.assertEqual(p.read_uleb(p.uleb(delta), 0), (delta, len(p.uleb(delta))))
        for delta, encoded in ((0, b'\x00'), (127, b'\x7f'), (128, b'\x80\x01'),
                               (16383, b'\xff\x7f'), (16384, b'\x80\x80\x01')):
            self.assertEqual(p.uleb(delta), encoded)

    def test_eof_only(self):
        self.assertEqual(self.roundtrip(stream([v.Event(v.EOF)]))[128:], b'\x00\xff')

    def test_final_wait_and_split_waits(self):
        s = stream([v.Event(v.WAIT, operand=2), v.Event(v.WAIT, operand=3),
                    v.Event(v.WRITE, 1, 2), v.Event(v.WAIT, operand=20000), v.Event(v.EOF)])
        raw = self.roundtrip(s)
        self.assertEqual(p.inspect(raw)['eof_delta'], 20000)
        self.assertEqual(p.decode(raw).metadata.stream_cycles, 20005)

    def test_metadata_all_flags_and_models(self):
        for model in (1, 2):
            for timing in (1, 2):
                self.roundtrip(stream([v.Event(v.WAIT, operand=100), v.Event(v.EOF)],
                    flags=v.DURATION_KNOWN | v.END_IS_CAPTURE_LIMIT |
                          v.MODEL_EXPLICIT_OVERRIDE | v.CLOCK_EXPLICIT_OVERRIDE,
                    duration_cycles=123, sid_model=model, timing_standard=timing,
                    clock_num=2045454, clock_den=2, subtune_id=9,
                    source_sha256=bytes(range(32))))

    def test_loop_wait_target_and_replay(self):
        events = [v.Event(v.WRITE, 1, 2), v.Event(v.WAIT, operand=10),
                  v.Event(v.WAIT, operand=20), v.Event(v.WRITE, 1, 3),
                  v.Event(v.WAIT, operand=40), v.Event(v.EOF)]
        s = stream(events, flags=v.LOOP_VALID, loop_event_index=2,
                   loop_start_cycle=10, loop_end_cycle=70)
        t = p.decode(self.roundtrip(s))
        self.assertEqual(t.metadata.loop_write_index, 1)
        golden = [(e.cycle, e.event.addr, e.event.data) for e in v.schedule(s, loop_repeats=3)
                  if e.event.opcode == v.WRITE]
        replay = list(t.writes)
        for iteration in range(1, 4):
            replay.extend((cycle + iteration * 60, addr, data)
                          for cycle, addr, data in t.writes[1:])
        self.assertEqual(golden, replay)

    def test_loop_excludes_write_at_start(self):
        s = stream([v.Event(v.WRITE, 1, 2), v.Event(v.WAIT, operand=10),
                    v.Event(v.WRITE, 1, 3), v.Event(v.WAIT, operand=20), v.Event(v.EOF)],
                   flags=v.LOOP_VALID, loop_event_index=1, loop_start_cycle=0,
                   loop_end_cycle=30)
        self.assertEqual(p.decode(self.roundtrip(s)).metadata.loop_write_index, 1)

    def test_loop_no_remaining_writes(self):
        for events, target in (([v.Event(v.WAIT, operand=10), v.Event(v.EOF)], 0),
                               ([v.Event(v.WRITE, 0, 0), v.Event(v.WAIT, operand=10), v.Event(v.EOF)], 1)):
            s = stream(events, flags=v.LOOP_VALID, loop_event_index=target,
                       loop_start_cycle=0, loop_end_cycle=10)
            self.roundtrip(s)

    def test_loop_rejects_inconsistent_and_boundary_collision(self):
        good = p.Trace(p.Metadata(flags=v.LOOP_VALID, stream_cycles=10,
                                  loop_start_cycle=1, loop_end_cycle=10), ((1, 0, 0),))
        for m in (replace(good.metadata, loop_write_index=2),
                  replace(good.metadata, loop_write_index=1, loop_start_cycle=0),
                  replace(good.metadata, loop_start_cycle=2),
                  replace(good.metadata, loop_end_cycle=9),
                  replace(good.metadata, flags=0)):
            with self.assertRaises(p.FormatError):
                p.encode(p.Trace(m, good.writes))
        with self.assertRaisesRegex(p.FormatError, 'boundary'):
            p.encode(p.Trace(good.metadata, ((1, 0, 0), (10, 0, 0))))

    def test_same_cycle_rejects_v1_and_v2(self):
        with self.assertRaises(p.FormatError):
            p.pack(stream([v.Event(v.WRITE), v.Event(v.WRITE), v.Event(v.EOF)]).encode())
        with self.assertRaisesRegex(p.FormatError, 'same-cycle'):
            p.decode(wire(b'\x00\x00\x00\x00\x00\x00\x00\xff', count=2))

    def test_bad_varints(self):
        cases = (b'\x80', b'\x80\x00', b'\x81\x00', b'\x80' * 9 + b'\x02',
                 b'\x80' * 10 + b'\x01', b'\xff' * 10, b'\x80' * 9 + b'\x00')
        for raw in cases:
            with self.subTest(raw=raw), self.assertRaises(p.FormatError):
                p.read_uleb(raw, 0)

    def test_bad_records(self):
        for body, count in ((b'\x00\x19\x00\x00\xff', 1),  # invalid register
                            (b'\x00\xfe\x00\x00\xff', 1),
                            (b'\x00\xff\x00', 0),  # trailing data after EOF
                            (b'\x00\x00\x01', 1),  # missing EOF
                            (b'\x80\x00\xff', 0),  # overlong delta
                            (b'\x00\xff\x00\xff', 0),
                            (b'\x00\x00\x00\x01\x01', 1)):
            with self.subTest(body=body), self.assertRaises(p.FormatError):
                p.decode(wire(body, count))

    def test_all_truncations(self):
        raw = self.roundtrip(stream([v.Event(v.WAIT, operand=16384), v.Event(v.WRITE, 3, 4),
                                     v.Event(v.WAIT, operand=8), v.Event(v.EOF)]))
        for n in range(len(raw)):
            with self.subTest(n=n), self.assertRaises(p.FormatError):
                p.decode(raw[:n])
        with self.assertRaises(p.FormatError):
            p.decode(raw + b'\x00')

    def test_header_mutations(self):
        raw = self.roundtrip(stream([v.Event(v.EOF)]))
        for offset, data in ((0, b'x'), (8, b'\x01'), (10, b'\x01'), (12, b'\x7f'),
                             (14, b'\x10'), (16, b'\x20'), (20, bytes(4)),
                             (24, bytes(4)), (28, b'\x00'), (29, b'\x03'),
                             (30, b'\x02'), (31, b'\x01'), (32, bytes(4)),
                             (36, b'\x01'), (40, b'\x01'), (48, b'\x03'),
                             (56, b'\x01'), (64, b'\x01'), (72, b'\x01')):
            corrupt = bytearray(raw)
            corrupt[offset:offset + len(data)] = data
            with self.subTest(offset=offset), self.assertRaises(p.FormatError):
                p.decode(bytes(corrupt))
        with self.assertRaises(v.FormatError):
            v.Stream.decode(raw)  # Golden v1 must not accidentally accept v2.

    def test_integer_overflow_and_range(self):
        for value in (-1, v.U64_MAX + 1, True, 1.0):
            with self.assertRaises(p.FormatError):
                p.uleb(value)
        body = p.uleb(v.U64_MAX) + b'\x00\x00\x01\xff'
        with self.assertRaisesRegex(p.FormatError, 'absolute cycle'):
            p.decode(wire(body, 1, v.U64_MAX))
        with self.assertRaises(p.FormatError):
            p.Header(p.Metadata(), 0, v.U64_MAX).encode()

    def test_equivalence_detects_changes(self):
        s = stream([v.Event(v.WRITE, 1, 2), v.Event(v.WAIT, operand=10), v.Event(v.EOF)])
        trace = p.decode(self.roundtrip(s))
        for other in (p.Trace(trace.metadata, ((0, 1, 3),)),
                      p.Trace(trace.metadata, ((1, 1, 2),)),
                      p.Trace(replace(trace.metadata, sid_model=2), trace.writes),
                      p.Trace(replace(trace.metadata, stream_cycles=11), trace.writes)):
            with self.assertRaises(p.FormatError):
                p.equivalent(s.encode(), p.encode(other))

    def test_seeded_random_golden_streams(self):
        rng = random.Random(20260912)
        for _ in range(200):
            events, cycle, starts = [], 0, []
            for i in range(rng.randrange(1, 50)):
                starts.append(cycle)
                wait = rng.randrange(1, 1000000)
                if rng.randrange(3) or (events and events[-1].opcode == v.WRITE):
                    events.append(v.Event(v.WAIT, operand=wait))
                    cycle += wait
                else:
                    events.append(v.Event(v.WRITE, rng.randrange(25), rng.randrange(256)))
            events.extend([v.Event(v.WAIT, operand=1), v.Event(v.EOF)])
            kwargs = {}
            if rng.randrange(2):
                target = rng.randrange(len(starts))
                kwargs = dict(flags=v.LOOP_VALID, loop_event_index=target,
                              loop_start_cycle=starts[target], loop_end_cycle=cycle + 1)
            s = stream(events, **kwargs)
            t = p.decode(self.roundtrip(s))
            # Independent C0 scheduler oracle, including three loop iterations.
            repeats = 3 if kwargs else 0
            golden = [(e.cycle, e.event.addr, e.event.data)
                      for e in v.schedule(s, loop_repeats=repeats) if e.event.opcode == v.WRITE]
            replay = list(t.writes)
            m = t.metadata
            for iteration in range(1, repeats + 1):
                replay.extend((cycle + iteration * (m.loop_end_cycle - m.loop_start_cycle), addr, data)
                              for cycle, addr, data in t.writes[m.loop_write_index:])
            self.assertEqual(golden, replay)

    def test_seeded_mutation_fuzz(self):
        rng = random.Random(222)
        raw = self.roundtrip(stream([v.Event(v.WRITE, 0, 3), v.Event(v.WAIT, operand=17000),
                                     v.Event(v.WRITE, 0x18, 15), v.Event(v.EOF)]))
        for _ in range(2000):
            changed = bytearray(raw)
            changed[rng.randrange(len(raw))] = rng.randrange(256)
            try:
                trace = p.decode(bytes(changed))
            except p.FormatError:
                continue
            self.assertEqual(p.encode(trace), bytes(changed))

    def test_corpus_report_tool(self):
        import corpus
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / 'synthetic.v1'
            target = Path(directory) / 'synthetic.v2'
            source.write_bytes(stream([v.Event(v.WRITE, 0, 7), v.Event(v.WAIT, operand=985248),
                                      v.Event(v.EOF)]).encode())
            report = corpus.measure(source, target)
            self.assertEqual(report['write_count'], 1)
            self.assertEqual(report['capture_seconds'], 1)
            self.assertTrue(report['deterministic'])
            self.assertEqual(report['v2_bytes'], target.stat().st_size)

    def test_declared_size_truncated_payload_and_bad_eof_cycle(self):
        for body, count, cycles in ((b'\x00\x00\x03\x80\x01', 1, 128),
                                    (b'\x00\x00\x03\x80\x01\x02', 2, 128),
                                    (b'\x01\xff', 0, 0)):
            with self.assertRaises(p.FormatError):
                p.decode(wire(body, count, cycles))

    def test_cli(self):
        with tempfile.TemporaryDirectory() as td:
            source, target = Path(td) / 'tone.v1', Path(td) / 'tone.v2'
            source.write_bytes(stream([v.Event(v.EOF)]).encode())
            cmd = [sys.executable, str(Path(p.__file__))]
            for args in (['pack', str(source), '-o', str(target)], ['validate', str(target)],
                         ['inspect', str(target)], ['dump', str(target)],
                         ['compare', str(source), str(target)]):
                result = subprocess.run(cmd + args, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
            result = subprocess.run(cmd + ['pack', str(source), '-o', str(target)], capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            summary = p.inspect(target.read_bytes())
            self.assertEqual(summary['varint_length_histogram'], {1: 1})
            self.assertIsNone(summary['average_write_record_bytes'])


if __name__ == '__main__':
    unittest.main()
