#!/usr/bin/env python3
"""Generate large uncompressed VGM size-sweep files for mode5 DDRAM tests."""

from __future__ import annotations

from pathlib import Path
import argparse
import struct


DATA_OFFSET = 0x40
VGM_VERSION = 0x00000150
SN76489_CLOCK_HZ = 3_579_545
YM2612_CLOCK_HZ = 7_670_454
TARGETS_KIB = (1536, 2048, 2560, 3072, 4095, 4096, 4097, 4608)


def le32(value: int) -> bytes:
    return struct.pack("<I", value)


def psg_marker(commands: bytearray, marker_index: int) -> int:
    """Append a very short PSG chirp and return the added wait samples."""

    divider = 0x060 + ((marker_index & 7) * 0x18)
    wait_samples = 16
    commands += bytes(
        [
            0x50,
            0x9F,  # ch0 mute before retune
            0x50,
            0x80 | (divider & 0x0F),
            0x50,
            (divider >> 4) & 0x3F,
            0x50,
            0x92,  # ch0 audible, quiet
            0x70 | (wait_samples - 1),
            0x50,
            0x9F,  # ch0 mute
        ]
    )
    return wait_samples


def build_commands(target_size: int) -> tuple[bytes, int, int]:
    if target_size <= DATA_OFFSET + 1:
        raise ValueError("target size is too small")

    commands = bytearray()
    total_wait_samples = 0
    marker_count = 0

    commands += bytes([0x50, 0x9F, 0x50, 0xBF, 0x50, 0xDF, 0x50, 0xFF])

    # Keep one byte for END. Fill the body with valid short waits so the parser
    # must walk the entire loaded image before stopping.
    body_limit = target_size - DATA_OFFSET - 1
    next_marker_at = 256 * 1024
    while len(commands) < body_limit:
        if len(commands) >= next_marker_at and body_limit - len(commands) >= 11:
            total_wait_samples += psg_marker(commands, marker_count)
            marker_count += 1
            next_marker_at += 256 * 1024
        else:
            commands.append(0x70)  # wait 1 sample
            total_wait_samples += 1

    commands.append(0x66)
    if len(commands) != target_size - DATA_OFFSET:
        raise AssertionError("internal size accounting error")

    return bytes(commands), total_wait_samples, marker_count


def make_vgm(target_size: int) -> tuple[bytes, int]:
    commands, total_wait_samples, marker_count = build_commands(target_size)

    vgm = bytearray(DATA_OFFSET)
    vgm[0x00:0x04] = b"Vgm "
    vgm[0x08:0x0C] = le32(VGM_VERSION)
    vgm[0x0C:0x10] = le32(SN76489_CLOCK_HZ)
    vgm[0x18:0x1C] = le32(total_wait_samples)
    vgm[0x24:0x28] = le32(60)
    vgm[0x2C:0x30] = le32(YM2612_CLOCK_HZ)
    vgm[0x34:0x38] = le32(DATA_OFFSET - 0x34)
    vgm += commands
    vgm[0x04:0x08] = le32(len(vgm) - 4)

    if len(vgm) != target_size:
        raise AssertionError(f"expected {target_size} bytes, got {len(vgm)}")

    return bytes(vgm), marker_count


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate mode5 DDRAM size-sweep VGM files."
    )
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=Path("testdata"),
        help="output directory, default: testdata",
    )
    args = parser.parse_args()

    args.out_dir.mkdir(parents=True, exist_ok=True)

    for kib in TARGETS_KIB:
        target_size = kib * 1024
        vgm, marker_count = make_vgm(target_size)
        out_path = args.out_dir / f"mode5_size_sweep_{kib}k.vgm"
        out_path.write_bytes(vgm)
        print(f"wrote {out_path} ({len(vgm)} bytes, markers={marker_count})")


if __name__ == "__main__":
    main()
