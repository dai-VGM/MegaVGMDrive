#!/usr/bin/env python3
"""Generate small uncompressed VGM files for mode5 behavior debugging."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import argparse
import math
import struct


DATA_OFFSET = 0x40
VGM_VERSION = 0x00000150
SN76489_CLOCK_HZ = 3_579_545
YM2612_CLOCK_HZ = 7_670_454
MAX_MODE5_BRAM_BYTES = 256 * 1024


@dataclass
class Stats:
    file_size: int = 0
    wait_samples: int = 0
    ym_writes: int = 0
    psg_writes: int = 0
    pcm_seek_count: int = 0
    dac_stream_count: int = 0
    unsupported_count: int = 0
    end_reached: bool = False


def pack32(value: int) -> bytes:
    return struct.pack("<I", value)


def wait_samples(commands: bytearray, samples: int, stats: Stats) -> None:
    if samples < 0:
        raise ValueError("wait sample count must be non-negative")

    stats.wait_samples += samples
    while samples >= 0xFFFF:
        commands += bytes([0x61, 0xFF, 0xFF])
        samples -= 0xFFFF
    if samples:
        commands += bytes([0x61, samples & 0xFF, (samples >> 8) & 0xFF])


def ym_write(commands: bytearray, port: int, reg: int, value: int, stats: Stats) -> None:
    commands += bytes([0x53 if port else 0x52, reg & 0xFF, value & 0xFF])
    stats.ym_writes += 1


def psg_write(commands: bytearray, value: int, stats: Stats) -> None:
    commands += bytes([0x50, value & 0xFF])
    stats.psg_writes += 1


def psg_tone(
    commands: bytearray,
    channel: int,
    divider: int,
    volume: int,
    stats: Stats,
) -> None:
    if channel < 0 or channel > 2:
        raise ValueError("PSG tone channel must be in 0..2")
    if divider < 1 or divider > 0x3FF:
        raise ValueError("PSG tone divider must be in 1..0x3ff")
    if volume < 0 or volume > 0x0F:
        raise ValueError("PSG volume must be in 0..0x0f")

    tone_latch = 0x80 | (channel << 5)
    volume_latch = 0x90 | (channel << 5)
    psg_write(commands, volume_latch | 0x0F, stats)
    psg_write(commands, tone_latch | (divider & 0x0F), stats)
    psg_write(commands, (divider >> 4) & 0x3F, stats)
    psg_write(commands, volume_latch | volume, stats)


def psg_ch0_tone(commands: bytearray, divider: int, volume: int, stats: Stats) -> None:
    psg_tone(commands, channel=0, divider=divider, volume=volume, stats=stats)


def psg_ch0_mute(commands: bytearray, stats: Stats) -> None:
    psg_write(commands, 0x90 | 0x0F, stats)


def psg_all_silence(commands: bytearray, stats: Stats) -> None:
    psg_write(commands, 0x9F, stats)
    psg_write(commands, 0xBF, stats)
    psg_write(commands, 0xDF, stats)
    psg_write(commands, 0xFF, stats)


def psg_known_init(commands: bytearray, stats: Stats) -> None:
    psg_all_silence(commands, stats)
    psg_write(commands, 0x80, stats)
    psg_write(commands, 0x08, stats)
    psg_write(commands, 0xA0, stats)
    psg_write(commands, 0x10, stats)
    psg_write(commands, 0xC0, stats)
    psg_write(commands, 0x18, stats)
    psg_write(commands, 0xE0, stats)


def psg_beep(
    commands: bytearray,
    stats: Stats,
    divider: int = 0x080,
    samples: int = 4_410,
    volume: int = 0x02,
) -> None:
    psg_ch0_tone(commands, divider, volume, stats)
    wait_samples(commands, samples, stats)
    psg_ch0_mute(commands, stats)


def pcm_seek(commands: bytearray, offset: int, stats: Stats) -> None:
    commands += bytes([0xE0]) + pack32(offset)
    stats.pcm_seek_count += 1


def dac_stream(commands: bytearray, opcode: int, stats: Stats) -> None:
    if opcode < 0x80 or opcode > 0x8F:
        raise ValueError(f"not a DAC stream opcode: 0x{opcode:02x}")
    commands.append(opcode)
    stats.dac_stream_count += 1
    stats.wait_samples += opcode & 0x0F


def unsupported(commands: bytearray, opcode: int, stats: Stats) -> None:
    commands.append(opcode & 0xFF)
    stats.unsupported_count += 1


def end(commands: bytearray, stats: Stats) -> None:
    commands.append(0x66)
    stats.end_reached = True


def make_vgm(commands: bytes, stats: Stats) -> bytes:
    vgm = bytearray(DATA_OFFSET)
    vgm[0x00:0x04] = b"Vgm "
    vgm[0x08:0x0C] = pack32(VGM_VERSION)
    vgm[0x0C:0x10] = pack32(SN76489_CLOCK_HZ)
    vgm[0x18:0x1C] = pack32(stats.wait_samples)
    vgm[0x24:0x28] = pack32(60)
    vgm[0x2C:0x30] = pack32(YM2612_CLOCK_HZ)
    vgm[0x34:0x38] = pack32(DATA_OFFSET - 0x34)
    vgm += commands
    vgm[0x04:0x08] = pack32(len(vgm) - 4)
    stats.file_size = len(vgm)
    if stats.file_size >= MAX_MODE5_BRAM_BYTES:
        raise ValueError(f"VGM too large for 256 KiB BRAM: {stats.file_size} bytes")
    return bytes(vgm)


def build_short_end() -> tuple[bytes, Stats]:
    stats = Stats()
    commands = bytearray()
    psg_known_init(commands, stats)
    wait_samples(commands, 735, stats)
    psg_ch0_tone(commands, divider=0x050, volume=0x02, stats=stats)
    wait_samples(commands, 30_870, stats)
    psg_ch0_tone(commands, divider=0x180, volume=0x02, stats=stats)
    wait_samples(commands, 52_920, stats)
    psg_all_silence(commands, stats)
    wait_samples(commands, 8_820, stats)
    end(commands, stats)
    return make_vgm(commands, stats), stats


def build_long_wait() -> tuple[bytes, Stats]:
    stats = Stats()
    commands = bytearray()

    # Periodic low PSG beeps make load-while-playing mute behavior obvious.
    for _ in range(30):
        psg_ch0_tone(commands, divider=0x180, volume=0x03, stats=stats)
        wait_samples(commands, 8_820, stats)
        psg_ch0_mute(commands, stats)
        wait_samples(commands, 35_280, stats)
    end(commands, stats)
    return make_vgm(commands, stats), stats


def build_bad_cmd_f2() -> tuple[bytes, Stats]:
    stats = Stats()
    commands = bytearray()
    psg_beep(commands, stats, divider=0x050, samples=4_410, volume=0x02)
    wait_samples(commands, 11_025, stats)
    unsupported(commands, 0xF2, stats)
    return make_vgm(commands, stats), stats


def build_pcm_probe_short() -> tuple[bytes, Stats]:
    stats = Stats()
    commands = bytearray()
    pcm_len = 512
    pcm = bytearray()

    for index in range(pcm_len):
        if (index // 8) & 1:
            sample = 0x20 if (index & 1) else 0xE0
        else:
            sample = round(128 + 112 * math.sin((2 * math.pi * index) / 16))
        pcm.append(max(0, min(255, sample)))

    ym_write(commands, 0, 0x2A, 0x80, stats)
    ym_write(commands, 0, 0x2B, 0x80, stats)
    commands += bytes([0x67, 0x66, 0x00]) + pack32(len(pcm)) + pcm
    pcm_seek(commands, 0, stats)

    for _ in range(pcm_len):
        dac_stream(commands, 0x8F, stats)

    ym_write(commands, 0, 0x2A, 0x80, stats)
    ym_write(commands, 0, 0x2B, 0x00, stats)
    end(commands, stats)
    return make_vgm(commands, stats), stats


def print_stats(path: Path, stats: Stats) -> None:
    print(path)
    print(f"  file_size={stats.file_size}")
    print(f"  wait_samples={stats.wait_samples}")
    print(f"  duration_seconds={stats.wait_samples / 44_100:.3f}")
    print(f"  ym_write_count={stats.ym_writes}")
    print(f"  psg_write_count={stats.psg_writes}")
    print(f"  pcm_seek_count={stats.pcm_seek_count}")
    print(f"  dac_stream_count={stats.dac_stream_count}")
    print(f"  unsupported_count={stats.unsupported_count}")
    print(f"  end_reached={int(stats.end_reached)}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "-o",
        "--output-dir",
        type=Path,
        default=Path("testdata"),
        help="directory for generated VGM files",
    )
    args = parser.parse_args()

    outputs = [
        ("behavior_short_end.vgm", build_short_end),
        ("behavior_long_wait.vgm", build_long_wait),
        ("behavior_bad_cmd_f2.vgm", build_bad_cmd_f2),
        ("behavior_pcm_probe_short.vgm", build_pcm_probe_short),
    ]

    args.output_dir.mkdir(parents=True, exist_ok=True)
    for filename, builder in outputs:
        vgm, stats = builder()
        path = args.output_dir / filename
        path.write_bytes(vgm)
        print_stats(path, stats)


if __name__ == "__main__":
    main()
