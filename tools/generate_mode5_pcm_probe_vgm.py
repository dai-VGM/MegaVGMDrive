#!/usr/bin/env python3
"""Generate a tiny uncompressed YM2612 DAC-stream VGM for mode5 bring-up."""

from pathlib import Path
import math
import struct


YM2612_CLOCK_HZ = 7_670_454
DATA_OFFSET = 0x40
PCM_SAMPLES = 4096
OUT_PATH = Path("testdata/mode5_pcm_probe.vgm")


def le32(value: int) -> bytes:
    return struct.pack("<I", value)


def main() -> None:
    pcm = bytearray()
    for index in range(PCM_SAMPLES):
        # 8-bit unsigned sine, centered at 0x80 for YM2612 DAC silence.
        sample = round(128 + 96 * math.sin((2 * math.pi * index) / 64))
        pcm.append(max(0, min(255, sample)))

    commands = bytearray()
    commands += bytes([0x52, 0x2A, 0x80])  # neutral DAC byte before enable
    commands += bytes([0x52, 0x2B, 0x80])  # YM2612 DAC enable
    commands += bytes([0x67, 0x66, 0x00])
    commands += le32(len(pcm))
    commands += pcm
    commands += bytes([0xE0]) + le32(0)
    dac_stream = bytes(0x80 | (index & 0x0F) for index in range(len(pcm)))
    commands += dac_stream
    commands += bytes([0x52, 0x2A, 0x80])
    commands += bytes([0x52, 0x2B, 0x00])
    commands += bytes([0x66])

    vgm = bytearray(DATA_OFFSET)
    vgm[0x00:0x04] = b"Vgm "
    vgm[0x08:0x0C] = le32(0x00000150)
    vgm[0x18:0x1C] = le32(sum(opcode & 0x0F for opcode in dac_stream))
    vgm[0x24:0x28] = le32(60)
    vgm[0x2C:0x30] = le32(YM2612_CLOCK_HZ)
    vgm[0x34:0x38] = le32(DATA_OFFSET - 0x34)
    vgm += commands
    vgm[0x04:0x08] = le32(len(vgm) - 4)

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUT_PATH.write_bytes(vgm)
    print(f"wrote {OUT_PATH} ({len(vgm)} bytes)")


if __name__ == "__main__":
    main()
