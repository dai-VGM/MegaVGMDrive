#!/usr/bin/env python3
"""Generate short PSG-only VGM files for SN76489 period checks."""

from __future__ import annotations

from pathlib import Path
import struct


DATA_OFFSET = 0x40
VGM_VERSION = 0x00000150
SN76489_CLOCK_HZ = 3_579_545
YM2612_CLOCK_HZ = 7_670_454
PERIODS = (0x100, 0x180, 0x0C0, 0x060)


def le32(value: int) -> bytes:
    return struct.pack("<I", value)


def wait_samples(commands: bytearray, samples: int) -> None:
    while samples >= 0xFFFF:
        commands += bytes([0x61, 0xFF, 0xFF])
        samples -= 0xFFFF
    if samples:
        commands += bytes([0x61, samples & 0xFF, (samples >> 8) & 0xFF])


def psg_write(commands: bytearray, value: int) -> None:
    commands += bytes([0x50, value & 0xFF])


def build_vgm(period: int) -> bytes:
    commands = bytearray()

    # Mute all channels before programming channel 0.
    for value in (0x9F, 0xBF, 0xDF, 0xFF):
        psg_write(commands, value)

    # Channel 0 tone period, then loud but not max volume.
    psg_write(commands, 0x80 | (period & 0x0F))
    psg_write(commands, (period >> 4) & 0x3F)
    psg_write(commands, 0x92)
    wait_samples(commands, 44_100 * 2)
    psg_write(commands, 0x9F)
    wait_samples(commands, 4_410)
    commands.append(0x66)

    header = bytearray(DATA_OFFSET)
    header[0:4] = b"Vgm "
    eof_offset = len(header) + len(commands) - 4
    header[0x04:0x08] = le32(eof_offset)
    header[0x08:0x0C] = le32(VGM_VERSION)
    header[0x0C:0x10] = le32(SN76489_CLOCK_HZ)
    header[0x2C:0x30] = le32(YM2612_CLOCK_HZ)
    header[0x34:0x38] = le32(DATA_OFFSET - 0x34)
    return bytes(header) + bytes(commands)


def main() -> None:
    out_dir = Path("testdata")
    out_dir.mkdir(parents=True, exist_ok=True)
    for period in PERIODS:
        path = out_dir / f"psg_tone_period_{period:04x}.vgm"
        path.write_bytes(build_vgm(period))
        freq = SN76489_CLOCK_HZ / (32 * period)
        print(f"{path}: period=0x{period:03x} expected={freq:.2f}Hz")


if __name__ == "__main__":
    main()
