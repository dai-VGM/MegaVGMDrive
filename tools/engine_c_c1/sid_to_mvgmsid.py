#!/usr/bin/env python3
"""Convert one PSID/RSID subtune into a strictly validated MVGMSID v1 file.

The native helper executes the tune through a pinned libsidplayfp and observes
actual C64-to-SID WRITE bus transactions.  This layer never polls registers,
never reconstructs state snapshots, and never quantizes event time to 44.1 kHz.
"""
from __future__ import annotations

import argparse
from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from typing import Sequence

SCRIPT_DIR = Path(__file__).resolve().parent
C0_DIR = SCRIPT_DIR.parent / "engine_c_c0"
sys.path.insert(0, str(C0_DIR))

from mvgmsid import (  # noqa: E402
    CLOCK_EXPLICIT_OVERRIDE,
    END_IS_CAPTURE_LIMIT,
    MODEL_EXPLICIT_OVERRIDE,
    EOF,
    WAIT,
    WRITE,
    Event,
    FormatError,
    Header,
    Stream,
    inspect,
)

CONVERTER_VERSION = "1.0.0"
TRACE_MAGIC = "MVGMCAP1"
REQUIRED_META = frozenset({
    "libsidplayfp_version", "libsidplayfp_commit", "title_hex",
    "author_hex", "released_hex", "format_hex", "songs", "start_song",
    "subtune", "song_speed", "source_model", "source_timing", "model",
    "timing", "model_override", "timing_override", "clock_hz",
    "capture_seconds", "capture_cycles", "write_count",
})


class ConversionError(ValueError):
    """The capture trace cannot be represented losslessly by MVGMSID v1."""


@dataclass(frozen=True)
class CapturedWrite:
    cycle: int
    sid: int
    addr: int
    data: int


@dataclass(frozen=True)
class CaptureTrace:
    metadata: dict[str, str]
    writes: tuple[CapturedWrite, ...]
    final_cycle: int


def _decimal(text: str, name: str, maximum: int = (1 << 64) - 1) -> int:
    if not text or not text.isascii() or not text.isdecimal():
        raise ConversionError(f"{name}: expected unsigned decimal integer")
    value = int(text, 10)
    if value > maximum:
        raise ConversionError(f"{name}: integer overflow")
    return value


def _boolean(text: str, name: str) -> bool:
    if text == "true":
        return True
    if text == "false":
        return False
    raise ConversionError(f"{name}: expected true or false")


def _hex_text(text: str, name: str) -> str:
    try:
        return bytes.fromhex(text).decode("utf-8", errors="replace")
    except ValueError as exc:
        raise ConversionError(f"{name}: malformed hexadecimal text") from exc


def parse_trace(raw: bytes) -> CaptureTrace:
    try:
        text = raw.decode("ascii")
    except UnicodeDecodeError as exc:
        raise ConversionError("capture trace is not ASCII") from exc
    lines = text.splitlines()
    if not lines or lines[0] != TRACE_MAGIC:
        raise ConversionError("bad capture trace magic")

    metadata: dict[str, str] = {}
    writes: list[CapturedWrite] = []
    final_cycle: int | None = None
    ended = False
    previous_cycle: int | None = None
    for line_number, line in enumerate(lines[1:], 2):
        if ended:
            raise ConversionError(f"line {line_number}: data after END")
        fields = line.split("\t")
        if fields[0] == "META" and len(fields) == 3:
            key, value = fields[1:]
            if key not in REQUIRED_META:
                raise ConversionError(f"line {line_number}: unknown metadata key {key!r}")
            if key in metadata:
                raise ConversionError(f"line {line_number}: duplicate metadata key {key!r}")
            metadata[key] = value
        elif fields[0] == "WRITE" and len(fields) == 5:
            cycle = _decimal(fields[1], "WRITE cycle")
            sid = _decimal(fields[2], "WRITE sid", 255)
            addr = _decimal(fields[3], "WRITE addr", 255)
            data = _decimal(fields[4], "WRITE data", 255)
            if sid != 0:
                raise ConversionError("MVGMSID v1 is single-SID; observed SID index is not zero")
            if addr > 0x18:
                raise ConversionError(f"WRITE register 0x{addr:02x} is outside SID range")
            if previous_cycle is not None:
                if cycle < previous_cycle:
                    raise ConversionError("WRITE cycles are not monotonic")
                if cycle == previous_cycle:
                    raise ConversionError(f"same-cycle WRITE at native SID cycle {cycle}")
            writes.append(CapturedWrite(cycle, sid, addr, data))
            previous_cycle = cycle
        elif fields[0] == "END" and len(fields) == 2:
            final_cycle = _decimal(fields[1], "END cycle")
            ended = True
        else:
            raise ConversionError(f"line {line_number}: malformed capture record")

    missing = REQUIRED_META - metadata.keys()
    if missing:
        raise ConversionError("missing capture metadata: " + ", ".join(sorted(missing)))
    if final_cycle is None:
        raise ConversionError("capture trace has no END record")
    if writes and writes[-1].cycle >= final_cycle:
        raise ConversionError("WRITE must precede final capture cycle")
    if _decimal(metadata["capture_cycles"], "capture_cycles") != final_cycle:
        raise ConversionError("capture_cycles / END mismatch")
    if _decimal(metadata["write_count"], "write_count") != len(writes):
        raise ConversionError("write_count / actual WRITE count mismatch")
    if metadata["model"] not in ("6581", "8580"):
        raise ConversionError("resolved model is not exact")
    if metadata["timing"] not in ("pal", "ntsc"):
        raise ConversionError("resolved timing is not exact")
    expected_clock = 985248 if metadata["timing"] == "pal" else 1022727
    if _decimal(metadata["clock_hz"], "clock_hz", (1 << 32) - 1) != expected_clock:
        raise ConversionError("timing / clock_hz mismatch")
    seconds = _decimal(metadata["capture_seconds"], "capture_seconds")
    if seconds == 0 or seconds > ((1 << 64) - 1) // expected_clock:
        raise ConversionError("capture_seconds is zero or overflows native cycles")
    if seconds * expected_clock != final_cycle:
        raise ConversionError("capture seconds / native cycle duration mismatch")
    _boolean(metadata["model_override"], "model_override")
    _boolean(metadata["timing_override"], "timing_override")
    for name in ("title_hex", "author_hex", "released_hex", "format_hex"):
        _hex_text(metadata[name], name)
    return CaptureTrace(metadata, tuple(writes), final_cycle)


def trace_to_stream(trace: CaptureTrace, source_sha256: bytes) -> Stream:
    if len(source_sha256) != 32:
        raise ConversionError("source SHA-256 must contain 32 bytes")
    events: list[Event] = []
    position = 0
    for write in trace.writes:
        if write.cycle > position:
            events.append(Event(WAIT, operand=write.cycle - position))
        events.append(Event(WRITE, addr=write.addr, data=write.data))
        position = write.cycle
    if trace.final_cycle > position:
        events.append(Event(WAIT, operand=trace.final_cycle - position))
    events.append(Event(EOF))

    metadata = trace.metadata
    flags = END_IS_CAPTURE_LIMIT
    if _boolean(metadata["model_override"], "model_override"):
        flags |= MODEL_EXPLICIT_OVERRIDE
    if _boolean(metadata["timing_override"], "timing_override"):
        flags |= CLOCK_EXPLICIT_OVERRIDE
    header = Header(
        flags=flags,
        clock_num=_decimal(metadata["clock_hz"], "clock_hz", (1 << 32) - 1),
        clock_den=1,
        sid_model={"6581": 1, "8580": 2}[metadata["model"]],
        timing_standard={"pal": 1, "ntsc": 2}[metadata["timing"]],
        subtune_id=_decimal(metadata["subtune"], "subtune", (1 << 32) - 1),
        event_count=len(events),
        stream_bytes=len(events) * 16,
        stream_cycles=trace.final_cycle,
        duration_cycles=0,
        loop_event_index=0,
        loop_start_cycle=0,
        loop_end_cycle=0,
        source_sha256=source_sha256,
    )
    stream = Stream(header, tuple(events))
    # This is the canonical C0 strict validator/codec, not a C1 fork.
    return Stream.decode(stream.encode())


def _git_head() -> str:
    try:
        return subprocess.run(
            ["git", "-C", str(SCRIPT_DIR), "rev-parse", "HEAD"],
            check=True, capture_output=True, text=True,
        ).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return "unknown"


def _sha256(path: Path) -> bytes:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        while block := source.read(1024 * 1024):
            digest.update(block)
    return digest.digest()


def _sidecar(trace: CaptureTrace, source: Path, source_sha: bytes,
             output: Path, output_sha: bytes, stream: Stream) -> dict:
    metadata = trace.metadata
    return {
        "schema": "MVGMSID-C1-provenance-1",
        "source": {
            "path": str(source.resolve()),
            "name": source.name,
            "sha256": source_sha.hex(),
            "title": _hex_text(metadata["title_hex"], "title_hex"),
            "author": _hex_text(metadata["author_hex"], "author_hex"),
            "released": _hex_text(metadata["released_hex"], "released_hex"),
            "format": _hex_text(metadata["format_hex"], "format_hex"),
            "songs": _decimal(metadata["songs"], "songs"),
            "start_song": _decimal(metadata["start_song"], "start_song"),
            "song_speed": _decimal(metadata["song_speed"], "song_speed"),
            "declared_model": metadata["source_model"],
            "declared_timing": metadata["source_timing"],
        },
        "converter": {"version": CONVERTER_VERSION, "git_commit": _git_head()},
        "libsidplayfp": {
            "version": metadata["libsidplayfp_version"],
            "git_commit": metadata["libsidplayfp_commit"],
            "capture_hook": "sidemu::writeReg entry / EventScheduler PHI1",
        },
        "selection": {
            "subtune": stream.header.subtune_id,
            "model": metadata["model"],
            "timing": metadata["timing"],
            "overrides": {
                "model": _boolean(metadata["model_override"], "model_override"),
                "timing": _boolean(metadata["timing_override"], "timing_override"),
            },
        },
        "capture": {
            "limit_seconds": _decimal(metadata["capture_seconds"], "capture_seconds"),
            "end_is_capture_limit": True,
            "event_count": stream.header.event_count,
            "write_count": len(trace.writes),
            "final_cycle": trace.final_cycle,
            "loop_valid": False,
        },
        "artifact": {
            "path": str(output.resolve()),
            "sha256": output_sha.hex(),
            "format": "MVGMSID v1.0",
        },
    }


def _atomic_write(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(descriptor, "wb") as target:
            target.write(data)
            target.flush()
            os.fsync(target.fileno())
        os.replace(temporary, path)
    except BaseException:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise


def convert(source: Path, output: Path, subtune: int, model: str, timing: str,
            capture_seconds: int, native_helper: Path) -> tuple[Stream, dict]:
    if subtune <= 0 or subtune >= (1 << 32):
        raise ConversionError("--subtune must be a positive 32-bit integer")
    if capture_seconds <= 0 or capture_seconds >= (1 << 64):
        raise ConversionError("--capture-seconds must be a positive 64-bit integer")
    if model not in ("auto", "6581", "8580"):
        raise ConversionError("--model must be auto, 6581 or 8580")
    if timing not in ("auto", "pal", "ntsc"):
        raise ConversionError("--timing must be auto, pal or ntsc")
    if not source.is_file():
        raise ConversionError(f"source SID does not exist: {source}")
    if not native_helper.is_file() or not os.access(native_helper, os.X_OK):
        raise ConversionError(
            f"native capture helper is unavailable: {native_helper}; run build_native.sh")

    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="mvgmsid-capture-") as directory:
        trace_path = Path(directory) / "capture.tsv"
        command = [
            str(native_helper), "--input", str(source), "--trace", str(trace_path),
            "--subtune", str(subtune), "--model", model, "--timing", timing,
            "--capture-seconds", str(capture_seconds),
        ]
        result = subprocess.run(command, capture_output=True, text=True)
        if result.returncode:
            detail = result.stderr.strip() or result.stdout.strip() or "capture helper failed"
            raise ConversionError(detail)
        raw_trace = trace_path.read_bytes()
        try:
            trace = parse_trace(raw_trace)
        except ConversionError:
            # Preserve the exact lossless trace when v1 cannot represent it,
            # especially for a same-cycle multi-WRITE corpus finding.
            _atomic_write(output.with_suffix(output.suffix + ".failed-trace.tsv"), raw_trace)
            raise

    source_sha = _sha256(source)
    stream = trace_to_stream(trace, source_sha)
    encoded = stream.encode()
    # Validate the actual bytes one final time before publication.
    decoded = Stream.decode(encoded)
    _atomic_write(output, encoded)
    output_sha = hashlib.sha256(encoded).digest()
    provenance = _sidecar(trace, source, source_sha, output, output_sha, decoded)
    sidecar = output.with_suffix(output.suffix + ".provenance.json")
    _atomic_write(sidecar, (json.dumps(provenance, indent=2, sort_keys=True) + "\n").encode())
    return decoded, provenance


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("--subtune", type=int, required=True)
    parser.add_argument("--model", choices=("auto", "6581", "8580"), default="auto")
    parser.add_argument("--timing", choices=("auto", "pal", "ntsc"), default="auto")
    parser.add_argument("--capture-seconds", type=int, required=True)
    parser.add_argument("-o", "--output", type=Path, required=True)
    parser.add_argument(
        "--native-helper", type=Path,
        default=SCRIPT_DIR / ".build" / "bin" / "sid_capture",
    )
    args = parser.parse_args(argv)
    try:
        stream, provenance = convert(
            args.input, args.output, args.subtune, args.model, args.timing,
            args.capture_seconds, args.native_helper,
        )
        print(json.dumps({
            "output": str(args.output),
            "provenance": str(args.output.with_suffix(args.output.suffix + ".provenance.json")),
            "summary": inspect(stream),
            "source": provenance["source"],
        }, indent=2))
    except (ConversionError, FormatError, OSError) as exc:
        print(f"MVGMSID conversion failed: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
