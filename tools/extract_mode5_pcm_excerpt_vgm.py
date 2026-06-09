#!/usr/bin/env python3
"""Extract a small BRAM-sized real-PCM VGM excerpt for MiSTer mode5."""

from __future__ import annotations

from pathlib import Path
import argparse
import struct


DEFAULT_INPUT = Path("/Users/daizo/Downloads/test.vgm")
DEFAULT_OUTPUT = Path("testdata/test_pcm_excerpt.vgm")
DATA_OFFSET = 0x40
DEFAULT_TARGET_SAMPLES = 44_100 * 2
DEFAULT_MAX_SIZE = 240 * 1024
YM2612_CLOCK_FALLBACK = 7_670_454


def le16(data: bytes, offset: int) -> int:
    return struct.unpack_from("<H", data, offset)[0]


def le32(data: bytes, offset: int) -> int:
    return struct.unpack_from("<I", data, offset)[0]


def pack32(value: int) -> bytes:
    return struct.pack("<I", value)


def data_start(data: bytes) -> int:
    version = le32(data, 0x08)
    if version >= 0x150:
        offset = le32(data, 0x34)
        return 0x34 + offset if offset != 0 else 0x40
    return 0x40


def parse_wait(data: bytes, pc: int) -> tuple[int, int] | None:
    cmd = data[pc]
    if cmd == 0x61 and pc + 2 < len(data):
        return le16(data, pc + 1), 3
    if cmd == 0x62:
        return 735, 1
    if cmd == 0x63:
        return 882, 1
    if 0x70 <= cmd <= 0x7F:
        return (cmd & 0x0F) + 1, 1
    if 0x80 <= cmd <= 0x8F:
        return cmd & 0x0F, 1
    return None


def skip_command(data: bytes, pc: int) -> tuple[int, bytes]:
    cmd = data[pc]
    if cmd in (0x52, 0x53):
        return pc + 3, data[pc:pc + 3]
    if cmd in (0x50, 0x4F):
        return pc + 2, data[pc:pc + 2]
    if cmd == 0x61:
        return pc + 3, data[pc:pc + 3]
    if cmd in (0x62, 0x63, 0x66) or 0x70 <= cmd <= 0x8F:
        return pc + 1, data[pc:pc + 1]
    if cmd == 0x67:
        if pc + 7 > len(data) or data[pc + 1] != 0x66:
            raise ValueError(f"bad data block at 0x{pc:08x}")
        size = le32(data, pc + 3)
        return pc + 7 + size, data[pc:pc + 7 + size]
    if cmd == 0xE0:
        return pc + 5, data[pc:pc + 5]
    raise ValueError(f"unsupported command 0x{cmd:02x} at 0x{pc:08x}")


def find_type0_banks(data: bytes, start: int) -> list[tuple[int, int, int]]:
    banks: list[tuple[int, int, int]] = []
    pc = start
    while pc < len(data):
        cmd = data[pc]
        if cmd == 0x66:
            break
        if cmd == 0x67:
            if pc + 7 > len(data) or data[pc + 1] != 0x66:
                raise ValueError(f"bad data block at 0x{pc:08x}")
            block_type = data[pc + 2]
            size = le32(data, pc + 3)
            block_data = pc + 7
            if block_type == 0x00:
                banks.append((pc, block_data, size))
            pc = block_data + size
        else:
            pc, _ = skip_command(data, pc)
    return banks


def find_first_e0(data: bytes, start: int) -> tuple[int, int]:
    pc = start
    while pc < len(data):
        cmd = data[pc]
        if cmd == 0x66:
            break
        if cmd == 0xE0:
            return pc, le32(data, pc + 1)
        pc, _ = skip_command(data, pc)
    raise ValueError("no 0xE0 PCM seek found")


def collect_window(
    data: bytes,
    start_pc: int,
    target_samples: int,
    source_pcm: bytes,
) -> tuple[bytearray, bytearray, int, int]:
    pc = start_pc
    out = bytearray()
    pcm = bytearray()
    dac_count = 0
    total_wait = 0
    source_pcm_pos = 0
    seek_seen = False

    while pc < len(data) and total_wait < target_samples:
        cmd = data[pc]
        if cmd == 0x66:
            break

        if cmd == 0xE0:
            source_pcm_pos = le32(data, pc + 1)
            if source_pcm_pos >= len(source_pcm):
                raise ValueError(
                    f"PCM seek {source_pcm_pos} outside source PCM bank size {len(source_pcm)}"
                )
            out += bytes([0xE0]) + pack32(len(pcm))
            seek_seen = True
            pc += 5
            continue

        if 0x80 <= cmd <= 0x8F:
            if not seek_seen:
                raise ValueError(f"DAC stream before first E0 at 0x{pc:08x}")
            if source_pcm_pos >= len(source_pcm):
                break
            pcm.append(source_pcm[source_pcm_pos])
            source_pcm_pos += 1
            out.append(cmd)
            dac_count += 1
            total_wait += cmd & 0x0F
            pc += 1
            continue

        wait = parse_wait(data, pc)
        if wait is not None:
            samples, length = wait
            out += data[pc:pc + length]
            total_wait += samples
            pc += length
            continue

        if cmd in (0x52, 0x53, 0x50, 0x4F):
            pc, raw = skip_command(data, pc)
            out += raw
            continue

        if cmd == 0x67:
            pc, _ = skip_command(data, pc)
            continue

        raise ValueError(f"unsupported command 0x{cmd:02x} in excerpt at 0x{pc:08x}")

    return out, pcm, dac_count, total_wait


def make_header(source: bytes, commands: bytes, total_samples: int) -> bytearray:
    header = bytearray(DATA_OFFSET)
    header[0x00:0x04] = b"Vgm "
    header[0x08:0x0C] = pack32(max(le32(source, 0x08), 0x150))
    header[0x18:0x1C] = pack32(total_samples)
    header[0x24:0x28] = pack32(60)
    ym_clock = le32(source, 0x2C) if len(source) >= 0x30 else 0
    header[0x2C:0x30] = pack32(ym_clock or YM2612_CLOCK_FALLBACK)
    header[0x34:0x38] = pack32(DATA_OFFSET - 0x34)
    vgm = header + commands
    vgm[0x04:0x08] = pack32(len(vgm) - 4)
    return vgm


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", nargs="?", type=Path, default=DEFAULT_INPUT)
    parser.add_argument("-o", "--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--target-samples", type=int, default=DEFAULT_TARGET_SAMPLES)
    parser.add_argument("--max-size", type=int, default=DEFAULT_MAX_SIZE)
    args = parser.parse_args()

    source = args.input.read_bytes()
    start = data_start(source)
    banks = find_type0_banks(source, start)
    if not banks:
        raise ValueError("no YM2612 type-0 PCM data block found")

    first_e0_pc, first_seek = find_first_e0(source, start)
    bank_pc, bank_data_start, bank_size = banks[0]
    if first_seek >= bank_size:
        raise ValueError(f"first E0 seek {first_seek} is outside PCM bank size {bank_size}")

    source_pcm = source[bank_data_start:bank_data_start + bank_size]
    window, pcm_excerpt, dac_count, total_wait = collect_window(
        source, first_e0_pc, args.target_samples, source_pcm
    )
    if dac_count == 0:
        raise ValueError("no 0x80..0x8f DAC stream commands after first E0")

    commands = bytearray()
    commands += bytes([0x52, 0x2A, 0x80])
    commands += bytes([0x52, 0x2B, 0x80])
    commands += bytes([0x67, 0x66, 0x00])
    commands += pack32(len(pcm_excerpt))
    commands += pcm_excerpt
    commands += window
    commands += bytes([0x52, 0x2A, 0x80])
    commands += bytes([0x52, 0x2B, 0x00])
    commands += bytes([0x66])

    vgm = make_header(source, commands, total_wait)
    if len(vgm) > args.max_size:
        raise ValueError(f"output {len(vgm)} bytes exceeds max size {args.max_size}")

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(vgm)
    output_first_e0_pc = DATA_OFFSET + 3 + 3 + 7 + len(pcm_excerpt)

    print(f"input={args.input}")
    print(f"output={args.output}")
    print(f"output_file_size={len(vgm)}")
    print(f"pcm_bank_size={len(pcm_excerpt)}")
    print(f"source_pcm_block_pc=0x{bank_pc:08x}")
    print(f"source_pcm_bank_size={bank_size}")
    print(f"excerpt_pcm_bank_size={len(pcm_excerpt)}")
    print(f"source_first_E0_pc=0x{first_e0_pc:08x}")
    print(f"first_E0_pc=0x{output_first_e0_pc:08x}")
    print(f"first_E0_seek={first_seek}")
    print(f"dac_stream_count={dac_count}")
    print(f"total_wait_samples={total_wait}")
    print(f"below_256k={len(vgm) < 256 * 1024}")


if __name__ == "__main__":
    main()
