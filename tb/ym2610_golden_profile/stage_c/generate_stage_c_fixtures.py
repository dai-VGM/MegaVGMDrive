#!/usr/bin/env python3
"""Generate copyright-free Stage C VGM fixtures under a caller-owned path."""

from __future__ import annotations

import json
from pathlib import Path
import struct
import sys

from stage_c_reference import ParseResult, parse_vgm


def write32(target: bytearray, offset: int, value: int) -> None:
    struct.pack_into("<I", target, offset, value)


def reg(port: int, address: int, data: int) -> bytes:
    return bytes((0x58 | port, address, data))


def wait16(samples: int) -> bytes:
    return bytes((0x61, samples & 0xFF, samples >> 8))


def data_block(kind: int, rom_size: int, logical: int, payload: bytes) -> bytes:
    block_size = 8 + len(payload)
    return (
        bytes((0x67, 0x66, kind))
        + struct.pack("<I", block_size)
        + struct.pack("<I", rom_size)
        + struct.pack("<I", logical)
        + payload
    )


def fm_setup() -> bytes:
    commands = bytearray()
    channel = 1
    commands += reg(0, 0xA4 + channel, 0x22)
    commands += reg(0, 0xA0 + channel, 0x00)
    commands += reg(0, 0xB0 + channel, 0x07)
    commands += reg(0, 0xB4 + channel, 0xC0)
    for offset, level in ((0x00, 0x00), (0x08, 0x7F),
                          (0x04, 0x7F), (0x0C, 0x7F)):
        commands += reg(0, 0x30 + channel + offset, 0x01)
        commands += reg(0, 0x40 + channel + offset, level)
        commands += reg(0, 0x50 + channel + offset, 0x1F)
        commands += reg(0, 0x60 + channel + offset, 0x00)
        commands += reg(0, 0x70 + channel + offset, 0x00)
        commands += reg(0, 0x80 + channel + offset, 0xAF)
        commands += reg(0, 0x90 + channel + offset, 0x00)
    return bytes(commands)


def make_vgm(
    commands: bytes,
    *,
    variant_b: bool = False,
    dual: bool = False,
    loop_command_offset: int | None = None,
    prepared: bool = False,
    directory: bytes = b"StageC",
    basename: bytes = b"Synthetic",
) -> bytes:
    header = bytearray(0x80)
    header[:4] = b"Vgm "
    write32(header, 0x08, 0x00000171)
    write32(header, 0x34, 0x4C)
    clock = 8_000_000
    if variant_b:
        clock |= 0x80000000
    if dual:
        clock |= 0x40000000
    write32(header, 0x4C, clock)
    body = header + commands
    write32(body, 0x04, len(body) - 4)
    if loop_command_offset is not None:
        target = 0x80 + loop_command_offset
        write32(body, 0x1C, target - 0x1C)
    if not prepared:
        return bytes(body)

    trailer = bytearray(128)
    trailer[:8] = b"MVGMTTL\x00"
    trailer[8] = 1
    trailer[9] = 3
    trailer[10] = len(directory)
    trailer[11] = len(basename)
    trailer[12] = 0x80
    write32(trailer, 16, len(body))
    trailer[32:32 + len(directory)] = directory
    trailer[64:64 + len(basename)] = basename
    return bytes(body + trailer)


def summary(result: ParseResult) -> dict[str, object]:
    return {
        "original_size": result.original_size,
        "physical_size": result.physical_size,
        "data_offset": result.data_offset,
        "loop_target": result.loop_target,
        "clock": result.clock,
        "commands": result.command_count,
        "writes": result.total_writes,
        "forwarded_fm_global": result.forwarded_fm_global,
        "forwarded_ssg": result.forwarded_ssg,
        "suppressed_adpcma": result.suppressed_adpcma,
        "suppressed_adpcmb": result.suppressed_adpcmb,
        "data_blocks": result.data_blocks,
        "total_samples": result.total_samples,
        "trace_hash": result.trace_hash,
        "first256_trace_hash": result.first256_trace_hash,
    }


def main() -> int:
    if len(sys.argv) != 2:
        raise SystemExit("usage: generate_stage_c_fixtures.py OUTPUT_DIR")
    output = Path(sys.argv[1])
    output.mkdir(parents=True, exist_ok=True)

    fm = bytearray(fm_setup())
    fm += reg(0, 0x28, 0xF1)
    fm += wait16(735)
    fm += reg(0, 0x28, 0x01)
    fm += wait16(64)
    fm += b"\x66"

    fm_loop_prefix = bytearray(fm_setup())
    loop_offset = len(fm_loop_prefix)
    fm_loop = bytearray(fm_loop_prefix)
    fm_loop += reg(0, 0x28, 0xF1)
    fm_loop += wait16(256)
    fm_loop += reg(0, 0x28, 0x01)
    fm_loop += wait16(32)
    fm_loop += b"\x66"

    ssg = bytearray()
    ssg += reg(0, 0x00, 0x20)
    ssg += reg(0, 0x01, 0x01)
    ssg += reg(0, 0x02, 0x30)
    ssg += reg(0, 0x03, 0x01)
    ssg += reg(0, 0x04, 0x40)
    ssg += reg(0, 0x05, 0x01)
    ssg += reg(0, 0x07, 0x38)
    ssg += reg(0, 0x08, 0x0F)
    ssg += reg(0, 0x09, 0x0F)
    ssg += reg(0, 0x0A, 0x0F)
    ssg += wait16(512)
    ssg += reg(0, 0x08, 0x00)
    ssg += reg(0, 0x09, 0x00)
    ssg += reg(0, 0x0A, 0x00)
    ssg += wait16(64)
    ssg += b"\x66"

    suppressed = bytearray()
    suppressed += data_block(0x82, 0x00100000, 0, b"\x12\x34\x56\x78")
    suppressed += data_block(0x83, 0x00080000, 0, b"\x9A\xBC\xDE\xF0")
    suppressed += fm_setup()
    suppressed += reg(1, 0x08, 0xC0)
    suppressed += reg(1, 0x10, 0x00)
    suppressed += reg(1, 0x00, 0x01)
    suppressed += reg(0, 0x10, 0x01)
    suppressed += reg(0, 0x11, 0xC0)
    suppressed += reg(0, 0x12, 0x00)
    suppressed += reg(0, 0x10, 0x80)
    suppressed += reg(0, 0x28, 0xF1)
    suppressed += wait16(256)
    suppressed += reg(0, 0x28, 0x01)
    suppressed += reg(1, 0x00, 0x81)
    suppressed += reg(0, 0x10, 0x01)
    suppressed += wait16(64)
    suppressed += b"\x66"

    accepted_cases = {
        "fm_only_raw.vgm": make_vgm(bytes(fm)),
        "fm_only_prepared.vgm": make_vgm(bytes(fm), prepared=True),
        "fm_loop.vgm": make_vgm(
            bytes(fm_loop), loop_command_offset=loop_offset
        ),
        "ssg_abc.vgm": make_vgm(bytes(ssg)),
        "suppressed_pcm.vgm": make_vgm(bytes(suppressed)),
        "b_compatible_fm.vgm": make_vgm(bytes(fm), variant_b=True),
    }

    manifest: dict[str, dict[str, object]] = {}
    for name, payload in accepted_cases.items():
        (output / name).write_bytes(payload)
        result, _ = parse_vgm(payload)
        manifest[name] = {
            "accepted": True,
            "classification": 1 if result.variant_b else 0,
            "reject": 0,
            **summary(result),
        }

    reject_cases = {
        "reject_b_key.vgm": (
            make_vgm(reg(0, 0x28, 0xF0) + b"\x66"),
            2, 3,
        ),
        "reject_b_setup.vgm": (
            make_vgm(reg(0, 0x30, 0x01) + b"\x66"),
            2, 3,
        ),
        "reject_dual.vgm": (
            make_vgm(bytes(fm), dual=True),
            3, 2,
        ),
        "reject_unknown.vgm": (
            make_vgm(reg(0, 0x20, 0x00) + b"\x66"),
            4, 4,
        ),
        "reject_opcode.vgm": (
            make_vgm(b"\x50\x90\x66"),
            5, 5,
        ),
    }
    for name, (payload, classification, reject) in reject_cases.items():
        (output / name).write_bytes(payload)
        manifest[name] = {
            "accepted": False,
            "classification": classification,
            "reject": reject,
            "original_size": len(payload),
            "physical_size": len(payload),
        }

    (output / "manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n"
    )
    print(f"STAGE_C_FIXTURES PASS count={len(manifest)} output={output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
