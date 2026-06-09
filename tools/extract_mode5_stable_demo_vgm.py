#!/usr/bin/env python3
"""Create a small song-head FM+PSG+PCM VGM demo for MiSTer mode5."""

from __future__ import annotations

from pathlib import Path
import argparse
import struct


DEFAULT_INPUT = Path("/Users/daizo/Downloads/test.vgm")
DEFAULT_OUTPUT = Path("testdata/test_stable_demo.vgm")
DATA_OFFSET = 0x40
DEFAULT_TARGET_SAMPLES = 44_100 * 20
DEFAULT_MIN_SAMPLES = 44_100 * 10
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


def find_first_type0_block(data: bytes, start: int) -> tuple[int, int, int, int]:
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
            if block_type == 0x00:
                return pc, pc + 7, size, pc + 7 + size
            pc = pc + 7 + size
        else:
            pc = skip_source_command(data, pc)
    raise ValueError("no YM2612 type-0 PCM data block found")


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


def collect_from_song_head(
    data: bytes,
    commands_start: int,
    target_samples: int,
) -> tuple[bytearray, dict[str, int]]:
    pc = commands_start
    out = bytearray()
    stats = {
        "ym0": 0,
        "ym1": 0,
        "psg": 0,
        "pcm_seek": 0,
        "dac_stream": 0,
        "wait": 0,
        "unsupported": 0,
        "end_reached": 0,
    }

    while pc < len(data) and stats["wait"] < target_samples:
        cmd = data[pc]
        if cmd == 0x66:
            stats["end_reached"] = 1
            break

        wait = parse_wait(data, pc)
        if wait is not None:
            samples, length = wait
            out += data[pc:pc + length]
            stats["wait"] += samples
            if 0x80 <= cmd <= 0x8F:
                stats["dac_stream"] += 1
            pc += length
            continue

        if cmd == 0xE0:
            out += data[pc:pc + 5]
            stats["pcm_seek"] += 1
            pc += 5
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

        stats["unsupported"] += 1
        raise ValueError(f"unsupported command 0x{cmd:02x} in demo at 0x{pc:08x}")

    return out, stats


def build_vgm(
    source: bytes,
    block_pc: int,
    block_end: int,
    commands_start: int,
    target_samples: int,
) -> tuple[bytearray, dict[str, int]]:
    window, stats = collect_from_song_head(source, commands_start, target_samples)
    commands = bytearray()
    commands += source[block_pc:block_end]
    commands += window
    commands += bytes([0x66])
    return make_header(source, commands, stats["wait"]), stats


def choose_duration(
    source: bytes,
    block_pc: int,
    block_end: int,
    commands_start: int,
    target_samples: int,
    min_samples: int,
    max_size: int,
) -> tuple[bytearray, dict[str, int], int]:
    vgm, stats = build_vgm(source, block_pc, block_end, commands_start, target_samples)
    if len(vgm) <= max_size:
        return vgm, stats, target_samples

    low = min_samples
    high = target_samples
    best_vgm: bytearray | None = None
    best_stats: dict[str, int] | None = None
    best_target = 0

    while low <= high:
        mid = (low + high) // 2
        candidate, candidate_stats = build_vgm(
            source, block_pc, block_end, commands_start, mid
        )
        if len(candidate) <= max_size:
            best_vgm = candidate
            best_stats = candidate_stats
            best_target = mid
            low = mid + 1
        else:
            high = mid - 1

    if best_vgm is None or best_stats is None:
        raise ValueError(
            f"could not fit minimum duration {min_samples / 44100:.3f}s under {max_size} bytes"
        )
    return best_vgm, best_stats, best_target


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", nargs="?", type=Path, default=DEFAULT_INPUT)
    parser.add_argument("-o", "--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--target-samples", type=int, default=DEFAULT_TARGET_SAMPLES)
    parser.add_argument("--min-samples", type=int, default=DEFAULT_MIN_SAMPLES)
    parser.add_argument("--max-size", type=int, default=DEFAULT_MAX_SIZE)
    args = parser.parse_args()

    source = args.input.read_bytes()
    start = data_start(source)
    block_pc, block_data, block_size, block_end = find_first_type0_block(source, start)
    vgm, stats, chosen_target = choose_duration(
        source,
        block_pc,
        block_end,
        block_end,
        args.target_samples,
        args.min_samples,
        args.max_size,
    )

    if stats["pcm_seek"] == 0:
        raise ValueError("selected demo has no 0xE0 PCM seek")
    if stats["dac_stream"] == 0:
        raise ValueError("selected demo has no 0x80..0x8f DAC stream command")

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(vgm)

    print(f"input={args.input}")
    print(f"output={args.output}")
    print(f"output_size={len(vgm)}")
    print(f"source_data_start=0x{start:08x}")
    print(f"source_pcm_block_pc=0x{block_pc:08x}")
    print(f"source_pcm_bank_size={block_size}")
    print(f"source_commands_start_pc=0x{block_end:08x}")
    print(f"chosen_target_samples={chosen_target}")
    print(f"duration_seconds={stats['wait'] / 44100:.3f}")
    print(f"ym_port0_write_count={stats['ym0']}")
    print(f"ym_port1_write_count={stats['ym1']}")
    print(f"psg_write_count={stats['psg']}")
    print(f"pcm_seek_count={stats['pcm_seek']}")
    print(f"dac_stream_count={stats['dac_stream']}")
    print(f"total_wait_samples={stats['wait']}")
    print(f"below_256k={len(vgm) < 256 * 1024}")
    print("END_reached=True")
    print(f"unsupported_commands_count={stats['unsupported']}")


if __name__ == "__main__":
    main()
