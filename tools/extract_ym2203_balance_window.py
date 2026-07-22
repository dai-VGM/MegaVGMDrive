#!/usr/bin/env python3
"""Create a short, state-preserving YM2203/SegaPCM VGM measurement window.

All non-wait commands before the retained interval are kept so the production
parser sees the real register and PCM setup.  Earlier waits are removed, while
the requested preroll and measurement window retain their exact 44.1 kHz wait
durations.  The resulting file is intended for cycle-accurate RTL audio
measurement, not listening or distribution.

Full-pass mode keeps every byte and only clears the loop header fields so the
production parser reaches the original end command exactly once.
"""

from __future__ import annotations

import argparse
import gzip
import pathlib
import struct


SAMPLE_RATE = 44_100


def u16le(data: bytes, offset: int) -> int:
    return struct.unpack_from("<H", data, offset)[0]


def u32le(data: bytes, offset: int) -> int:
    return struct.unpack_from("<I", data, offset)[0]


def command_size(data: bytes, pc: int) -> int:
    command = data[pc]
    if command == 0x66:
        return 1
    if command == 0x61:
        return 3
    if command in (0x62, 0x63) or 0x70 <= command <= 0x8F:
        return 1
    if command == 0x67:
        if data[pc + 1] != 0x66:
            raise ValueError(f"bad data block at 0x{pc:x}")
        return 7 + u32le(data, pc + 3)
    if command == 0x68:
        return 12
    if command in (0x30, 0x4F, 0x50, 0x94):
        return 2
    if 0x51 <= command <= 0x5F or command == 0xA0:
        return 3
    if 0xB0 <= command <= 0xBF:
        return 3
    if 0xC0 <= command <= 0xDF:
        return 4
    if command == 0xE0 or command in (0x90, 0x91, 0x95):
        return 5
    if command == 0x92:
        return 6
    if command == 0x93:
        return 11
    raise ValueError(f"unsupported command 0x{command:02x} at 0x{pc:x}")


def wait_samples(data: bytes, pc: int) -> int | None:
    command = data[pc]
    if command == 0x61:
        return u16le(data, pc + 1)
    if command == 0x62:
        return 735
    if command == 0x63:
        return 882
    if 0x70 <= command <= 0x7F:
        return (command & 0x0F) + 1
    if 0x80 <= command <= 0x8F:
        return command & 0x0F
    return None


def emit_wait(output: bytearray, samples: int) -> None:
    while samples:
        chunk = min(samples, 0xFFFF)
        if chunk <= 16:
            output.append(0x70 | (chunk - 1))
        else:
            output.extend((0x61, chunk & 0xFF, chunk >> 8))
        samples -= chunk


def load_vgm(path: pathlib.Path) -> bytes:
    data = path.read_bytes()
    if data[:2] == b"\x1f\x8b":
        data = gzip.decompress(data)
    if data[:4] != b"Vgm ":
        raise ValueError(f"not a VGM file: {path}")
    return data


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=pathlib.Path)
    parser.add_argument("output", type=pathlib.Path)
    parser.add_argument("--start", type=float,
                        help="measurement start in seconds")
    parser.add_argument("--duration", type=float, default=1.0)
    parser.add_argument("--preroll", type=float, default=2.0)
    parser.add_argument(
        "--full-pass", action="store_true",
        help="copy every command unchanged and clear only the VGM loop fields",
    )
    args = parser.parse_args()

    data = load_vgm(args.source)
    if args.full_pass:
        output = bytearray(data)
        struct.pack_into("<I", output, 0x1C, 0)
        struct.pack_into("<I", output, 0x20, 0)
        args.output.write_bytes(output)
        print(
            f"source={args.source} output={args.output} bytes={len(output)} "
            "mode=full-pass loop_offset=0 loop_samples=0 commands=unchanged"
        )
        return
    if args.start is None:
        parser.error("--start is required unless --full-pass is used")

    version = u32le(data, 0x08)
    data_rel = u32le(data, 0x34) if version >= 0x150 else 0
    data_start = 0x40 if data_rel == 0 else 0x34 + data_rel
    measure_start = round(args.start * SAMPLE_RATE)
    measure_end = measure_start + round(args.duration * SAMPLE_RATE)
    retain_start = max(0, measure_start - round(args.preroll * SAMPLE_RATE))

    output = bytearray(data[:data_start])
    pc = data_start
    sample = 0
    kept_waits = 0
    kept_commands = 0
    while pc < len(data) and sample < measure_end:
        size = command_size(data, pc)
        command = data[pc]
        if command == 0x66:
            break
        wait = wait_samples(data, pc)
        if wait is None:
            output.extend(data[pc : pc + size])
            kept_commands += 1
        else:
            overlap_start = max(sample, retain_start)
            overlap_end = min(sample + wait, measure_end)
            if overlap_end > overlap_start:
                retained = overlap_end - overlap_start
                emit_wait(output, retained)
                kept_waits += retained
            sample += wait
        pc += size
    output.append(0x66)

    # Remove loop/GD3 metadata and describe the shortened wait timeline.
    struct.pack_into("<I", output, 0x14, 0)
    struct.pack_into("<I", output, 0x18, kept_waits)
    struct.pack_into("<I", output, 0x1C, 0)
    struct.pack_into("<I", output, 0x20, 0)
    struct.pack_into("<I", output, 0x04, len(output) - 4)
    args.output.write_bytes(output)

    print(
        f"source={args.source} output={args.output} bytes={len(output)} "
        f"source_samples={sample} retain_start={retain_start} "
        f"measure_start={measure_start} measure_end={measure_end} "
        f"preroll_samples={measure_start - retain_start} "
        f"kept_wait_samples={kept_waits} kept_nonwait_commands={kept_commands}"
    )


if __name__ == "__main__":
    main()
