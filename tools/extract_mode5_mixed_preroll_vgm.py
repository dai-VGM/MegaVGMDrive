#!/usr/bin/env python3
"""Extract a timed-preroll FM+PSG+PCM VGM excerpt for MiSTer mode5."""

from __future__ import annotations

from pathlib import Path
import argparse
import struct


DEFAULT_INPUT = Path("/Users/daizo/Downloads/test.vgm")
DEFAULT_OUTPUT = Path("testdata/test_mixed_excerpt_preroll.vgm")
DATA_OFFSET = 0x40
DEFAULT_PREROLL_SAMPLES = 44_100 * 5
DEFAULT_TARGET_SAMPLES = 44_100 * 10
DEFAULT_MAX_SIZE = 240 * 1024
YM2612_CLOCK_FALLBACK = 7_670_454
SN76489_CLOCK_FALLBACK = 3_579_545


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


def skip_source_command(data: bytes, pc: int) -> int:
    cmd = data[pc]
    if cmd in (0x4F, 0x50):
        return pc + 2
    if cmd in (0x51, 0x52, 0x53, 0x54, 0x55):
        return pc + 3
    if cmd == 0x61:
        return pc + 3
    if cmd in (0x62, 0x63, 0x66) or 0x70 <= cmd <= 0x8F:
        return pc + 1
    if cmd == 0x67:
        if pc + 7 > len(data) or data[pc + 1] != 0x66:
            raise ValueError(f"bad data block at 0x{pc:08x}")
        return pc + 7 + le32(data, pc + 3)
    if cmd == 0xE0:
        return pc + 5
    raise ValueError(f"unsupported source command 0x{cmd:02x} at 0x{pc:08x}")


def iter_commands(data: bytes, start: int):
    pc = start
    elapsed = 0
    while pc < len(data):
        cmd = data[pc]
        if cmd == 0x66:
            yield pc, elapsed, 1, 0
            break
        next_pc = skip_source_command(data, pc)
        wait = parse_wait(data, pc)
        wait_samples = wait[0] if wait is not None else 0
        yield pc, elapsed, next_pc - pc, wait_samples
        elapsed += wait_samples
        pc = next_pc


def find_type0_banks(data: bytes, start: int) -> list[tuple[int, int, int]]:
    banks: list[tuple[int, int, int]] = []
    for pc, _elapsed, _length, _wait in iter_commands(data, start):
        if data[pc] == 0x67:
            block_type = data[pc + 2]
            size = le32(data, pc + 3)
            if block_type == 0x00:
                banks.append((pc, pc + 7, size))
    return banks


def find_first_e0(data: bytes, start: int) -> tuple[int, int, int]:
    for pc, elapsed, _length, _wait in iter_commands(data, start):
        if data[pc] == 0xE0:
            return pc, le32(data, pc + 1), elapsed
    raise ValueError("no 0xE0 PCM seek found")


def choose_preroll_start(data: bytes, start: int, target_elapsed: int) -> tuple[int, int]:
    chosen_pc = start
    chosen_elapsed = 0
    for pc, elapsed, _length, _wait in iter_commands(data, start):
        if elapsed > target_elapsed:
            break
        if data[pc] != 0x67:
            chosen_pc = pc
            chosen_elapsed = elapsed
    return chosen_pc, chosen_elapsed


def collect_window(
    data: bytes,
    start_pc: int,
    target_samples: int,
    source_pcm: bytes,
) -> tuple[bytearray, bytearray, dict[str, int]]:
    pc = start_pc
    out = bytearray()
    pcm = bytearray()
    stats = {
        "ym0": 0,
        "ym1": 0,
        "psg": 0,
        "pcm_seek": 0,
        "dac_stream": 0,
        "wait": 0,
    }
    source_pcm_pos = 0
    seek_seen = False

    while pc < len(data) and stats["wait"] < target_samples:
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
            stats["pcm_seek"] += 1
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
            stats["dac_stream"] += 1
            stats["wait"] += cmd & 0x0F
            pc += 1
            continue

        wait = parse_wait(data, pc)
        if wait is not None:
            samples, length = wait
            out += data[pc:pc + length]
            stats["wait"] += samples
            pc += length
            continue

        if cmd == 0x52:
            out += data[pc:pc + 3]
            stats["ym0"] += 1
            pc += 3
            continue

        if cmd == 0x53:
            out += data[pc:pc + 3]
            stats["ym1"] += 1
            pc += 3
            continue

        if cmd == 0x50:
            out += data[pc:pc + 2]
            stats["psg"] += 1
            pc += 2
            continue

        if cmd == 0x4F:
            out += data[pc:pc + 2]
            pc += 2
            continue

        if cmd == 0x67:
            pc = skip_source_command(data, pc)
            continue

        raise ValueError(f"unsupported command 0x{cmd:02x} in excerpt at 0x{pc:08x}")

    return out, pcm, stats


def make_header(source: bytes, commands: bytes, total_samples: int) -> bytearray:
    header = bytearray(DATA_OFFSET)
    header[0x00:0x04] = b"Vgm "
    header[0x08:0x0C] = pack32(max(le32(source, 0x08), 0x150))
    sn_clock = le32(source, 0x0C) if len(source) >= 0x10 else 0
    ym_clock = le32(source, 0x2C) if len(source) >= 0x30 else 0
    header[0x0C:0x10] = pack32(sn_clock or SN76489_CLOCK_FALLBACK)
    header[0x18:0x1C] = pack32(total_samples)
    header[0x24:0x28] = pack32(60)
    header[0x2C:0x30] = pack32(ym_clock or YM2612_CLOCK_FALLBACK)
    header[0x34:0x38] = pack32(DATA_OFFSET - 0x34)
    vgm = header + commands
    vgm[0x04:0x08] = pack32(len(vgm) - 4)
    return vgm


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", nargs="?", type=Path, default=DEFAULT_INPUT)
    parser.add_argument("-o", "--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--preroll-samples", type=int, default=DEFAULT_PREROLL_SAMPLES)
    parser.add_argument("--target-samples", type=int, default=DEFAULT_TARGET_SAMPLES)
    parser.add_argument("--max-size", type=int, default=DEFAULT_MAX_SIZE)
    args = parser.parse_args()

    source = args.input.read_bytes()
    start = data_start(source)
    banks = find_type0_banks(source, start)
    if not banks:
        raise ValueError("no YM2612 type-0 PCM data block found")

    first_e0_pc, first_seek, first_e0_elapsed = find_first_e0(source, start)
    bank_pc, bank_data_start, bank_size = banks[0]
    if first_seek >= bank_size:
        raise ValueError(f"first E0 seek {first_seek} is outside PCM bank size {bank_size}")

    preroll_target_elapsed = max(0, first_e0_elapsed - args.preroll_samples)
    window_start_pc, window_start_elapsed = choose_preroll_start(
        source, start, preroll_target_elapsed
    )
    actual_preroll = first_e0_elapsed - window_start_elapsed

    source_pcm = source[bank_data_start:bank_data_start + bank_size]
    window, pcm_excerpt, stats = collect_window(
        source, window_start_pc, args.target_samples, source_pcm
    )
    if stats["pcm_seek"] == 0:
        raise ValueError("no 0xE0 PCM seek in selected window")
    if stats["dac_stream"] == 0:
        raise ValueError("no 0x80..0x8f DAC stream commands in selected window")

    commands = bytearray()
    commands += bytes([0x67, 0x66, 0x00])
    commands += pack32(len(pcm_excerpt))
    commands += pcm_excerpt
    commands += window
    commands += bytes([0x52, 0x2A, 0x80])
    commands += bytes([0x52, 0x2B, 0x00])
    commands += bytes([0x66])
    total_ym0 = stats["ym0"] + 2

    vgm = make_header(source, commands, stats["wait"])
    if len(vgm) > args.max_size:
        raise ValueError(f"output {len(vgm)} bytes exceeds max size {args.max_size}")

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(vgm)

    print(f"input={args.input}")
    print(f"output={args.output}")
    print(f"output_size={len(vgm)}")
    print(f"source_data_start=0x{start:08x}")
    print(f"source_pcm_block_pc=0x{bank_pc:08x}")
    print(f"source_pcm_bank_size={bank_size}")
    print(f"excerpt_pcm_bank_size={len(pcm_excerpt)}")
    print(f"source_first_E0_pc=0x{first_e0_pc:08x}")
    print(f"source_first_E0_elapsed_samples={first_e0_elapsed}")
    print(f"window_start_pc=0x{window_start_pc:08x}")
    print(f"window_start_elapsed_samples={window_start_elapsed}")
    print(f"preroll_wait_samples={actual_preroll}")
    print(f"preroll_seconds={actual_preroll / 44100:.3f}")
    print(f"audible_window_duration_seconds={stats['wait'] / 44100:.3f}")
    print(f"ym_port0_write_count={total_ym0}")
    print(f"ym_port1_write_count={stats['ym1']}")
    print(f"psg_write_count={stats['psg']}")
    print(f"pcm_seek_count={stats['pcm_seek']}")
    print(f"dac_stream_count={stats['dac_stream']}")
    print(f"total_wait_samples={stats['wait']}")
    print(f"below_256k={len(vgm) < 256 * 1024}")


if __name__ == "__main__":
    main()
