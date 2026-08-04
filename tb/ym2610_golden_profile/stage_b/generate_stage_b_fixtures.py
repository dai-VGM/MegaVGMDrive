#!/usr/bin/env python3
"""Generate redistributable Stage B compatibility fixtures in a temp dir."""

from __future__ import annotations

import json
import pathlib
import struct
import sys


def u32(value: int) -> bytes:
    return struct.pack("<I", value & 0xFFFFFFFF)


def write(port: int, address: int, data: int) -> bytes:
    return bytes((0x58 + port, address, data))


def block(kind: int, rom_size: int, logical: int, payload: bytes,
          *, declared: int | None = None, compressed: bool = False) -> bytes:
    body = u32(rom_size) + u32(logical) + payload
    size = len(body) if declared is None else declared
    if compressed:
        size |= 0x80000000
    return b"\x67\x66" + bytes((kind,)) + u32(size) + body


def vgm(commands: bytes, *, b: bool = False, dual: bool = False,
        loop_absolute: int | None = None) -> bytes:
    header = bytearray(0x80)
    header[:4] = b"Vgm "
    header[8:12] = u32(0x151)
    header[0x34:0x38] = u32(0x80 - 0x34)
    flags = (0x80000000 if b else 0) | (0x40000000 if dual else 0)
    header[0x4C:0x50] = u32(flags | 8_000_000)
    if loop_absolute is not None:
        header[0x1C:0x20] = u32(loop_absolute - 0x1C)
    result = bytes(header) + commands
    return result[:4] + u32(len(result) - 4) + result[8:]


def prepared(raw: bytes, directory: str = "Fixture", basename: str = "Stage B") -> bytes:
    d = directory.encode("ascii")
    b = basename.encode("ascii")
    trailer = bytearray(128)
    trailer[:8] = b"MVGMTTL\0"
    trailer[8] = 1
    trailer[9] = (1 if d else 0) | (2 if b else 0)
    trailer[10] = len(d)
    trailer[11] = len(b)
    trailer[12:16] = b"\x80\0\0\0"
    trailer[16:20] = u32(len(raw))
    trailer[32:32 + len(d)] = d
    trailer[64:64 + len(b)] = b
    return raw + trailer


def main() -> int:
    out = pathlib.Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    a = block(0x82, 0x100000, 0x100, bytes(range(32)))
    b = block(0x83, 0x80000, 0x200, bytes(range(32, 64)))
    standard = vgm(a + b + write(0, 0x31, 0x01) + b"\x63\x66")
    b_compatible = vgm(a + b + write(0, 0x31, 0x01) + b"\x62\x66", b=True)
    overflow = b"".join(block(0x82, 0x100000, index * 2, bytes((index,)))
                         for index in range(9)) + b"\x66"

    fixtures: dict[str, tuple[bytes, int, int]] = {
        "standard_valid_raw": (standard, 0, 0x00),
        "b_compatible_raw": (b_compatible, 1, 0x00),
        "b_only_key_on": (vgm(write(0, 0x28, 0xF0) + b"\x66", b=True), 2, 0x03),
        "b_only_frequency_setup": (vgm(write(0, 0xA0, 0x22) + b"\x66", b=True), 2, 0x03),
        "b_only_operator_setup": (vgm(write(1, 0x30, 0x01) + b"\x66", b=True), 2, 0x03),
        "dual_flag": (vgm(b"\x66", b=True, dual=True), 3, 0x02),
        "unknown_register": (vgm(write(0, 0x20, 0) + b"\x66", b=True), 4, 0x04),
        "unsupported_opcode": (vgm(b"\x50\x00\x66"), 5, 0x05),
        "malformed_67": (vgm(b"\x67\x00\x66"), 4, 0x06),
        "compressed_block": (vgm(block(0x82, 0x100000, 0, b"x", compressed=True) + b"\x66"), 4, 0x06),
        "unknown_block_type": (vgm(block(0x81, 0x100000, 0, b"x") + b"\x66"), 4, 0x06),
        "a_logical_range": (vgm(block(0x82, 0x100000, 0xFFFF0, bytes(32)) + b"\x66"), 4, 0x07),
        "b_logical_range": (vgm(block(0x83, 0x80000, 0x7FFF0, bytes(32)) + b"\x66"), 4, 0x07),
        "payload_eof": (vgm(block(0x82, 0x100000, 0, b"", declared=0x100)), 4, 0x07),
        "descriptor_overflow": (vgm(overflow), 4, 0x08),
        "missing_end": (vgm(b"\x62"), 4, 0x07),
        "invalid_loop_target": (vgm(write(0, 0x31, 1) + b"\x66", loop_absolute=0x81), 4, 0x01),
        "prepared_valid": (prepared(standard), 0, 0x00),
    }
    manifest = {}
    for name, (payload, classification, reject) in fixtures.items():
        path = out / f"{name}.vgm"
        path.write_bytes(payload)
        original = len(payload) - 128 if name == "prepared_valid" else len(payload)
        manifest[name] = {
            "file": path.name,
            "physical": len(payload),
            "original": original,
            "classification": classification,
            "reject": reject,
            "accepted": reject == 0,
        }
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
