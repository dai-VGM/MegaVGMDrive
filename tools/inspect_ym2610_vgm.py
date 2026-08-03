#!/usr/bin/env python3
"""Inspect and trace the YM2610 subset accepted by the MiSTer profile.

The implementation deliberately separates the raw VGM header variant from
actual register use.  A YM2610B-tagged file is accepted only when every write
has standard YM2610 semantics.  This utility is also the independent reference
used by the RTL regression; it never rewrites the input file.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import random
import struct
import sys
from dataclasses import asdict, dataclass
from typing import Iterable


MVGMTTL_SIZE = 128
MAX_VGM_SIZE = 1 << 23
YM2610_CLOCK_OFFSET = 0x4C


class VGMError(ValueError):
    """A deterministic, pre-playback rejection."""

    def __init__(self, code: str, pc: int, opcode: int, detail: str):
        super().__init__(f"{code} at 0x{pc:X}: {detail}")
        self.code = code
        self.pc = pc
        self.opcode = opcode
        self.detail = detail


@dataclass(frozen=True)
class RegisterWrite:
    pc: int
    sample: int
    opcode: int
    port: int
    address: int
    data: int
    semantic: str
    target: str


@dataclass(frozen=True)
class Descriptor:
    space: str
    command_pc: int
    block_type: int
    file_start: int
    logical_start: int
    length: int
    logical_rom_size: int

    @property
    def file_end(self) -> int:
        return self.file_start + self.length

    @property
    def logical_end(self) -> int:
        return self.logical_start + self.length


@dataclass
class Inspection:
    path: str
    sha256: str
    physical_size: int
    original_size: int
    prepared: bool
    directory: str
    basename: str
    version: int
    data_offset: int
    clock_field: int
    clock: int
    dual: bool
    variant_bit: bool
    raw_variant: str
    classification: str
    reject_code: str | None
    first_offending_pc: int | None
    first_offending_opcode: int | None
    first_offending_port: int | None
    first_offending_address: int | None
    first_offending_data: int | None
    first_offending_sample: int | None
    first_offending_target: str | None
    first_offending_reason: str | None
    command_count: int
    command_histogram: dict[str, int]
    total_writes: int
    port0_writes: int
    port1_writes: int
    b_only_writes: int
    unknown_writes: int
    unsupported_writes: int
    total_samples: int
    loop_target: int
    loop_samples: int | None
    end_pc: int
    descriptors: list[Descriptor]
    writes: list[RegisterWrite]


def le32(data: bytes, offset: int) -> int:
    if offset < 0 or offset + 4 > len(data):
        raise VGMError("TRUNCATED", offset, 0, "32-bit field is outside the file")
    return struct.unpack_from("<I", data, offset)[0]


def _prepared_metadata(data: bytes) -> tuple[int, bool, str, str]:
    if len(data) < MVGMTTL_SIZE:
        return len(data), False, "", ""
    trailer = data[-MVGMTTL_SIZE:]
    if trailer[:8] != b"MVGMTTL\0" or trailer[8] != 1:
        return len(data), False, "", ""
    flags = trailer[9]
    directory_length = trailer[10]
    basename_length = trailer[11]
    original_size = le32(trailer, 16)
    valid = (
        flags & 0xFC == 0
        and directory_length <= 32
        and basename_length <= 48
        and bool(flags & 1) == bool(directory_length)
        and bool(flags & 2) == bool(basename_length)
        and trailer[12:16] == b"\x80\x00\x00\x00"
        and trailer[20:32] == bytes(12)
        and all(0x20 <= byte <= 0x7E for byte in trailer[32:32 + directory_length])
        and not any(trailer[32 + directory_length:64])
        and all(0x20 <= byte <= 0x7E for byte in trailer[64:64 + basename_length])
        and not any(trailer[64 + basename_length:])
        and original_size + MVGMTTL_SIZE == len(data)
    )
    if not valid:
        return len(data), False, "", ""
    directory = trailer[32:32 + directory_length].decode("ascii")
    basename = trailer[64:64 + basename_length].decode("ascii")
    return original_size, True, directory, basename


def classify_write(port: int, address: int, value: int) -> tuple[str, str, str | None]:
    """Return (semantic, target, rejection-kind).

    The address decode mirrors the pinned ``ym2610_hw0_jt12_mmr``.  A
    rejection kind of ``B_ONLY`` is distinct from an unknown/reserved write.
    """
    if port not in (0, 1):
        return "unknown", "invalid-port", "UNKNOWN"

    if port == 0:
        if address <= 0x0F:
            return "ssg", f"SSG register {address:X}", None
        if address in (0x10, 0x11, 0x12, 0x13, 0x14, 0x15,
                       0x19, 0x1A, 0x1B, 0x1C):
            return "adpcm-b", f"ADPCM-B register {address:02X}", None
        if address in (0x21, 0x22, 0x24, 0x25, 0x26, 0x27,
                       0x29, 0x2D, 0x2E, 0x2F):
            return "global", f"global register {address:02X}", None
        if address == 0x28:
            selector = value & 7
            if selector in (1, 2, 5, 6):
                return "fm-key", f"standard FM channel code {selector}", None
            if selector in (0, 4):
                return "fm-key", f"YM2610B extra FM channel code {selector}", "B_ONLY"
            return "fm-key", f"reserved FM channel code {selector}", "UNKNOWN"
    else:
        if address in (0x00, 0x01, 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D,
                       0x10, 0x11, 0x12, 0x13, 0x14, 0x15,
                       0x18, 0x19, 0x1A, 0x1B, 0x1C, 0x1D,
                       0x20, 0x21, 0x22, 0x23, 0x24, 0x25,
                       0x28, 0x29, 0x2A, 0x2B, 0x2C, 0x2D):
            return "adpcm-a", f"ADPCM-A register {address:02X}", None

    if 0x30 <= address <= 0x9F:
        selector = address & 3
        semantic = {
            0x3: "fm-operator-dt-mul", 0x4: "fm-operator-tl",
            0x5: "fm-operator-ks-ar", 0x6: "fm-operator-am-dr",
            0x7: "fm-operator-sr", 0x8: "fm-operator-sl-rr",
            0x9: "fm-operator-ssg-eg",
        }[address >> 4]
        if selector in (1, 2):
            channel = selector + (3 if port else 0)
            return semantic, f"standard FM channel {channel}", None
        if selector == 0:
            channel = 3 if port else 0
            return semantic, f"YM2610B extra FM channel {channel}", "B_ONLY"
        return semantic, "reserved FM channel selector 3", "UNKNOWN"

    if address in (0xA0, 0xA1, 0xA2, 0xA4, 0xA5, 0xA6,
                   0xB0, 0xB1, 0xB2, 0xB4, 0xB5, 0xB6):
        selector = address & 3
        semantic = "fm-frequency" if (address & 0xF0) == 0xA0 else "fm-channel-control"
        if selector in (1, 2):
            channel = selector + (3 if port else 0)
            return semantic, f"standard FM channel {channel}", None
        channel = 3 if port else 0
        return semantic, f"YM2610B extra FM channel {channel}", "B_ONLY"

    # CH3 special-frequency registers are global to the first FM bank.
    if port == 0 and address in (0xA8, 0xA9, 0xAA, 0xAC, 0xAD, 0xAE):
        return "fm-ch3-special-frequency", "standard FM channel 2 operators", None

    return "unknown", f"reserved register {port}:{address:02X}", "UNKNOWN"


def _trace(data: bytes, source: pathlib.Path) -> Inspection:
    physical_size = len(data)
    original_size, prepared, directory, basename = _prepared_metadata(data)
    if physical_size > MAX_VGM_SIZE:
        raise VGMError("FILE_TOO_LARGE", 0, 0, "physical file exceeds 8 MiB")
    if original_size < 0x40 or data[:4] != b"Vgm ":
        raise VGMError("BAD_HEADER", 0, 0, "missing Vgm magic")
    eof = le32(data, 4) + 4
    if eof != original_size:
        raise VGMError("BAD_EOF", 4, 0, f"header EOF {eof} != original size {original_size}")
    version = le32(data, 8)
    data_offset = 0x40 if version < 0x150 else 0x34 + le32(data, 0x34)
    if not (0x40 <= data_offset < original_size):
        raise VGMError("BAD_DATA_OFFSET", 0x34, 0, f"data offset 0x{data_offset:X}")
    clock_field = le32(data, YM2610_CLOCK_OFFSET)
    clock = clock_field & 0x3FFFFFFF
    dual = bool(clock_field & 0x40000000)
    variant_bit = bool(clock_field & 0x80000000)
    raw_variant = "YM2610B" if variant_bit else "YM2610"
    loop_offset = le32(data, 0x1C)
    loop_target = 0 if loop_offset == 0 else 0x1C + loop_offset

    pc = data_offset
    sample = 0
    commands = 0
    histogram: dict[str, int] = {}
    writes: list[RegisterWrite] = []
    descriptors: list[Descriptor] = []
    port_counts = [0, 0]
    b_only = 0
    unknown = 0
    unsupported = 0
    first: RegisterWrite | None = None
    first_reason: str | None = None
    loop_samples: int | None = None
    end_pc = -1

    while pc < original_size:
        if pc == loop_target:
            loop_samples = sample
        command_pc = pc
        opcode = data[pc]
        pc += 1
        commands += 1
        histogram[f"{opcode:02x}"] = histogram.get(f"{opcode:02x}", 0) + 1
        if opcode in (0x58, 0x59):
            if pc + 2 > original_size:
                raise VGMError("TRUNCATED", command_pc, opcode, "register write")
            port = opcode - 0x58
            address, value = data[pc], data[pc + 1]
            pc += 2
            semantic, target, rejected = classify_write(port, address, value)
            write = RegisterWrite(command_pc, sample, opcode, port, address,
                                  value, semantic, target)
            writes.append(write)
            port_counts[port] += 1
            if rejected == "B_ONLY":
                b_only += 1
            elif rejected:
                unknown += 1
            if rejected and first is None:
                first = write
                first_reason = rejected
        elif opcode == 0x61:
            if pc + 2 > original_size:
                raise VGMError("TRUNCATED", command_pc, opcode, "wait")
            sample += data[pc] | (data[pc + 1] << 8)
            pc += 2
        elif opcode == 0x62:
            sample += 735
        elif opcode == 0x63:
            sample += 882
        elif 0x70 <= opcode <= 0x7F:
            sample += (opcode & 0x0F) + 1
        elif opcode == 0x67:
            if pc + 6 > original_size or data[pc] != 0x66:
                raise VGMError("BAD_BLOCK", command_pc, opcode, "invalid data-block header")
            block_type = data[pc + 1]
            block_size = le32(data, pc + 2) & 0x7FFFFFFF
            payload = pc + 6
            block_end = payload + block_size
            if block_end > original_size:
                raise VGMError("BAD_BLOCK", command_pc, opcode, "payload exceeds VGM")
            if block_type not in (0x82, 0x83) or block_size < 8:
                raise VGMError("UNSUPPORTED_BLOCK", command_pc, opcode,
                               f"type {block_type:02X}, size {block_size}")
            logical_rom_size = le32(data, payload)
            logical_start = le32(data, payload + 4)
            length = block_size - 8
            limit = 0x100000 if block_type == 0x82 else 0x80000
            if logical_rom_size != limit or logical_start + length > limit:
                raise VGMError("BLOCK_RANGE", command_pc, opcode,
                               f"type {block_type:02X} logical range")
            new = Descriptor("A" if block_type == 0x82 else "B", command_pc,
                             block_type, payload + 8, logical_start, length,
                             logical_rom_size)
            for old in descriptors:
                if old.space == new.space and not (
                    new.logical_end <= old.logical_start or
                    new.logical_start >= old.logical_end
                ):
                    raise VGMError("BLOCK_OVERLAP", command_pc, opcode,
                                   f"{new.space} logical range overlaps 0x{old.command_pc:X}")
            descriptors.append(new)
            pc = block_end
        elif opcode == 0x66:
            end_pc = command_pc
            break
        else:
            unsupported += 1
            raise VGMError("UNSUPPORTED_OPCODE", command_pc, opcode,
                           "command length is intentionally not guessed")

    if end_pc < 0:
        raise VGMError("NO_END", pc, 0, "no 0x66 before EOF")
    if loop_target and loop_samples is None:
        raise VGMError("BAD_LOOP", 0x1C, 0, "loop target is not a command boundary")

    if dual:
        classification = "VARIANT_DUAL_UNSUPPORTED"
        reject_code = "DUAL_UNSUPPORTED"
    elif first is not None:
        classification = "VARIANT_B_REQUIRED" if variant_bit else "VARIANT_STANDARD"
        reject_code = "B_REQUIRED" if first_reason == "B_ONLY" else "UNKNOWN_REGISTER"
    elif variant_bit:
        classification = "VARIANT_B_COMPATIBLE_SUBSET"
        reject_code = None
    else:
        classification = "VARIANT_STANDARD"
        reject_code = None

    return Inspection(
        str(source), hashlib.sha256(data).hexdigest(), physical_size,
        original_size, prepared, directory, basename, version, data_offset,
        clock_field, clock,
        dual, variant_bit, raw_variant, classification, reject_code,
        None if first is None else first.pc,
        None if first is None else first.opcode,
        None if first is None else first.port,
        None if first is None else first.address,
        None if first is None else first.data,
        None if first is None else first.sample,
        None if first is None else first.target,
        first_reason,
        commands, histogram, len(writes), port_counts[0], port_counts[1],
        b_only, unknown, unsupported, sample, loop_target,
        None if loop_samples is None else sample - loop_samples,
        end_pc, descriptors, writes,
    )


def inspect(path: pathlib.Path) -> Inspection:
    return _trace(path.read_bytes(), path)


def map_rom(descriptors: Iterable[Descriptor], space: str, address: int) -> int | None:
    for descriptor in descriptors:
        if (descriptor.space == space and
                descriptor.logical_start <= address < descriptor.logical_end):
            return descriptor.file_start + address - descriptor.logical_start
    return None


def _summary(inspection: Inspection, include_writes: bool) -> dict[str, object]:
    result = asdict(inspection)
    result["trace_hash"] = trace_hash(inspection.writes)
    result["first_256_trace_hash"] = trace_hash(inspection.writes[:256])
    if not include_writes:
        result.pop("writes")
    return result


def trace_hash(writes: Iterable[RegisterWrite]) -> str:
    value = 0xCBF29CE484222325
    for write_event in writes:
        packed = struct.pack("<IIBBBB", write_event.pc, write_event.sample,
                             write_event.opcode, write_event.port,
                             write_event.address, write_event.data)
        for byte in packed:
            value ^= byte
            value = (value * 0x100000001B3) & 0xFFFFFFFFFFFFFFFF
    return f"{value:016x}"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("vgm", type=pathlib.Path)
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--trace", action="store_true",
                        help="include every classified register write")
    parser.add_argument("--rom-samples", type=int, default=0,
                        help="emit deterministic mapped-byte samples per space")
    args = parser.parse_args(argv)
    try:
        result = inspect(args.vgm)
    except VGMError as error:
        print(json.dumps({"error": error.code, "pc": error.pc,
                          "opcode": error.opcode, "detail": error.detail}, indent=2))
        return 2
    output = _summary(result, args.trace)
    if args.rom_samples:
        rng = random.Random(0x2610)
        payload = args.vgm.read_bytes()
        samples: dict[str, list[dict[str, int]]] = {"A": [], "B": []}
        for space, limit in (("A", 0x100000), ("B", 0x80000)):
            candidates = [rng.randrange(limit) for _ in range(args.rom_samples * 8)]
            for address in candidates:
                mapped = map_rom(result.descriptors, space, address)
                if mapped is not None:
                    samples[space].append({"logical": address, "file": mapped,
                                           "value": payload[mapped]})
                    if len(samples[space]) == args.rom_samples:
                        break
        output["rom_samples"] = samples
    if args.json:
        print(json.dumps(output, indent=2, sort_keys=True))
    else:
        print(f"{result.classification} writes={result.total_writes} "
              f"samples={result.total_samples} descriptors={len(result.descriptors)}")
        if result.reject_code:
            location = ("header" if result.first_offending_pc is None else
                        f"0x{result.first_offending_pc:X}")
            print(f"reject={result.reject_code} pc={location}")
    return 0 if result.reject_code is None else 3


if __name__ == "__main__":
    sys.exit(main())
