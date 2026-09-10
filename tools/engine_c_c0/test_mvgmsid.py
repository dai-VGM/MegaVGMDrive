"""Host-only contract tests; no FPGA/hardware claim."""
from dataclasses import replace
from fractions import Fraction
import json
from pathlib import Path
import random
import struct
import subprocess
import sys
import tempfile
import unittest

from mvgmsid import (Clock, DURATION_KNOWN, END_IS_CAPTURE_LIMIT, EOF, Event,
                     FormatError, FractionalCE, Header, LOOP_VALID, Stream,
                     TransportCursor, U64_MAX, WAIT, WRITE, inspect, schedule)


# Independently written v1 wire fixture: PAL 985248 Hz, subtune 1, EOF only.
MINIMAL = bytes.fromhex("""
4d56474d53494400 0100000080001000
00000000 a0080f00 01000000 01010100
01000000 00000000
0100000000000000 1000000000000000
0000000000000000 0000000000000000
0000000000000000 0000000000000000 0000000000000000
0000000000000000000000000000000000000000000000000000000000000000
ff000000000000000000000000000000
""")


def fixture(events, **fields):
    events = tuple(events)
    cycles = sum(e.operand for e in events if e.opcode == WAIT)
    return Stream(Header(event_count=len(events), stream_bytes=len(events) * 16,
                         stream_cycles=cycles, **fields), events)


def mutate(raw, offset, fmt, value):
    result = bytearray(raw)
    struct.pack_into(fmt, result, offset, value)
    return bytes(result)


class WireTests(unittest.TestCase):
    def test_independent_minimal_fixture(self):
        self.assertEqual(len(MINIMAL), 144)
        stream = Stream.decode(MINIMAL)
        self.assertEqual(stream.header, Header())
        self.assertEqual(stream.encode(), MINIMAL)
        self.assertEqual(list(schedule(stream))[0].cycle, 0)

    def test_roundtrip_all_fields(self):
        stream = fixture([Event(WRITE, 0x18, 255), Event(WAIT, operand=23), Event(EOF)],
                         flags=31, clock_num=1022727, sid_model=2, timing_standard=2,
                         subtune_id=12, duration_cycles=23, loop_event_index=0,
                         loop_start_cycle=0, loop_end_cycle=23,
                         source_sha256=bytes(range(32)))
        self.assertEqual(Stream.decode(stream.encode()), stream)

    def test_bad_magic(self):
        with self.assertRaisesRegex(FormatError, "magic"):
            Stream.decode(b"Vgm " + MINIMAL[4:])

    def test_version_major_and_minor(self):
        for offset in (8, 10):
            with self.subTest(offset=offset), self.assertRaises(FormatError):
                Stream.decode(mutate(MINIMAL, offset, "<H", 2))

    def test_header_and_event_sizes(self):
        for offset, value in ((12, 127), (12, 144), (14, 8), (14, 32)):
            with self.subTest(offset=offset, value=value), self.assertRaises(FormatError):
                Stream.decode(mutate(MINIMAL, offset, "<H", value))

    def test_unknown_flag_each_bit(self):
        for bit in range(5, 32):
            with self.subTest(bit=bit), self.assertRaises(FormatError):
                Stream.decode(mutate(MINIMAL, 0x10, "<I", 1 << bit))

    def test_all_reserved_bytes(self):
        for offset in [0x1F, *range(0x24, 0x28), *range(131, 136)]:
            with self.subTest(offset=offset), self.assertRaisesRegex(FormatError, "reserved"):
                Stream.decode(mutate(MINIMAL, offset, "B", 1))

    def test_model_standard_single_sid(self):
        for offset, value in ((0x1C, 0), (0x1C, 3), (0x1D, 0), (0x1D, 3),
                              (0x1E, 0), (0x1E, 2)):
            with self.subTest(offset=offset, value=value), self.assertRaises(FormatError):
                Stream.decode(mutate(MINIMAL, offset, "B", value))

    def test_zero_clock_and_subtune(self):
        for offset in (0x14, 0x18, 0x20):
            with self.subTest(offset=offset), self.assertRaises(FormatError):
                Stream.decode(mutate(MINIMAL, offset, "<I", 0))

    def test_event_count_and_size_mismatch(self):
        for offset, value in ((0x28, 0), (0x28, 2), (0x30, 0), (0x30, 17)):
            with self.subTest(offset=offset), self.assertRaises(FormatError):
                Stream.decode(mutate(MINIMAL, offset, "<Q", value))

    def test_each_byte_truncation(self):
        raw = fixture([Event(WRITE, 3, 7), Event(WAIT, operand=11), Event(EOF)]).encode()
        for length in range(len(raw)):
            with self.subTest(length=length), self.assertRaises(FormatError):
                Stream.decode(raw[:length])

    def test_trailing_bytes(self):
        with self.assertRaises(FormatError):
            Stream.decode(MINIMAL + bytes(16))

    def test_unknown_opcode(self):
        for opcode in set(range(256)) - {WAIT, WRITE, EOF}:
            with self.subTest(opcode=opcode), self.assertRaises(FormatError):
                Stream.decode(mutate(MINIMAL, 128, "B", opcode))

    def test_write_range_and_payload(self):
        for event in (Event(WRITE, 0x19), Event(WRITE, 255), Event(WRITE, operand=1)):
            with self.subTest(event=event), self.assertRaises(FormatError):
                fixture([event, Event(EOF)]).encode()

    def test_wait_payload(self):
        for event in (Event(WAIT), Event(WAIT, addr=1, operand=1),
                      Event(WAIT, data=1, operand=1)):
            with self.subTest(event=event), self.assertRaises(FormatError):
                fixture([event, Event(EOF)]).encode()

    def test_eof_payload(self):
        for offset, fmt in ((129, "B"), (130, "B"), (136, "<Q")):
            with self.subTest(offset=offset), self.assertRaises(FormatError):
                Stream.decode(mutate(MINIMAL, offset, fmt, 1))

    def test_missing_duplicate_and_early_eof(self):
        for events in ([Event(WRITE)], [Event(EOF), Event(EOF)],
                       [Event(EOF), Event(WAIT, operand=1), Event(EOF)]):
            with self.subTest(events=events), self.assertRaises(FormatError):
                fixture(events).encode()

    def test_same_cycle_writes_even_identical(self):
        for second in (Event(WRITE, 4, 33), Event(WRITE, 0x18, 0)):
            with self.subTest(second=second), self.assertRaisesRegex(FormatError, "same-cycle"):
                fixture([Event(WRITE, 4, 33), second, Event(EOF)]).encode()

    def test_identical_writes_different_cycles_preserved(self):
        stream = fixture([Event(WRITE, 4, 33), Event(WAIT, operand=1),
                          Event(WRITE, 4, 33), Event(EOF)])
        decoded = Stream.decode(stream.encode())
        writes = [e for e in schedule(decoded) if e.event.opcode == WRITE]
        self.assertEqual([e.cycle for e in writes], [0, 1])
        self.assertEqual(writes[0].event, writes[1].event)

    def test_cycle_metadata_mismatch(self):
        with self.assertRaisesRegex(FormatError, "WAIT sum"):
            Stream.decode(mutate(MINIMAL, 0x38, "<Q", 1))

    def test_duration_known_and_capture_limit_are_separate(self):
        stream = fixture([Event(WAIT, operand=100), Event(EOF)], flags=END_IS_CAPTURE_LIMIT)
        self.assertIsNone(inspect(stream)["duration"])
        self.assertEqual(inspect(stream)["stream_duration"]["cycles"], 100)
        known = replace(stream, header=replace(stream.header, flags=DURATION_KNOWN,
                                              duration_cycles=200))
        self.assertEqual(inspect(known)["duration"]["cycles"], 200)
        for h in (replace(stream.header, duration_cycles=5),
                  replace(stream.header, flags=DURATION_KNOWN)):
            with self.assertRaises(FormatError):
                h.validate()

    def test_integer_encoder_rejects_no_truncation(self):
        for field, value in (("flags", 1 << 32), ("clock_num", -1),
                             ("clock_den", 1.5), ("subtune_id", True),
                             ("stream_cycles", 1 << 64), ("sid_model", 257)):
            with self.subTest(field=field), self.assertRaises(FormatError):
                replace(Header(), **{field: value}).encode()
        for event in (Event(WRITE, data=256), Event(WAIT, operand=1 << 64),
                      Event(WRITE, addr=-1)):
            with self.assertRaises(FormatError):
                event.encode()

    def test_size_product_and_total_file_overflow(self):
        for count in ((1 << 64) // 16, ((1 << 64) - 128) // 16):
            with self.subTest(count=count), self.assertRaises(FormatError):
                replace(Header(), event_count=count, stream_bytes=count * 16).validate()

    def test_wait_sum_overflow_from_wire(self):
        h = Header(event_count=3, stream_bytes=48, stream_cycles=U64_MAX)
        raw = h.encode() + Event(WAIT, operand=U64_MAX).encode() + Event(WAIT, operand=1).encode() + Event(EOF).encode()
        with self.assertRaisesRegex(FormatError, "WAIT cycle sum"):
            Stream.decode(raw)

    def test_maximum_cycle_accepted(self):
        stream = fixture([Event(WAIT, operand=U64_MAX), Event(EOF)])
        self.assertEqual(list(schedule(Stream.decode(stream.encode())))[-1].cycle, U64_MAX)


class LoopTests(unittest.TestCase):
    def loop(self):
        return fixture([Event(WRITE, 1, 9), Event(WAIT, operand=7),
                        Event(WRITE, 4, 33), Event(WAIT, operand=11), Event(EOF)],
                       flags=LOOP_VALID, loop_event_index=2,
                       loop_start_cycle=7, loop_end_cycle=18)

    def test_intro_and_repeated_loop_exact_times(self):
        stream = Stream.decode(self.loop().encode())
        timeline = list(schedule(stream, 2))
        self.assertEqual([e.cycle for e in timeline if e.event.opcode == WRITE], [0, 7, 18, 29])
        self.assertEqual([e.cycle for e in timeline if e.event.opcode == EOF], [40])
        self.assertEqual(timeline[-1].transport_tick, 40 * 44100 // 985248)

    def test_bad_loop_metadata(self):
        for fields in ({"loop_event_index": 4}, {"loop_event_index": 99},
                       {"loop_start_cycle": 8}, {"loop_start_cycle": 18},
                       {"loop_end_cycle": 17}, {"flags": 0}):
            with self.subTest(fields=fields), self.assertRaises(FormatError):
                replace(self.loop(), header=replace(self.loop().header, **fields)).encode()

    def test_loop_target_wait_is_valid(self):
        stream = self.loop()
        stream = replace(stream, header=replace(stream.header, loop_event_index=1, loop_start_cycle=0))
        stream.validate()
        self.assertEqual(list(schedule(stream, 1))[-1].cycle, 36)

    def test_same_cycle_across_loop_boundary(self):
        stream = fixture([Event(WRITE), Event(WAIT, operand=1), Event(WRITE), Event(EOF)],
                         flags=LOOP_VALID, loop_end_cycle=1)
        with self.assertRaisesRegex(FormatError, "loop boundary"):
            stream.validate()

    def test_positive_loop_without_writes(self):
        stream = fixture([Event(WAIT, operand=1), Event(EOF)], flags=LOOP_VALID, loop_end_cycle=1)
        self.assertEqual(list(schedule(stream, 10))[-1].cycle, 11)

    def test_expanded_timeline_overflow(self):
        with self.assertRaisesRegex(FormatError, "expanded timeline"):
            list(schedule(self.loop(), U64_MAX))

    def test_repeats_without_metadata(self):
        with self.assertRaises(FormatError):
            list(schedule(Stream.decode(MINIMAL), 1))


class TimingTests(unittest.TestCase):
    CLOCKS = (Clock(985248), Clock(1022727), Clock(15763977, 16))

    def test_24_hour_closed_form_reference(self):
        sys_hz = 50_000_000
        edges = sys_hz * 86400
        for clock in self.CLOCKS:
            with self.subTest(clock=clock):
                expected = Fraction(edges * clock.num, sys_hz * clock.den)
                count, rem = clock.ce_position(edges, sys_hz)
                self.assertEqual(count, expected.numerator // expected.denominator)
                self.assertEqual(Fraction(count) + Fraction(rem, clock.threshold(sys_hz)), expected)
                tick, rest = clock.transport_position(count)
                self.assertEqual(Fraction(tick) + Fraction(rest, clock.num), clock.seconds(count) * 44100)

    def test_chunking_does_not_accumulate_rounding(self):
        rng = random.Random(913)
        for clock in self.CLOCKS:
            ce = FractionalCE(clock, 50_000_000)
            cursor = TransportCursor(clock)
            edges = count = total_cycles = 0
            for _ in range(10000):
                chunk = rng.randrange(1, 1_000_000_000)
                edges += chunk
                count += ce.advance(chunk)
                cycles = rng.randrange(1, 100000)
                total_cycles += cycles
                position = cursor.advance(cycles)
            self.assertEqual((count, ce.accumulator), clock.ce_position(edges, 50_000_000))
            self.assertEqual(position, clock.transport_position(total_cycles))

    def test_edge_by_edge_divider_and_jitter(self):
        sys_hz = 50_000_000
        for clock in self.CLOCKS:
            ce = FractionalCE(clock, sys_hz)
            ordinal = 0
            previous = 0
            period = Fraction(sys_hz * clock.den, clock.num)
            allowed = {period.numerator // period.denominator,
                       -(-period.numerator // period.denominator)}
            for edge in range(1, 100001):
                emitted = ce.advance(1)
                self.assertIn(emitted, (0, 1))
                if emitted:
                    ordinal += 1
                    self.assertEqual(edge, clock.ce_edge(ordinal, sys_hz))
                    self.assertTrue(0 <= Fraction(edge) - ordinal * period < 1)
                    if previous:
                        self.assertIn(edge - previous, allowed)
                    previous = edge

    def test_one_cycle_events_not_individually_rounded(self):
        stream = fixture([Event(WAIT, operand=1)] * 1000 + [Event(EOF)])
        end = list(schedule(stream))[-1]
        self.assertEqual(end.transport_tick, 44)
        self.assertEqual(end.transport_remainder, 1000 * 44100 % 985248)

    def test_large_intermediate_products_do_not_wrap(self):
        clock = Clock((1 << 32) - 1, (1 << 32) - 2)
        tick, rem = clock.transport_position(U64_MAX)
        self.assertGreater(tick, U64_MAX)
        self.assertEqual(Fraction(tick) + Fraction(rem, clock.num), clock.seconds(U64_MAX) * 44100)

    def test_cursor_overflow_is_rejected(self):
        cursor = TransportCursor(Clock(985248), U64_MAX)
        with self.assertRaises(FormatError):
            cursor.advance(1)
        self.assertEqual(cursor.cycles, U64_MAX)

    def test_invalid_clock_math_inputs(self):
        for args in ((0, 1), (1, 0), (-1, 1), (1 << 32, 1)):
            with self.assertRaises(FormatError):
                Clock(*args)
        for action in (lambda: Clock(985248).threshold(0),
                       lambda: Clock(985248).threshold(1),
                       lambda: Clock(985248).ce_edge(0, 50_000_000),
                       lambda: Clock(985248).transport_position(-1),
                       lambda: FractionalCE(Clock(1), 50, 50)):
            with self.assertRaises(FormatError):
                action()


class InspectorTests(unittest.TestCase):
    def test_inspector_required_fields(self):
        stream = fixture([Event(WRITE), Event(WAIT, operand=1022727), Event(EOF)],
                         clock_num=1022727, timing_standard=2, sid_model=2,
                         subtune_id=3, flags=DURATION_KNOWN | LOOP_VALID,
                         duration_cycles=1022727, loop_end_cycle=1022727)
        result = inspect(stream)
        self.assertEqual(result["model"], "8580")
        self.assertEqual(result["timing_standard"], "NTSC")
        self.assertEqual(result["clock"], {"num": 1022727, "den": 1, "unit": "Hz"})
        self.assertEqual(result["subtune"], 3)
        self.assertEqual(result["duration"]["seconds_num"], 1)
        self.assertEqual(result["loop"]["end_cycle"], 1022727)
        self.assertEqual(result["event_count"], 3)
        self.assertEqual(result["write_count"], 1)
        self.assertEqual(result["final_cycle"], 1022727)

    def test_cli_valid_dump_and_invalid(self):
        tool = str(Path(__file__).with_name("mvgmsid.py"))
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "minimal.mvgmsid"
            path.write_bytes(MINIMAL)
            run = subprocess.run([sys.executable, tool, str(path)], capture_output=True, text=True)
            self.assertEqual(run.returncode, 0, run.stderr)
            self.assertEqual(json.loads(run.stdout)["event_count"], 1)
            run = subprocess.run([sys.executable, tool, str(path), "--dump"], capture_output=True, text=True)
            self.assertEqual(run.returncode, 0)
            self.assertIn("#0 cycle=0 tick44100=0 remainder=0/985248 EOF", run.stdout)
            path.write_bytes(MINIMAL[:-1])
            run = subprocess.run([sys.executable, tool, str(path)], capture_output=True, text=True)
            self.assertEqual(run.returncode, 2)
            self.assertEqual(run.stdout, "")
            self.assertNotIn("Traceback", run.stderr)
            run = subprocess.run([sys.executable, tool, str(path) + ".missing"], capture_output=True, text=True)
            self.assertEqual(run.returncode, 2)


if __name__ == "__main__":
    unittest.main()
