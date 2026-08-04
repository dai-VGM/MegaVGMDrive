#!/usr/bin/env python3
"""Independent Stage C VGM parser and YM2610 forwarding reference."""

from __future__ import annotations

import argparse
from dataclasses import asdict, dataclass
import hashlib
import json
from pathlib import Path
import struct
from typing import BinaryIO


FNV_OFFSET = 0xCBF29CE484222325
FNV_PRIME = 0x00000100000001B3

SEM_NONE = 0
SEM_SSG = 1
SEM_GLOBAL = 2
SEM_ADPCMA = 3
SEM_ADPCMB = 4
SEM_FM_OP = 5
SEM_FM_FREQ = 6
SEM_FM_CTRL = 7
SEM_FM_KEY = 8
SEM_FM_CH3 = 9

SEMANTIC_NAMES = {
    SEM_NONE: "NONE",
    SEM_SSG: "SSG",
    SEM_GLOBAL: "GLOBAL",
    SEM_ADPCMA: "ADPCM_A",
    SEM_ADPCMB: "ADPCM_B",
    SEM_FM_OP: "FM_OPERATOR",
    SEM_FM_FREQ: "FM_FREQUENCY",
    SEM_FM_CTRL: "FM_CONTROL",
    SEM_FM_KEY: "FM_KEY",
    SEM_FM_CH3: "FM_CH3",
}


class ReferenceError(RuntimeError):
    pass


@dataclass(frozen=True)
class Classification:
    accepted: bool
    b_only: bool
    unknown: bool
    semantic: int
    target: int


@dataclass(frozen=True)
class WriteEvent:
    command_pc: int
    sample: int
    port: int
    address: int
    data: int
    semantic: int
    semantic_name: str
    forwarded: bool
    next_pc: int


@dataclass
class ParseResult:
    physical_size: int
    original_size: int
    prepared: bool
    version: int
    clock_field: int
    clock: int
    variant_b: bool
    dual: bool
    data_offset: int
    loop_target: int
    loop_boundary_sample: int
    loop_samples: int
    end_pc: int
    total_samples: int
    command_count: int
    total_writes: int
    port0_writes: int
    port1_writes: int
    forwarded_fm_global: int
    forwarded_ssg: int
    suppressed_adpcma: int
    suppressed_adpcmb: int
    b_only_writes: int
    unknown_writes: int
    data_blocks: int
    descriptor_a: int
    descriptor_b: int
    fm_key_on: int
    key_on_channel_1: int
    key_on_channel_2: int
    key_on_channel_5: int
    key_on_channel_6: int
    b_only_key_on: int
    ssg_writes: int
    adpcma_key_on_voices: int
    adpcma_key_off_voices: int
    adpcmb_start: int
    adpcmb_reset: int
    first_adpcmb_control_sample: int
    first_fm_key_on_sample: int
    first_adpcma_control_sample: int
    trace_hash: str
    first256_trace_hash: str
    event_metadata_sha256: str


def le32(data: bytes, offset: int) -> int:
    if offset < 0 or offset + 4 > len(data):
        raise ReferenceError(f"32-bit read outside file at 0x{offset:X}")
    return struct.unpack_from("<I", data, offset)[0]


def popcount6(value: int) -> int:
    return (value & 0x3F).bit_count()


def classify_write(port: int, address: int, data: int) -> Classification:
    accepted = False
    b_only = False
    unknown = False
    semantic = SEM_NONE
    target = 7
    selector = address & 3

    if port == 0 and address <= 0x0F:
        accepted = True
        semantic = SEM_SSG
        target = (address >> 1) & 1
    elif port == 0 and address in {
        0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x19, 0x1A, 0x1B, 0x1C
    }:
        accepted = True
        semantic = SEM_ADPCMB
        target = 0
    elif port == 1 and (
        address in {0x00, 0x01}
        or 0x08 <= address <= 0x0D
        or 0x10 <= address <= 0x15
        or 0x18 <= address <= 0x1D
        or 0x20 <= address <= 0x25
        or 0x28 <= address <= 0x2D
    ):
        accepted = True
        semantic = SEM_ADPCMA
        target = address & 7
    elif port == 0 and (
        address in {0x21, 0x22, 0x24, 0x25, 0x26, 0x27, 0x29, 0x2D, 0x2E, 0x2F}
    ):
        accepted = True
        semantic = SEM_GLOBAL
        target = 0
    elif port == 0 and address == 0x28:
        semantic = SEM_FM_KEY
        selector = data & 7
        target = selector
        if selector in {1, 2, 5, 6}:
            accepted = True
        elif selector in {0, 4}:
            b_only = True
        else:
            unknown = True
    elif 0x30 <= address <= 0x9F:
        semantic = SEM_FM_OP
        target = (port << 2) | selector
        if selector in {1, 2}:
            accepted = True
        elif selector == 0:
            b_only = True
        else:
            unknown = True
    elif address in {
        0xA0, 0xA1, 0xA2, 0xA4, 0xA5, 0xA6,
        0xB0, 0xB1, 0xB2, 0xB4, 0xB5, 0xB6,
    }:
        semantic = SEM_FM_FREQ if address >> 4 == 0xA else SEM_FM_CTRL
        target = (port << 2) | selector
        if selector in {1, 2}:
            accepted = True
        else:
            b_only = True
    elif port == 0 and address in {0xA8, 0xA9, 0xAA, 0xAC, 0xAD, 0xAE}:
        accepted = True
        semantic = SEM_FM_CH3
        target = 2
    else:
        unknown = True

    return Classification(accepted, b_only, unknown, semantic, target)


def fnv_byte(value: int, byte: int) -> int:
    return ((value ^ byte) * FNV_PRIME) & 0xFFFFFFFFFFFFFFFF


def hash_event(value: int, event: WriteEvent) -> int:
    for number in (event.command_pc, event.sample):
        for shift in (0, 8, 16, 24):
            value = fnv_byte(value, (number >> shift) & 0xFF)
    value = fnv_byte(value, 0x58 | event.port)
    value = fnv_byte(value, event.port)
    value = fnv_byte(value, event.address)
    value = fnv_byte(value, event.data)
    return value


def original_body(data: bytes) -> tuple[int, bool]:
    if len(data) >= 128:
        trailer = data[-128:]
        if trailer[:8] == b"MVGMTTL\x00" and trailer[8] == 1:
            original = le32(trailer, 16)
            if original + 128 == len(data):
                return original, True
    return len(data), False


def event_metadata_digest(events: list[WriteEvent]) -> str:
    digest = hashlib.sha256()
    for event in events:
        digest.update(
            (
                f"{event.command_pc:08x} {event.sample} {event.port} "
                f"{event.address:02x} {event.data:02x} {event.semantic} "
                f"{int(event.forwarded)} {event.next_pc:08x}\n"
            ).encode()
        )
    return digest.hexdigest()


def parse_vgm(data: bytes) -> tuple[ParseResult, list[WriteEvent]]:
    physical_size = len(data)
    original_size, prepared = original_body(data)
    body = data[:original_size]
    if original_size < 0x80 or body[:4] != b"Vgm ":
        raise ReferenceError("invalid VGM header")
    if le32(body, 4) + 4 != original_size:
        raise ReferenceError("EOF offset does not match original body")

    version = le32(body, 8)
    clock_field = le32(body, 0x4C)
    clock = clock_field & 0x3FFFFFFF
    variant_b = bool(clock_field & 0x80000000)
    dual = bool(clock_field & 0x40000000)
    data_offset = 0x40 if version < 0x150 else 0x34 + le32(body, 0x34)
    loop_relative = le32(body, 0x1C)
    loop_target = 0 if loop_relative == 0 else 0x1C + loop_relative

    if clock == 0 or dual:
        raise ReferenceError("clock zero or dual chip")
    if not 0x40 <= data_offset < original_size:
        raise ReferenceError("invalid data offset")
    if loop_target and not data_offset <= loop_target < original_size:
        raise ReferenceError("invalid loop target")

    pc = data_offset
    sample = 0
    loop_boundary_sample = -1
    command_count = 0
    port_writes = [0, 0]
    forwarded_fm_global = 0
    forwarded_ssg = 0
    suppressed_adpcma = 0
    suppressed_adpcmb = 0
    b_only_writes = 0
    unknown_writes = 0
    data_blocks = 0
    descriptor_a = 0
    descriptor_b = 0
    fm_key_on = 0
    key_channels = {1: 0, 2: 0, 5: 0, 6: 0}
    b_only_key_on = 0
    ssg_writes = 0
    adpcma_on = 0
    adpcma_off = 0
    adpcmb_start = 0
    adpcmb_reset = 0
    first_adpcmb = -1
    first_fm = -1
    first_adpcma = -1
    events: list[WriteEvent] = []
    trace_hash = FNV_OFFSET
    first256_hash = FNV_OFFSET

    while True:
        if not 0 <= pc < original_size:
            raise ReferenceError(f"PC outside body: 0x{pc:X}")
        if pc == loop_target and loop_target:
            loop_boundary_sample = sample
        command_pc = pc
        opcode = body[pc]
        pc += 1
        command_count += 1

        if opcode in (0x58, 0x59):
            if pc + 2 > original_size:
                raise ReferenceError("truncated register write")
            port = opcode & 1
            address = body[pc]
            value = body[pc + 1]
            pc += 2
            classification = classify_write(port, address, value)
            if classification.b_only:
                b_only_writes += 1
            if classification.unknown:
                unknown_writes += 1
            forwarded = (
                classification.accepted
                and classification.semantic not in {SEM_ADPCMA, SEM_ADPCMB}
            )
            event = WriteEvent(
                command_pc,
                sample,
                port,
                address,
                value,
                classification.semantic,
                SEMANTIC_NAMES[classification.semantic],
                forwarded,
                pc,
            )
            events.append(event)
            port_writes[port] += 1
            trace_hash = hash_event(trace_hash, event)
            if len(events) <= 256:
                first256_hash = trace_hash

            if classification.semantic == SEM_SSG:
                ssg_writes += 1
                forwarded_ssg += 1
            elif classification.semantic == SEM_ADPCMA:
                suppressed_adpcma += 1
                if port == 1 and address == 0x00:
                    if first_adpcma < 0 and not (value & 0x80) and (value & 0x3F):
                        first_adpcma = sample
                    if value & 0x80:
                        adpcma_off += popcount6(value)
                    else:
                        adpcma_on += popcount6(value)
            elif classification.semantic == SEM_ADPCMB:
                suppressed_adpcmb += 1
                if port == 0 and address == 0x10:
                    if first_adpcmb < 0 and value & 0x80:
                        first_adpcmb = sample
                    if value & 0x80:
                        adpcmb_start += 1
                    if value & 0x01:
                        adpcmb_reset += 1
            elif classification.accepted:
                forwarded_fm_global += 1

            if port == 0 and address == 0x28 and value & 0xF0:
                channel = value & 7
                if channel in key_channels:
                    fm_key_on += 1
                    key_channels[channel] += 1
                    if first_fm < 0:
                        first_fm = sample
                elif channel in {0, 4}:
                    b_only_key_on += 1

        elif opcode == 0x61:
            if pc + 2 > original_size:
                raise ReferenceError("truncated 0x61 wait")
            sample += body[pc] | body[pc + 1] << 8
            pc += 2
        elif opcode == 0x62:
            sample += 735
        elif opcode == 0x63:
            sample += 882
        elif opcode == 0x66:
            end_pc = command_pc
            break
        elif opcode == 0x67:
            if pc + 6 > original_size or body[pc] != 0x66:
                raise ReferenceError("malformed data block")
            block_type = body[pc + 1]
            block_size = le32(body, pc + 2)
            if block_size & 0x80000000 or block_type not in {0x82, 0x83}:
                raise ReferenceError("unsupported data block")
            next_pc = command_pc + 7 + block_size
            if block_size <= 8 or next_pc > original_size:
                raise ReferenceError("data block range")
            data_blocks += 1
            descriptor_a += int(block_type == 0x82)
            descriptor_b += int(block_type == 0x83)
            pc = next_pc
        elif 0x70 <= opcode <= 0x7F:
            sample += (opcode & 0x0F) + 1
        else:
            raise ReferenceError(
                f"unsupported opcode 0x{opcode:02X} at 0x{command_pc:X}"
            )

    loop_samples = (
        sample - loop_boundary_sample if loop_boundary_sample >= 0 else 0
    )
    result = ParseResult(
        physical_size=physical_size,
        original_size=original_size,
        prepared=prepared,
        version=version,
        clock_field=clock_field,
        clock=clock,
        variant_b=variant_b,
        dual=dual,
        data_offset=data_offset,
        loop_target=loop_target,
        loop_boundary_sample=loop_boundary_sample,
        loop_samples=loop_samples,
        end_pc=end_pc,
        total_samples=sample,
        command_count=command_count,
        total_writes=len(events),
        port0_writes=port_writes[0],
        port1_writes=port_writes[1],
        forwarded_fm_global=forwarded_fm_global,
        forwarded_ssg=forwarded_ssg,
        suppressed_adpcma=suppressed_adpcma,
        suppressed_adpcmb=suppressed_adpcmb,
        b_only_writes=b_only_writes,
        unknown_writes=unknown_writes,
        data_blocks=data_blocks,
        descriptor_a=descriptor_a,
        descriptor_b=descriptor_b,
        fm_key_on=fm_key_on,
        key_on_channel_1=key_channels[1],
        key_on_channel_2=key_channels[2],
        key_on_channel_5=key_channels[5],
        key_on_channel_6=key_channels[6],
        b_only_key_on=b_only_key_on,
        ssg_writes=ssg_writes,
        adpcma_key_on_voices=adpcma_on,
        adpcma_key_off_voices=adpcma_off,
        adpcmb_start=adpcmb_start,
        adpcmb_reset=adpcmb_reset,
        first_adpcmb_control_sample=first_adpcmb,
        first_fm_key_on_sample=first_fm,
        first_adpcma_control_sample=first_adpcma,
        trace_hash=f"{trace_hash:016x}",
        first256_trace_hash=f"{first256_hash:016x}",
        event_metadata_sha256=event_metadata_digest(events),
    )
    return result, events


def write_trace(handle: BinaryIO, events: list[WriteEvent]) -> None:
    for event in events:
        handle.write(
            (
                f"{event.command_pc:08x} {event.sample} {event.port} "
                f"{event.address:02x} {event.data:02x} {event.semantic} "
                f"{int(event.forwarded)} {event.next_pc:08x}\n"
            ).encode()
        )


def check_olga(result: ParseResult) -> None:
    expected = {
        "physical_size": 934025,
        "original_size": 933897,
        "clock_field": 0x807A1200,
        "clock": 8_000_000,
        "data_offset": 0x80,
        "loop_target": 0xB6223,
        "loop_samples": 4_025_862,
        "end_pc": 0xE3F24,
        "total_samples": 8_372_668,
        "command_count": 171_869,
        "total_writes": 81_272,
        "port0_writes": 38_246,
        "port1_writes": 43_026,
        "data_blocks": 7,
        "descriptor_a": 4,
        "descriptor_b": 3,
        "fm_key_on": 2_480,
        "key_on_channel_1": 879,
        "key_on_channel_2": 632,
        "key_on_channel_5": 453,
        "key_on_channel_6": 516,
        "b_only_key_on": 0,
        "ssg_writes": 0,
        "adpcma_key_on_voices": 793,
        "adpcma_key_off_voices": 850,
        "adpcmb_start": 23,
        "adpcmb_reset": 27,
        "first_adpcmb_control_sample": 4625,
        "first_fm_key_on_sample": 120851,
        "first_adpcma_control_sample": 121270,
        "trace_hash": "7c3088bd1d4eea6f",
        "first256_trace_hash": "155cbbc09e7b636b",
    }
    for name, value in expected.items():
        actual = getattr(result, name)
        if actual != value:
            raise ReferenceError(
                f"Olga mismatch {name}: expected={value!r} actual={actual!r}"
            )
    if result.b_only_writes != 0 or result.unknown_writes != 0:
        raise ReferenceError("Olga contains impossible B-only/unknown writes")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("vgm", type=Path)
    parser.add_argument("--check-olga", action="store_true")
    parser.add_argument("--json", type=Path)
    parser.add_argument("--trace", type=Path)
    parser.add_argument("--memh", type=Path)
    args = parser.parse_args()

    data = args.vgm.read_bytes()
    result, events = parse_vgm(data)
    if args.check_olga:
        check_olga(result)
    if args.json:
        args.json.write_text(json.dumps(asdict(result), indent=2) + "\n")
    if args.trace:
        with args.trace.open("wb") as handle:
            write_trace(handle, events)
    if args.memh:
        original_size, _ = original_body(data)
        args.memh.write_text(
            "".join(f"{byte:02x}\n" for byte in data[:original_size])
        )

    print(json.dumps(asdict(result), sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
