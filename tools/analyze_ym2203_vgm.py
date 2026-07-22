#!/usr/bin/env python3
"""Report YM2203/SSG/SegaPCM use and activity windows in a VGM file.

The activity windows are register-state estimates used to choose production
simulation intervals.  They are not an audio-model replacement: FM release
tails and SegaPCM sample contents can only be measured in RTL simulation.
"""

from __future__ import annotations

import argparse
import gzip
import pathlib
import struct
from collections import Counter


SAMPLE_RATE = 44_100


def u16le(data: bytes, offset: int) -> int:
    return struct.unpack_from("<H", data, offset)[0]


def u24le(data: bytes, offset: int) -> int:
    return int.from_bytes(data[offset : offset + 3], "little")


def u32le(data: bytes, offset: int) -> int:
    return struct.unpack_from("<I", data, offset)[0]


def load_vgm(path: pathlib.Path) -> bytes:
    data = path.read_bytes()
    if data[:2] == b"\x1f\x8b":
        data = gzip.decompress(data)
    if data[:4] != b"Vgm ":
        raise SystemExit(f"not a VGM file: {path}")
    return data


def command_payload_size(command: int) -> int | None:
    if command in (0x30, 0x4F, 0x50):
        return 1
    if 0x51 <= command <= 0x5F or command == 0xA0:
        return 2
    if 0xB0 <= command <= 0xBF:
        return 2
    if 0xC0 <= command <= 0xDF:
        return 3
    if command == 0xE0:
        return 4
    if command == 0x90:
        return 4
    if command == 0x91:
        return 4
    if command == 0x92:
        return 5
    if command == 0x93:
        return 10
    if command == 0x94:
        return 1
    if command == 0x95:
        return 4
    return None


class ActivityBins:
    def __init__(self) -> None:
        self.bins: list[dict[str, int]] = []

    def _ensure(self, index: int) -> dict[str, int]:
        while len(self.bins) <= index:
            self.bins.append(Counter())
        return self.bins[index]

    def add(self, start: int, duration: int, state: dict[str, int]) -> None:
        cursor = start
        remaining = duration
        while remaining:
            index = cursor // SAMPLE_RATE
            amount = min(remaining, SAMPLE_RATE - (cursor % SAMPLE_RATE))
            target = self._ensure(index)
            target["samples"] += amount
            for name, value in state.items():
                target[name] += value * amount
            cursor += amount
            remaining -= amount


def analyze(path: pathlib.Path) -> None:
    data = load_vgm(path)
    version = u32le(data, 0x08)
    data_rel = u32le(data, 0x34) if len(data) >= 0x38 else 0
    data_start = 0x40 if data_rel == 0 else 0x34 + data_rel
    eof_rel = u32le(data, 0x04)
    eof_absolute = 0x04 + eof_rel if eof_rel else len(data)
    loop_rel = u32le(data, 0x1C)
    loop_absolute = 0x1C + loop_rel if loop_rel else 0
    total_header_samples = u32le(data, 0x18)
    loop_header_samples = u32le(data, 0x20)
    segapcm_clock = u32le(data, 0x38) & 0x3FFF_FFFF
    segapcm_interface = u32le(data, 0x3C)
    ym2203_clock = u32le(data, 0x44) & 0x3FFF_FFFF

    command_counts: Counter[int] = Counter()
    wait_counts: Counter[str] = Counter()
    reg_counts: Counter[int] = Counter()
    ssg_reg_counts: Counter[int] = Counter()
    fm_reg_counts: Counter[int] = Counter()
    other_ym_counts: Counter[int] = Counter()
    key_on_counts: Counter[int] = Counter()
    key_off_counts: Counter[int] = Counter()
    key_on_operator_masks: Counter[int] = Counter()
    alg_counts: Counter[tuple[int, int]] = Counter()
    feedback_counts: Counter[tuple[int, int]] = Counter()
    c0_reg_counts: Counter[int] = Counter()
    data_block_counts: Counter[int] = Counter()
    unknown_counts: Counter[int] = Counter()

    ssg_regs = [0] * 16
    fm_key_mask = [0] * 3
    pcm_regs = [dict(vol_l=0, vol_r=0, delta=0, control=1,
                     control_written=0) for _ in range(16)]
    bins = ActivityBins()

    def activity_state() -> dict[str, int]:
        mixer = ssg_regs[7]
        ssg_active = 0
        for channel in range(3):
            volume = ssg_regs[8 + channel]
            enabled_source = not ((mixer >> channel) & 1) or not (
                (mixer >> (channel + 3)) & 1
            )
            if enabled_source and (volume & 0x1F):
                ssg_active += 1
        pcm_active = 0
        pcm_volume = 0
        for channel in pcm_regs:
            if (channel["control_written"] and
                    not (channel["control"] & 1) and channel["delta"] and
                    (channel["vol_l"] or channel["vol_r"])):
                pcm_active += 1
                pcm_volume += channel["vol_l"] + channel["vol_r"]
        return {
            "fm": sum(mask != 0 for mask in fm_key_mask),
            "ssg": ssg_active,
            "pcm": pcm_active,
            "pcm_volume": pcm_volume,
        }

    pc = data_start
    sample = 0
    end_pc = 0
    while pc < len(data):
        command_pc = pc
        command = data[pc]
        command_counts[command] += 1
        pc += 1

        if command == 0x66:
            end_pc = command_pc
            break
        if command == 0x61:
            wait = u16le(data, pc)
            pc += 2
            wait_counts["0x61"] += 1
            bins.add(sample, wait, activity_state())
            sample += wait
            continue
        if command == 0x62:
            wait_counts["0x62"] += 1
            bins.add(sample, 735, activity_state())
            sample += 735
            continue
        if command == 0x63:
            wait_counts["0x63"] += 1
            bins.add(sample, 882, activity_state())
            sample += 882
            continue
        if 0x70 <= command <= 0x7F:
            wait = (command & 0x0F) + 1
            wait_counts["0x70-0x7f"] += 1
            bins.add(sample, wait, activity_state())
            sample += wait
            continue
        if 0x80 <= command <= 0x8F:
            wait = command & 0x0F
            wait_counts["0x80-0x8f"] += 1
            bins.add(sample, wait, activity_state())
            sample += wait
            continue
        if command == 0x67:
            if data[pc] != 0x66:
                raise SystemExit(f"bad data-block marker at 0x{command_pc:x}")
            block_type = data[pc + 1]
            block_size = u32le(data, pc + 2)
            data_block_counts[block_type] += 1
            pc += 6 + block_size
            continue
        if command == 0x68:
            pc += 11
            continue
        if command == 0x55:
            register = data[pc]
            value = data[pc + 1]
            pc += 2
            reg_counts[register] += 1
            if register <= 0x0F:
                ssg_reg_counts[register] += 1
                ssg_regs[register] = value
            elif 0x20 <= register <= 0xB6:
                fm_reg_counts[register] += 1
            else:
                other_ym_counts[register] += 1

            if register == 0x28:
                channel = value & 0x03
                operator_mask = (value >> 4) & 0x0F
                if channel < 3:
                    fm_key_mask[channel] = operator_mask
                    if operator_mask:
                        key_on_counts[channel] += 1
                        key_on_operator_masks[operator_mask] += 1
                    else:
                        key_off_counts[channel] += 1
            if 0xB0 <= register <= 0xB2:
                channel = register - 0xB0
                alg_counts[(channel, value & 0x07)] += 1
                feedback_counts[(channel, (value >> 3) & 0x07)] += 1
            continue
        if command == 0xC0:
            address = data[pc] | (data[pc + 1] << 8)
            value = data[pc + 2]
            pc += 3
            mapped = address & 0xFF
            c0_reg_counts[mapped] += 1
            channel = (mapped >> 3) & 0x0F
            low_base = channel << 3
            if mapped == low_base + 2:
                pcm_regs[channel]["vol_l"] = value
            elif mapped == low_base + 3:
                pcm_regs[channel]["vol_r"] = value
            elif mapped == low_base + 7:
                pcm_regs[channel]["delta"] = value
            elif mapped == 0x86 + low_base:
                pcm_regs[channel]["control"] = value
                pcm_regs[channel]["control_written"] = 1
            continue

        payload = command_payload_size(command)
        if payload is None:
            unknown_counts[command] += 1
            raise SystemExit(
                f"unknown command 0x{command:02x} at 0x{command_pc:x}"
            )
        pc += payload

    print(f"file={path}")
    print(f"bytes={len(data)} version=0x{version:08x}")
    print(
        f"data_start=0x{data_start:x} eof=0x{eof_absolute:x} "
        f"end_command_pc=0x{end_pc:x}"
    )
    print(
        f"header_total_samples={total_header_samples} parsed_wait_samples={sample} "
        f"seconds={sample / SAMPLE_RATE:.6f}"
    )
    print(
        f"loop_offset=0x{loop_absolute:x} loop_samples={loop_header_samples} "
        f"loop_seconds={loop_header_samples / SAMPLE_RATE:.6f}"
    )
    print(
        f"ym2203_clock={ym2203_clock} segapcm_clock={segapcm_clock} "
        f"segapcm_interface=0x{segapcm_interface:08x}"
    )
    print(
        f"commands={sum(command_counts.values())} ym2203_0x55={command_counts[0x55]} "
        f"ssg_writes={sum(ssg_reg_counts.values())} "
        f"fm_control_writes={sum(fm_reg_counts.values())} "
        f"other_ym_writes={sum(other_ym_counts.values())} c0={command_counts[0xC0]}"
    )
    print(
        f"wait_commands={sum(wait_counts.values())} wait_breakdown="
        + ",".join(f"{name}:{count}" for name, count in sorted(wait_counts.items()))
    )
    print(
        "data_blocks="
        + (",".join(
            f"0x{block_type:02x}:{count}"
            for block_type, count in sorted(data_block_counts.items())
        ) or "none")
    )
    print(
        "ssg_regs="
        + ",".join(
            f"{register:02x}:{count}"
            for register, count in sorted(ssg_reg_counts.items())
        )
    )
    print(
        "fm_regs="
        + ",".join(
            f"{register:02x}:{count}"
            for register, count in sorted(fm_reg_counts.items())
        )
    )
    print(
        "key_on=" + ",".join(
            f"ch{channel}:{key_on_counts[channel]}"
            for channel in range(3)
        ) + " key_off=" + ",".join(
            f"ch{channel}:{key_off_counts[channel]}"
            for channel in range(3)
        )
    )
    print(
        "key_masks=" + ",".join(
            f"0x{mask:x}:{count}"
            for mask, count in sorted(key_on_operator_masks.items())
        )
    )
    print(
        "algorithm=" + ",".join(
            f"ch{channel}/a{algorithm}:{count}"
            for (channel, algorithm), count in sorted(alg_counts.items())
        )
    )
    print(
        "feedback=" + ",".join(
            f"ch{channel}/f{feedback}:{count}"
            for (channel, feedback), count in sorted(feedback_counts.items())
        )
    )

    populated = []
    for index, values in enumerate(bins.bins):
        samples = values.get("samples", 0)
        if not samples:
            continue
        fm = values.get("fm", 0) / samples
        ssg = values.get("ssg", 0) / samples
        pcm = values.get("pcm", 0) / samples
        pcm_volume = values.get("pcm_volume", 0) / samples
        populated.append((index, fm, ssg, pcm, pcm_volume))

    def select(predicate, score, used: list[int]) -> tuple | None:
        choices = [entry for entry in populated if predicate(entry) and all(
            abs(entry[0] - previous) >= 2 for previous in used
        )]
        return max(choices, key=score) if choices else None

    selected: list[tuple[str, tuple]] = []
    used_bins: list[int] = []
    first_overlap = next((entry for entry in populated
                          if entry[1] > 0 and entry[2] > 0), None)
    if first_overlap:
        selected.append(("first_fm_ssg", first_overlap))
        used_bins.append(first_overlap[0])
    main = select(
        lambda entry: entry[0] >= 5 and entry[1] > 0 and entry[2] > 0,
        lambda entry: entry[1] + entry[2], used_bins,
    )
    if main:
        selected.append(("main_fm_ssg", main))
        used_bins.append(main[0])
    strong = select(
        lambda entry: entry[1] > 0 and entry[3] > 0,
        lambda entry: entry[1] + entry[2] + entry[3] + entry[4] / 255.0,
        used_bins,
    )
    if strong:
        selected.append(("fm_pcm_strong", strong))
        used_bins.append(strong[0])
    for label, entry in selected:
        index, fm, ssg, pcm, pcm_volume = entry
        print(
            f"window={label} samples={index * SAMPLE_RATE}:"
            f"{(index + 1) * SAMPLE_RATE} seconds={index:.3f}:{index + 1:.3f} "
            f"fm_active_avg={fm:.3f} ssg_active_avg={ssg:.3f} "
            f"pcm_active_avg={pcm:.3f} pcm_volume_avg={pcm_volume:.3f}"
        )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("vgm", type=pathlib.Path)
    args = parser.parse_args()
    analyze(args.vgm)


if __name__ == "__main__":
    main()
