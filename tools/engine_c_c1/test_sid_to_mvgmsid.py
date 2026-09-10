#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent / "engine_c_c0"))

import sid_to_mvgmsid as converter
from mvgmsid import (
    CLOCK_EXPLICIT_OVERRIDE,
    END_IS_CAPTURE_LIMIT,
    MODEL_EXPLICIT_OVERRIDE,
    EOF,
    WAIT,
    WRITE,
    Clock,
    FormatError,
    Stream,
)


def trace_bytes(writes=((12, 0, 0, 52),), **changes) -> bytes:
    metadata = {
        "libsidplayfp_version": "3.1.1",
        "libsidplayfp_commit": "732fa8ec8131fc75aafc2eaea583ddcdeea2a3cc",
        "title_hex": "54657374",
        "author_hex": "417574686f72",
        "released_hex": "32303236",
        "format_hex": "50534944",
        "songs": "1",
        "start_song": "1",
        "subtune": "1",
        "song_speed": "0",
        "source_model": "6581",
        "source_timing": "pal",
        "model": "6581",
        "timing": "pal",
        "model_override": "false",
        "timing_override": "false",
        "clock_hz": "985248",
        "capture_seconds": "1",
        "capture_cycles": "985248",
        "write_count": str(len(writes)),
    }
    metadata.update({key: str(value) for key, value in changes.items()})
    lines = [converter.TRACE_MAGIC]
    lines.extend(f"META\t{key}\t{value}" for key, value in metadata.items())
    lines.extend(f"WRITE\t{cycle}\t{sid}\t{addr}\t{data}"
                 for cycle, sid, addr, data in writes)
    lines.append(f"END\t{metadata['capture_cycles']}")
    return ("\n".join(lines) + "\n").encode()


def synthetic_psid(*, flags=0x0014, songs=1) -> bytes:
    """Original tiny PSID fixture: init writes five registers, play writes one."""
    header = bytearray(0x7c)
    header[0:4] = b"PSID"
    struct.pack_into(">HHHHHHHI", header, 4, 2, 0x7c, 0, 0x1000,
                     0x101a, songs, 1, 0)
    header[22:22 + len(b"MVGMSID C1 synthetic")] = b"MVGMSID C1 synthetic"
    header[54:54 + len(b"MegaVGMPlayer tests")] = b"MegaVGMPlayer tests"
    header[86:90] = b"2026"
    struct.pack_into(">H", header, 118, flags)
    init = bytes((
        0xA9, 0x34, 0x8D, 0x00, 0xD4,
        0xA9, 0x12, 0x8D, 0x01, 0xD4,
        0xA9, 0x34, 0x8D, 0x00, 0xD4,
        0xA9, 0x21, 0x8D, 0x04, 0xD4,
        0xA9, 0x0F, 0x8D, 0x18, 0xD4,
        0x60,
    ))
    play = bytes((0xA9, 0x0E, 0x8D, 0x18, 0xD4, 0x60))
    return bytes(header) + b"\x00\x10" + init + play


class TraceTests(unittest.TestCase):
    def test_valid_minimal_trace(self):
        trace = converter.parse_trace(trace_bytes())
        self.assertEqual(trace.final_cycle, 985248)
        self.assertEqual(trace.writes[0].data, 0x34)

    def test_wait_conversion_and_final_eof(self):
        trace = converter.parse_trace(trace_bytes(
            writes=((0, 0, 0, 1), (9, 0, 1, 2), (25, 0, 2, 3))))
        stream = converter.trace_to_stream(trace, bytes(range(32)))
        self.assertEqual(
            [(event.opcode, event.operand) for event in stream.events],
            [(WRITE, 0), (WAIT, 9), (WRITE, 0), (WAIT, 16),
             (WRITE, 0), (WAIT, 985223), (EOF, 0)],
        )

    def test_zero_cycle_first_write_is_legal(self):
        trace = converter.parse_trace(trace_bytes(writes=((0, 0, 24, 15),)))
        stream = converter.trace_to_stream(trace, bytes(32))
        self.assertEqual(stream.events[0].opcode, WRITE)

    def test_same_value_rewrite_survives(self):
        trace = converter.parse_trace(trace_bytes(
            writes=((2, 0, 0, 52), (7, 0, 0, 52))))
        stream = converter.trace_to_stream(trace, bytes(32))
        writes = [event for event in stream.events if event.opcode == WRITE]
        self.assertEqual([(event.addr, event.data) for event in writes], [(0, 52), (0, 52)])

    def test_init_write_order_survives(self):
        original = ((3, 0, 0, 0x34), (8, 0, 1, 0x12), (13, 0, 4, 0x21))
        stream = converter.trace_to_stream(
            converter.parse_trace(trace_bytes(writes=original)), bytes(32))
        self.assertEqual(
            [(event.addr, event.data) for event in stream.events if event.opcode == WRITE],
            [(0, 0x34), (1, 0x12), (4, 0x21)],
        )

    def test_same_cycle_write_is_rejected(self):
        with self.assertRaisesRegex(converter.ConversionError, "same-cycle WRITE"):
            converter.parse_trace(trace_bytes(
                writes=((100, 0, 0, 1), (100, 0, 1, 2))))

    def test_out_of_order_write_is_rejected(self):
        with self.assertRaisesRegex(converter.ConversionError, "not monotonic"):
            converter.parse_trace(trace_bytes(
                writes=((100, 0, 0, 1), (99, 0, 1, 2))))

    def test_malformed_end_is_rejected(self):
        with self.assertRaisesRegex(converter.ConversionError, "capture_cycles / END"):
            converter.parse_trace(trace_bytes().replace(b"END\t985248", b"END\t985249"))

    def test_trailing_record_is_rejected(self):
        with self.assertRaisesRegex(converter.ConversionError, "data after END"):
            converter.parse_trace(trace_bytes() + b"WRITE\t3\t0\t0\t0\n")

    def test_unknown_trace_metadata_is_rejected(self):
        with self.assertRaisesRegex(converter.ConversionError, "unknown metadata"):
            converter.parse_trace(trace_bytes().replace(
                b"META\ttitle_hex\t54657374", b"META\tbogus\t54657374"))

    def test_integer_overflow_is_rejected(self):
        too_large = str(1 << 64).encode()
        with self.assertRaisesRegex(converter.ConversionError, "integer overflow"):
            converter.parse_trace(trace_bytes().replace(b"WRITE\t12", b"WRITE\t" + too_large))

    def test_capture_limit_and_override_flags(self):
        trace = converter.parse_trace(trace_bytes(
            model="8580", timing="ntsc", source_model="unknown",
            source_timing="any", model_override="true", timing_override="true",
            clock_hz="1022727", capture_cycles="1022727"))
        stream = converter.trace_to_stream(trace, bytes(32))
        self.assertEqual(
            stream.header.flags,
            END_IS_CAPTURE_LIMIT | MODEL_EXPLICIT_OVERRIDE | CLOCK_EXPLICIT_OVERRIDE,
        )
        self.assertEqual((stream.header.sid_model, stream.header.timing_standard), (2, 2))

    def test_c0_strict_validator_accepts_generated_bytes(self):
        stream = converter.trace_to_stream(converter.parse_trace(trace_bytes()), bytes(32))
        self.assertEqual(Stream.decode(stream.encode()), stream)

    def test_c0_rejects_truncated_generated_bytes(self):
        stream = converter.trace_to_stream(converter.parse_trace(trace_bytes()), bytes(32))
        with self.assertRaises(FormatError):
            Stream.decode(stream.encode()[:-1])

    def test_deterministic_binary(self):
        trace = converter.parse_trace(trace_bytes(
            writes=((2, 0, 0, 1), (1000, 0, 24, 15))))
        first = converter.trace_to_stream(trace, bytes(range(32))).encode()
        second = converter.trace_to_stream(trace, bytes(range(32))).encode()
        self.assertEqual(hashlib.sha256(first).digest(), hashlib.sha256(second).digest())

    def test_pal_and_ntsc_long_run_transport_positions_are_exact(self):
        seconds = 24 * 60 * 60
        for timing, clock_hz in (("pal", 985248), ("ntsc", 1022727)):
            with self.subTest(timing=timing):
                cycles = seconds * clock_hz
                trace = converter.parse_trace(trace_bytes(
                    writes=(), timing=timing, clock_hz=str(clock_hz),
                    capture_seconds=str(seconds), capture_cycles=str(cycles)))
                stream = converter.trace_to_stream(trace, bytes(32))
                self.assertEqual(stream.header.stream_cycles, cycles)
                self.assertEqual(Clock(clock_hz).transport_position(cycles),
                                 (seconds * 44100, 0))


NATIVE_HELPER = Path(os.environ.get(
    "MVGMSID_C1_NATIVE_HELPER", HERE / ".build" / "bin" / "sid_capture"))


@unittest.skipUnless(NATIVE_HELPER.is_file(), "run build_native.sh for native integration tests")
class NativeIntegrationTests(unittest.TestCase):
    def run_helper(self, source: Path, trace: Path, *extra: str) -> subprocess.CompletedProcess:
        return subprocess.run([
            str(NATIVE_HELPER), "--input", str(source), "--trace", str(trace),
            "--subtune", "1", "--capture-seconds", "1", *extra,
        ], capture_output=True, text=True)

    def test_actual_bus_capture_includes_init_and_same_value_rewrite(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            sid = root / "synthetic.sid"
            trace_path = root / "capture.tsv"
            sid.write_bytes(synthetic_psid())
            result = self.run_helper(sid, trace_path, "--model", "auto", "--timing", "auto")
            self.assertEqual(result.returncode, 0, result.stderr)
            trace = converter.parse_trace(trace_path.read_bytes())
            pairs = [(write.addr, write.data) for write in trace.writes]
            self.assertGreaterEqual(len(pairs), 6)
            expected_init = [(0, 0x34), (1, 0x12), (0, 0x34),
                             (4, 0x21), (24, 0x0f)]
            start = pairs.index(expected_init[0])
            self.assertEqual(pairs[start:start + len(expected_init)], expected_init)
            self.assertIn((24, 0x0e), pairs[start + len(expected_init):])
            self.assertEqual(trace.metadata["source_model"], "6581")
            self.assertEqual(trace.metadata["source_timing"], "pal")

    def test_full_converter_is_deterministic_and_writes_provenance(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            sid = root / "synthetic.sid"
            first = root / "first.mvgmsid"
            second = root / "second.mvgmsid"
            sid.write_bytes(synthetic_psid())
            stream1, provenance = converter.convert(
                sid, first, 1, "auto", "auto", 1, NATIVE_HELPER)
            stream2, _ = converter.convert(
                sid, second, 1, "auto", "auto", 1, NATIVE_HELPER)
            self.assertEqual(first.read_bytes(), second.read_bytes())
            self.assertEqual(Stream.decode(first.read_bytes()), stream1)
            self.assertEqual(stream1, stream2)
            self.assertTrue(stream1.header.flags & END_IS_CAPTURE_LIMIT)
            self.assertFalse(stream1.header.flags & MODEL_EXPLICIT_OVERRIDE)
            sidecar = json.loads(
                first.with_suffix(".mvgmsid.provenance.json").read_text())
            self.assertEqual(sidecar["capture"]["write_count"], provenance["capture"]["write_count"])
            self.assertEqual(sidecar["libsidplayfp"]["git_commit"],
                             "732fa8ec8131fc75aafc2eaea583ddcdeea2a3cc")
            self.assertFalse(sidecar["capture"]["loop_valid"])

    def test_model_and_timing_overrides_are_recorded(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            sid = root / "unknown.sid"
            output = root / "unknown.mvgmsid"
            sid.write_bytes(synthetic_psid(flags=0))
            with self.assertRaisesRegex(converter.ConversionError, "pass --model"):
                converter.convert(sid, output, 1, "auto", "auto", 1, NATIVE_HELPER)
            stream, sidecar = converter.convert(
                sid, output, 1, "8580", "ntsc", 1, NATIVE_HELPER)
            self.assertEqual(
                stream.header.flags,
                END_IS_CAPTURE_LIMIT | MODEL_EXPLICIT_OVERRIDE | CLOCK_EXPLICIT_OVERRIDE,
            )
            self.assertEqual(sidecar["selection"]["overrides"],
                             {"model": True, "timing": True})

    def test_malformed_sid_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "bad.sid"
            source.write_bytes(b"not a SID")
            result = self.run_helper(source, root / "trace.tsv",
                                     "--model", "6581", "--timing", "pal")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("malformed/unsupported SID", result.stderr)

    def test_invalid_subtune_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "one-song.sid"
            source.write_bytes(synthetic_psid())
            result = subprocess.run([
                str(NATIVE_HELPER), "--input", str(source), "--trace", str(root / "trace.tsv"),
                "--subtune", "2", "--capture-seconds", "1",
                "--model", "auto", "--timing", "auto",
            ], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("subtune outside", result.stderr)

    def test_native_capture_duration_overflow_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "one-song.sid"
            source.write_bytes(synthetic_psid())
            result = subprocess.run([
                str(NATIVE_HELPER), "--input", str(source), "--trace", str(root / "trace.tsv"),
                "--subtune", "1", "--capture-seconds", str((1 << 64) - 1),
                "--model", "auto", "--timing", "auto",
            ], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("multiplication overflow", result.stderr)


if __name__ == "__main__":
    unittest.main()
