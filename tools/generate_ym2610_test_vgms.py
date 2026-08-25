#!/usr/bin/env python3
"""Generate small, redistributable YM2610 parser/audio fixtures.

Only the generator is committed.  Generated VGM files belong in a temporary
test directory and are intentionally ignored by the profile project.
"""

from __future__ import annotations

import argparse
import pathlib
import struct


def u32(value: int) -> bytes:
    return struct.pack("<I", value)


def write(port: int, address: int, value: int) -> bytes:
    return bytes((0x58 + port, address, value))


def wait(samples: int) -> bytes:
    if 1 <= samples <= 16:
        return bytes((0x6F + samples,))
    return bytes((0x61, samples & 0xFF, samples >> 8))


def block(block_type: int, logical_size: int, start: int, payload: bytes) -> bytes:
    body = u32(logical_size) + u32(start) + payload
    return b"\x67\x66" + bytes((block_type,)) + u32(len(body)) + body


def vgm(commands: bytes, *, variant_b: bool = False, dual: bool = False,
        loop_command_offset: int | None = None) -> bytes:
    header = bytearray(0x80)
    header[:4] = b"Vgm "
    header[8:12] = u32(0x151)
    header[0x34:0x38] = u32(0x80 - 0x34)
    flags = (0x80000000 if variant_b else 0) | (0x40000000 if dual else 0)
    header[0x4C:0x50] = u32(flags | 8_000_000)
    if loop_command_offset is not None:
        absolute = 0x80 + loop_command_offset
        header[0x1C:0x20] = u32(absolute - 0x1C)
    result = bytes(header) + commands
    result = result[:4] + u32(len(result) - 4) + result[8:]
    return result


def prepared(raw: bytes, directory: str, basename: str) -> bytes:
    directory_bytes = directory.encode("ascii")
    basename_bytes = basename.encode("ascii")
    if len(directory_bytes) > 32 or len(basename_bytes) > 48:
        raise ValueError("MVGMTTL name is too long")
    trailer = bytearray(128)
    trailer[:8] = b"MVGMTTL\0"
    trailer[8] = 1
    trailer[9] = (1 if directory_bytes else 0) | (2 if basename_bytes else 0)
    trailer[10] = len(directory_bytes)
    trailer[11] = len(basename_bytes)
    trailer[12:16] = b"\x80\x00\x00\x00"
    trailer[16:20] = u32(len(raw))
    trailer[32:32 + len(directory_bytes)] = directory_bytes
    trailer[64:64 + len(basename_bytes)] = basename_bytes
    return raw + trailer


def fm_sequence() -> bytes:
    # A quiet but valid four-operator tone on standard channel code 1.
    sequence = bytearray()
    for register, value in (
        (0x31, 0x01), (0x35, 0x01), (0x39, 0x01), (0x3D, 0x01),
        (0x41, 0x10), (0x45, 0x18), (0x49, 0x20), (0x4D, 0x08),
        (0x51, 0x1F), (0x55, 0x1F), (0x59, 0x1F), (0x5D, 0x1F),
        (0x61, 0x08), (0x65, 0x08), (0x69, 0x08), (0x6D, 0x08),
        (0x71, 0x04), (0x75, 0x04), (0x79, 0x04), (0x7D, 0x04),
        (0x81, 0x0F), (0x85, 0x0F), (0x89, 0x0F), (0x8D, 0x0F),
        (0xB1, 0xC7), (0xA5, 0x22), (0xA1, 0x69),
    ):
        sequence += write(0, register, value)
    sequence += write(0, 0x28, 0xF1) + wait(2205)
    sequence += write(0, 0x28, 0x01) + wait(128)
    return bytes(sequence)


def fm_channel_sequence(channel: int, *, frequency: int = 0x269) -> bytes:
    """Four-operator algorithm-7 tone on one physical FM channel (0..5)."""
    if not 0 <= channel < 6:
        raise ValueError("FM channel must be in range 0..5")
    port = 0 if channel < 3 else 1
    low = channel % 3
    selector = channel if channel < 3 else channel + 1
    sequence = bytearray()
    for operator_offset in (0, 4, 8, 12):
        for register_base, value in (
            (0x30, 0x01), (0x40, 0x18), (0x50, 0x1F),
            (0x60, 0x08), (0x70, 0x04), (0x80, 0x0F),
        ):
            sequence += write(port, register_base + operator_offset + low, value)
    sequence += write(port, 0xB0 + low, 0x07)
    sequence += write(port, 0xB4 + low, 0xC0)
    sequence += write(port, 0xA4 + low, (frequency >> 8) & 0x3F)
    sequence += write(port, 0xA0 + low, frequency & 0xFF)
    sequence += write(0, 0x28, 0xF0 | selector)
    sequence += wait(2205)
    sequence += write(0, 0x28, selector)
    sequence += wait(128)
    return bytes(sequence)


def six_fm_sequence() -> bytes:
    """Configure and key all six FM channels at distinct frequencies."""
    sequence = bytearray()
    selectors = (0, 1, 2, 4, 5, 6)
    for channel in range(6):
        port = 0 if channel < 3 else 1
        low = channel % 3
        frequency = 0x220 + channel * 0x29
        for operator_offset in (0, 4, 8, 12):
            for register_base, value in (
                (0x30, 0x01), (0x40, 0x20), (0x50, 0x1F),
                (0x60, 0x08), (0x70, 0x04), (0x80, 0x0F),
            ):
                sequence += write(port, register_base + operator_offset + low,
                                  value)
        sequence += write(port, 0xB0 + low, 0x07)
        sequence += write(port, 0xB4 + low, 0xC0)
        sequence += write(port, 0xA4 + low, (frequency >> 8) & 0x3F)
        sequence += write(port, 0xA0 + low, frequency & 0xFF)
    for selector in selectors:
        sequence += write(0, 0x28, 0xF0 | selector)
    sequence += wait(2205)
    for selector in selectors:
        sequence += write(0, 0x28, selector)
    sequence += wait(128)
    return bytes(sequence)


def ssg_sequence() -> bytes:
    sequence = bytearray()
    for register, value in (
        (0x00, 0x40), (0x01, 0x01),
        (0x02, 0x80), (0x03, 0x01),
        (0x04, 0xC0), (0x05, 0x01),
        (0x07, 0x38),
        (0x08, 0x0F), (0x09, 0x0C), (0x0A, 0x09),
    ):
        sequence += write(0, register, value)
    sequence += wait(2205)
    sequence += write(0, 0x08, 0) + write(0, 0x09, 0) + write(0, 0x0A, 0)
    sequence += wait(128)
    return bytes(sequence)


def adpcma_sequence() -> bytes:
    payload = bytes(((index * 73 + 41) & 0xFF) for index in range(0x400))
    sequence = bytearray(block(0x82, 0x100000, 0, payload))
    # Voice 0, start page 0, end page 1, centered, maximum channel level.
    for register, value in ((0x10, 0), (0x18, 0), (0x20, 3), (0x28, 0),
                            (0x01, 0x3F), (0x08, 0xDF), (0x00, 1)):
        sequence += write(1, register, value)
    sequence += wait(1024) + write(1, 0x00, 0x81) + wait(128)
    return bytes(sequence)


def adpcmb_sequence() -> bytes:
    payload = bytes(((index * 29 + 17) & 0xFF) for index in range(0x400))
    sequence = bytearray(block(0x83, 0x80000, 0, payload))
    for register, value in ((0x11, 0xC0), (0x12, 0), (0x13, 0),
                            (0x14, 3), (0x15, 0), (0x19, 0xFF),
                            (0x1A, 0x7F), (0x1B, 0xFF), (0x10, 0x80)):
        sequence += write(0, register, value)
    sequence += wait(1024) + write(0, 0x10, 0x01) + wait(128)
    return bytes(sequence)


def descriptor_sequence(block_type: int, count: int) -> bytes:
    """Non-overlapping 16-byte ROM regions for scanner-capacity tests."""
    logical_size = 0x100000 if block_type == 0x82 else 0x80000
    return b"".join(
        block(block_type, logical_size, index * 0x1000,
              bytes((index,)) * 16)
        for index in range(count)
    )


def fixtures() -> dict[str, bytes]:
    standard_all = vgm(fm_sequence() + ssg_sequence() + adpcma_sequence() +
                       adpcmb_sequence() + b"\x66")
    b_compatible = vgm(fm_sequence() + adpcma_sequence() +
                       adpcmb_sequence() + b"\x66", variant_b=True)
    b_key = vgm(write(0, 0x28, 0xF0) + b"\x66", variant_b=True)
    b_setup = vgm(write(0, 0x30, 0x01) + write(1, 0xB0, 0x07) + b"\x66",
                  variant_b=True)
    dual = vgm(fm_sequence() + b"\x66", dual=True)
    unknown_register = vgm(write(0, 0x20, 0x12) + b"\x66")
    unsupported_opcode = vgm(b"\x50\x00\x66")
    block_out_of_range = vgm(
        block(0x82, 0x100000, 0xFFFF0, bytes(range(32))) + b"\x66")
    ssg = vgm(ssg_sequence() + b"\x66")
    fm = vgm(fm_sequence() + b"\x66")
    adpcma = vgm(adpcma_sequence() + b"\x66")
    adpcmb = vgm(adpcmb_sequence() + b"\x66")
    payload_a = bytes(((index * 73 + 41) & 0xFF) for index in range(0x400))
    payload_b = bytes(((index * 29 + 17) & 0xFF) for index in range(0x400))
    simultaneous_commands = bytearray()
    simultaneous_commands += block(0x82, 0x100000, 0, payload_a)
    simultaneous_commands += block(0x83, 0x80000, 0, payload_b)
    for port, register, value in (
        (1, 0x10, 0), (1, 0x18, 0), (1, 0x20, 3), (1, 0x28, 0),
        (1, 0x01, 0x3F), (1, 0x08, 0xDF),
        (0, 0x11, 0xC0), (0, 0x12, 0), (0, 0x13, 0),
        (0, 0x14, 3), (0, 0x15, 0), (0, 0x19, 0xFF),
        (0, 0x1A, 0x7F), (0, 0x1B, 0xFF),
        (1, 0x00, 1), (0, 0x10, 0x80),
    ):
        simultaneous_commands += write(port, register, value)
    simultaneous_commands += wait(1024)
    simultaneous_commands += write(1, 0x00, 0x81) + write(0, 0x10, 1)
    simultaneous_commands += wait(128) + b"\x66"
    simultaneous = vgm(bytes(simultaneous_commands))
    loop_body = fm_sequence()
    looping = vgm(loop_body + b"\x66", loop_command_offset=0)
    lifecycle = vgm(wait(16) + b"\x66")
    ym2610b_fm = {
        f"ym2610b_fm_ch{channel + 1}.vgm": vgm(
            fm_channel_sequence(channel, frequency=0x220 + channel * 0x29) +
            b"\x66", variant_b=True)
        for channel in range(6)
    }
    ym2610b_six = vgm(six_fm_sequence() + b"\x66", variant_b=True)
    ym2610_unflagged_extra = vgm(fm_channel_sequence(0) + b"\x66")
    descriptor_a = {
        f"descriptor_a_{count}.vgm": vgm(
            descriptor_sequence(0x82, count) + b"\x66")
        for count in (0, 1, 8, 9, 10, 11, 64, 65)
    }
    descriptor_b = {
        f"descriptor_b_{count}.vgm": vgm(
            descriptor_sequence(0x83, count) + b"\x66")
        for count in (10, 11, 16, 17)
    }
    descriptor_mixed = vgm(descriptor_sequence(0x82, 10) +
                           descriptor_sequence(0x83, 3) + b"\x66")
    empty_b_512 = vgm(block(0x83, 0x80000, 0, b"") + b"\x66")
    empty_b_1m = vgm(block(0x83, 0x100000, 0, b"") + b"\x66")
    valid_b_512 = block(0x83, 0x80000, 0x100, bytes(range(16)))
    valid_b_1m = block(0x83, 0x100000, 0x200, bytes(range(16)))
    valid_b_8m = block(0x83, 0x800000, 0x300, bytes(range(16)))
    b_declared_too_small = block(
        0x83, 0x200, 0x1f8, bytes(range(16)))
    b_above_window = block(
        0x83, 0x100000, 0x90000, bytes(range(16)))
    b_arithmetic_overflow = block(
        0x83, 0xffffffff, 0xfffffff0, bytes(range(32)))
    malformed_b = vgm(b"\x67\x66\x83" + u32(7) + b"\0" * 7 + b"\x66")
    empty_b_with_a = vgm(
        block(0x82, 0x100000, 0, bytes(range(16))) +
        empty_b_1m[0x80:-1] +
        block(0x82, 0x100000, 0x100, bytes(range(16))) + b"\x66")
    empty_b_then_valid = vgm(empty_b_1m[0x80:-1] + valid_b_512 + b"\x66")
    empty_b_then_invalid = vgm(
        empty_b_1m[0x80:-1] + b_declared_too_small + b"\x66")
    b_out_of_range = vgm(block(0x83, 0x80000, 0x7fff0,
                                bytes(range(32))) + b"\x66")
    b_overlap = vgm(block(0x83, 0x80000, 0, bytes(range(16))) +
                    block(0x83, 0x80000, 8, bytes(range(16))) + b"\x66")
    wide_b = vgm(
        block(0x83, 0x800000, 0x07FFFE, bytes((0xB0, 0xB1, 0xB2, 0xB3))) +
        block(0x83, 0x800000, 0x0FFFFE, bytes((0xC0, 0xC1, 0xC2, 0xC3))) +
        block(0x83, 0x800000, 0x710300, bytes(range(0xD0, 0xE0))) +
        block(0x83, 0x800000, 0x717AF0, bytes(range(0xE0, 0xF0))) + b"\x66")
    b_exact_end = vgm(
        block(0x83, 0x720000, 0x71FFF0, bytes(range(16))) + b"\x66")
    b_declared_over_24 = vgm(
        block(0x83, 0x1000001, 0, bytes(range(16))) + b"\x66")
    b_space_overflow = vgm(
        block(0x83, 0x1000000, 0xFFFFF0, bytes(range(32))) + b"\x66")
    wide_a = vgm(
        block(0x82, 0x800000, 0x0FFFFE, bytes((0xA0, 0xA1, 0xA2, 0xA3))) +
        block(0x82, 0x800000, 0x168B00, bytes(range(0x10, 0x20))) +
        block(0x82, 0x800000, 0x16AFF0, bytes(range(0x20, 0x30))) +
        block(0x82, 0x800000, 0x170000, bytes(range(0x30, 0x40))) +
        block(0x82, 0x800000, 0x17EAF0, bytes(range(0x40, 0x50))) +
        block(0x82, 0x800000, 0x301AFF, b"\x5A") + b"\x66")
    a_exact_end = vgm(
        block(0x82, 0x180000, 0x17FFF0, bytes(range(16))) + b"\x66")
    a_last_address = vgm(
        block(0x82, 0x1000000, 0xFFFFFF, b"\xC7") + b"\x66")
    a_declared_overflow = vgm(
        block(0x82, 0x180000, 0x17FFF8, bytes(range(16))) + b"\x66")
    a_space_overflow = vgm(
        block(0x82, 0x1000000, 0xFFFFF0, bytes(range(32))) + b"\x66")
    a_declared_over_24 = vgm(
        block(0x82, 0x1000001, 0, bytes(range(16))) + b"\x66")
    a_zero_length = vgm(block(0x82, 0x800000, 0, b"") + b"\x66")
    result = {
        "standard_all_raw.vgm": standard_all,
        "standard_all_prepared.vgm": prepared(standard_all, "Synthetic", "YM2610 Standard"),
        "b_compatible.vgm": b_compatible,
        "b_only_keyon.vgm": b_key,
        "b_only_setup.vgm": b_setup,
        "dual_unsupported.vgm": dual,
        "unknown_register.vgm": unknown_register,
        "unsupported_opcode.vgm": unsupported_opcode,
        "block_out_of_range.vgm": block_out_of_range,
        "ssg_abc_raw.vgm": ssg,
        "ssg_abc_prepared.vgm": prepared(ssg, "Synthetic", "SSG A B C"),
        "adpcma.vgm": adpcma,
        "fm_standard.vgm": fm,
        "adpcmb.vgm": adpcmb,
        "adpcma_b_simultaneous.vgm": simultaneous,
        "loop.vgm": looping,
        "lifecycle.vgm": lifecycle,
        **ym2610b_fm,
        "ym2610b_six_fm.vgm": ym2610b_six,
        "ym2610_unflagged_extra_fm.vgm": ym2610_unflagged_extra,
        **descriptor_a,
        **descriptor_b,
        "descriptor_a10_b3.vgm": descriptor_mixed,
        "empty_b_512k.vgm": empty_b_512,
        "empty_b_1m.vgm": empty_b_1m,
        "valid_b_512k.vgm": vgm(valid_b_512 + b"\x66"),
        "valid_b_1m_low.vgm": vgm(valid_b_1m + b"\x66"),
        "valid_b_8m_low.vgm": vgm(valid_b_8m + b"\x66"),
        "b_declared_too_small.vgm": vgm(
            b_declared_too_small + b"\x66"),
        "b_above_window.vgm": vgm(b_above_window + b"\x66"),
        "b_arithmetic_overflow.vgm": vgm(
            b_arithmetic_overflow + b"\x66"),
        "malformed_b.vgm": malformed_b,
        "empty_b_with_a.vgm": empty_b_with_a,
        "empty_b_then_valid.vgm": empty_b_then_valid,
        "empty_b_then_invalid.vgm": empty_b_then_invalid,
        "b_out_of_range.vgm": b_out_of_range,
        "b_overlap.vgm": b_overlap,
        "wide_b_24bit.vgm": wide_b,
        "b_exact_end.vgm": b_exact_end,
        "b_declared_over_24.vgm": b_declared_over_24,
        "b_space_overflow.vgm": b_space_overflow,
        "wide_a_24bit.vgm": wide_a,
        "a_exact_end.vgm": a_exact_end,
        "a_last_address.vgm": a_last_address,
        "a_declared_overflow.vgm": a_declared_overflow,
        "a_space_overflow.vgm": a_space_overflow,
        "a_declared_over_24.vgm": a_declared_over_24,
        "a_zero_length.vgm": a_zero_length,
    }
    return result


def compressed_window(source: bytes, start_sample: int, end_sample: int,
                      *, preserve_loop: bool = False) -> bytes:
    """Build a temporary timing-compressed fixture from a local acceptance VGM.

    Data blocks and all preceding register setup writes are retained byte exact.
    Wait time outside the requested interval is removed.  The result is for
    local simulation only and must never be committed.
    """
    original_size = struct.unpack_from("<I", source, 4)[0] + 4
    data_offset = 0x34 + struct.unpack_from("<I", source, 0x34)[0]
    raw_loop = struct.unpack_from("<I", source, 0x1C)[0]
    loop_pc = 0 if raw_loop == 0 else 0x1C + raw_loop
    pc = data_offset
    sample = 0
    output = bytearray()
    new_loop_offset: int | None = None
    while pc < original_size:
        if pc == loop_pc:
            new_loop_offset = len(output)
        command_pc = pc
        opcode = source[pc]
        pc += 1
        if opcode in (0x58, 0x59):
            output += source[command_pc:pc + 2]
            pc += 2
        elif opcode == 0x67:
            size = struct.unpack_from("<I", source, pc + 2)[0] & 0x7FFFFFFF
            end = pc + 6 + size
            output += source[command_pc:end]
            pc = end
        elif opcode == 0x61:
            duration = source[pc] | (source[pc + 1] << 8)
            pc += 2
            overlap = max(0, min(sample + duration, end_sample) -
                          max(sample, start_sample))
            if overlap:
                output += wait(overlap)
            sample += duration
        elif opcode == 0x62:
            duration = 735
            overlap = max(0, min(sample + duration, end_sample) -
                          max(sample, start_sample))
            if overlap:
                output += wait(overlap)
            sample += duration
        elif opcode == 0x63:
            duration = 882
            overlap = max(0, min(sample + duration, end_sample) -
                          max(sample, start_sample))
            if overlap:
                output += wait(overlap)
            sample += duration
        elif 0x70 <= opcode <= 0x7F:
            duration = (opcode & 15) + 1
            overlap = max(0, min(sample + duration, end_sample) -
                          max(sample, start_sample))
            if overlap:
                output += wait(overlap)
            sample += duration
        elif opcode == 0x66:
            break
        else:
            raise ValueError(f"unsupported source opcode {opcode:02X} at {command_pc:X}")
        if not preserve_loop and sample >= end_sample:
            break
    output += b"\x66"
    loop = new_loop_offset if preserve_loop else None
    if preserve_loop and loop is None:
        raise ValueError("loop target was not retained")
    return vgm(bytes(output), variant_b=True, loop_command_offset=loop)


def loop_transition_window(source: bytes) -> bytes:
    """Create a bounded, Olga-derived end-to-loop transition fixture.

    The original type 82/83 payloads are retained byte exact.  Register writes
    and waits come from the final 3,000 samples followed by the first 9,000
    samples at the loop target.  The compact stream is ordered post-loop then
    pre-end so its 0x66 can jump backward to the real post-loop slice.  This
    exercises a natural parser loop plus audio after the jump without replaying
    81k unrelated writes in every Icarus determinism run.
    """
    original_size = struct.unpack_from("<I", source, 4)[0] + 4
    data_offset = 0x34 + struct.unpack_from("<I", source, 0x34)[0]
    raw_loop = struct.unpack_from("<I", source, 0x1C)[0]
    loop_pc = 0 if raw_loop == 0 else 0x1C + raw_loop
    pc = data_offset
    sample = 0
    loop_sample: int | None = None
    data_blocks = bytearray()
    while pc < original_size:
        if pc == loop_pc:
            loop_sample = sample
        command_pc = pc
        opcode = source[pc]
        pc += 1
        if opcode in (0x58, 0x59):
            pc += 2
        elif opcode == 0x67:
            size = struct.unpack_from("<I", source, pc + 2)[0] & 0x7FFFFFFF
            end = pc + 6 + size
            data_blocks += source[command_pc:end]
            pc = end
        elif opcode == 0x61:
            sample += source[pc] | (source[pc + 1] << 8)
            pc += 2
        elif opcode == 0x62:
            sample += 735
        elif opcode == 0x63:
            sample += 882
        elif 0x70 <= opcode <= 0x7F:
            sample += (opcode & 15) + 1
        elif opcode == 0x66:
            break
        else:
            raise ValueError(f"unsupported source opcode {opcode:02X} at {command_pc:X}")
    if loop_sample is None:
        raise ValueError("source has no command-boundary loop")

    def segment(start_sample: int, end_sample: int) -> bytes:
        pc = data_offset
        sample = 0
        output = bytearray()
        while pc < original_size:
            command_pc = pc
            opcode = source[pc]
            pc += 1
            if opcode in (0x58, 0x59):
                if start_sample <= sample < end_sample:
                    output += source[command_pc:pc + 2]
                pc += 2
            elif opcode == 0x67:
                size = struct.unpack_from("<I", source, pc + 2)[0] & 0x7FFFFFFF
                pc += 6 + size
            elif opcode in (0x61, 0x62, 0x63) or 0x70 <= opcode <= 0x7F:
                if opcode == 0x61:
                    duration = source[pc] | (source[pc + 1] << 8)
                    pc += 2
                elif opcode == 0x62:
                    duration = 735
                elif opcode == 0x63:
                    duration = 882
                else:
                    duration = (opcode & 15) + 1
                overlap = max(0, min(sample + duration, end_sample) -
                              max(sample, start_sample))
                if overlap:
                    output += wait(overlap)
                sample += duration
            elif opcode == 0x66:
                break
            else:
                raise ValueError(
                    f"unsupported source opcode {opcode:02X} at {command_pc:X}")
        return bytes(output)

    post_loop = segment(loop_sample, loop_sample + 9_000)
    pre_end = segment(max(0, sample - 3_000), sample)
    commands = bytes(data_blocks) + post_loop + pre_end + b"\x66"
    return vgm(commands, variant_b=True,
               loop_command_offset=len(data_blocks))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=pathlib.Path)
    parser.add_argument("--olga", type=pathlib.Path,
                        help="also create temporary bounded Olga windows")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    for name, data in fixtures().items():
        (args.output / name).write_bytes(data)
        print(f"{name} {len(data)}")
    if args.olga:
        source = args.olga.read_bytes()
        windows = {
            "olga_adpcmb_window.vgm": compressed_window(source, 4_000, 10_000),
            "olga_fm_window.vgm": compressed_window(source, 120_000, 126_000),
            "olga_adpcma_window.vgm": compressed_window(source, 120_500, 127_000),
            "olga_ab_window.vgm": compressed_window(source, 395_000, 402_000),
            "olga_loop_window.vgm": loop_transition_window(source),
        }
        for name, data in windows.items():
            (args.output / name).write_bytes(data)
            print(f"{name} {len(data)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
