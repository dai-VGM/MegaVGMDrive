#!/usr/bin/env python3
"""Inspect SegaPCM type-0x80 blocks and 0xC0 writes in a VGM file.

This intentionally mirrors the current experimental shadow decode in
rtl/segapcm_sound_module.sv rather than a generic SegaPCM map.
"""

from __future__ import annotations

import argparse
import dataclasses
import gzip
import pathlib
import struct
from collections import Counter, defaultdict


def u32le(data: bytes, off: int) -> int:
    return struct.unpack_from("<I", data, off)[0] if off + 4 <= len(data) else 0


def u16le(data: bytes, off: int) -> int:
    return struct.unpack_from("<H", data, off)[0] if off + 2 <= len(data) else 0


@dataclasses.dataclass
class C0Write:
    pc: int
    sample: int
    addr: int
    mapped: int
    data: int
    channel: int
    reg: str

    @property
    def seconds(self) -> float:
        return self.sample / 44100.0


@dataclasses.dataclass
class Block:
    pc: int
    block_type: int
    size: int
    data_start: int
    data_end: int
    rom_size: int | None = None
    rom_dest: int | None = None


class Shadow:
    def __init__(self) -> None:
        self.cur_low = 0
        self.cur_mid = 0
        self.cur_high = 0
        self.loop_mid = 0
        self.loop_high = 0
        self.end = 0
        self.delta = 0
        self.vol_l = 0
        self.vol_r = 0
        self.ctrl = 0
        self.ctrl_ext = 0

    def apply(self, mapped: int, data: int) -> str:
        # This mirrors the ch3 case statements in segapcm_sound_module.sv,
        # generalized by mapped_addr[6:3].
        low_base = (mapped & 0x78)
        high_base = 0x84 + low_base
        off_low = mapped - low_base
        off_high = mapped - high_base
        reg = "?"
        if off_low == 0:
            self.cur_low = data
            reg = "cur_low"
        elif off_low == 2:
            self.vol_l = data
            reg = "vol_l"
        elif off_low == 3:
            self.vol_r = data
            reg = "vol_r"
        elif off_low == 4:
            self.loop_mid = data
            reg = "loop_mid"
        elif off_low == 5:
            self.loop_high = data
            reg = "loop_high"
        elif off_low == 6:
            self.end = data
            reg = "end"
        elif off_low == 7:
            self.delta = data
            reg = "delta"
        elif off_high == 0:
            self.cur_mid = data
            reg = "cur_mid"
        elif off_high == 1:
            self.cur_high = data
            reg = "cur_high"
        elif off_high == 2:
            self.ctrl = data
            reg = "ctrl"
        elif off_high == 3:
            self.ctrl_ext = data
            reg = "ctrl_ext"
        return reg

    @property
    def rtl_current_seed16(self) -> int:
        # Current experimental C0Drive seed:
        # {c0_capture_ch3_cur_high_i, c0_capture_ch3_cur_low_i, 8'd0}
        return (self.cur_high << 8) | self.cur_low

    @property
    def alt_current16(self) -> int:
        # Generic-looking adjacent-byte candidate, for contrast.
        return (self.cur_high << 8) | self.cur_mid

    @property
    def loop16(self) -> int:
        return (self.loop_high << 8) | self.loop_mid

    @property
    def end_boundary16(self) -> int:
        return ((self.end + 1) & 0xFF) << 8

    @property
    def bank(self) -> int:
        return (self.ctrl >> 4) & 0x7


def load_vgm(path: pathlib.Path) -> bytes:
    raw = path.read_bytes()
    if raw[:2] == b"\x1f\x8b":
        raw = gzip.decompress(raw)
    if raw[:4] != b"Vgm ":
        raise SystemExit(f"not a VGM file: {path}")
    return raw


def reg_name_for(mapped: int) -> tuple[int, str]:
    ch = (mapped >> 3) & 0xF
    low_base = mapped & 0x78
    high_base = 0x84 + low_base
    off_low = mapped - low_base
    off_high = mapped - high_base
    names_low = {
        0: "cur_low",
        2: "vol_l",
        3: "vol_r",
        4: "loop_mid",
        5: "loop_high",
        6: "end",
        7: "delta",
    }
    names_high = {
        0: "cur_mid",
        1: "cur_high",
        2: "ctrl",
        3: "ctrl_ext",
    }
    if off_low in names_low:
        return ch, names_low[off_low]
    if off_high in names_high:
        return ch, names_high[off_high]
    return ch, "?"


def payload_index(addr16: int, db: int, size: int) -> str:
    if db <= addr16 < db + size:
        return f"{addr16 - db:04X}"
    if addr16 < size:
        return f"{addr16:04X} (addr<SZ fallback)"
    return "FAULT"


def parse(data: bytes) -> tuple[dict, list[Block], list[C0Write]]:
    eof_off = u32le(data, 0x04)
    version = u32le(data, 0x08)
    total_samples = u32le(data, 0x18)
    loop_rel = u32le(data, 0x1C)
    loop_samples = u32le(data, 0x20)
    data_rel = u32le(data, 0x34)
    data_off = 0x40 if data_rel == 0 else 0x34 + data_rel
    loop_abs = 0 if loop_rel == 0 else 0x1C + loop_rel
    header = {
        "file_size": len(data),
        "eof_absolute": 0x04 + eof_off if eof_off else 0,
        "version": version,
        "data_offset": data_off,
        "total_samples": total_samples,
        "loop_offset": loop_abs,
        "loop_samples": loop_samples,
    }

    pc = data_off
    sample = 0
    blocks: list[Block] = []
    writes: list[C0Write] = []
    unknown = Counter()

    def need(n: int) -> bool:
        return pc + n <= len(data)

    while pc < len(data):
        cmd_pc = pc
        cmd = data[pc]
        pc += 1
        if cmd == 0x66:
            break
        if cmd == 0x61 and need(2):
            sample += u16le(data, pc)
            pc += 2
        elif cmd == 0x62:
            sample += 735
        elif cmd == 0x63:
            sample += 882
        elif 0x70 <= cmd <= 0x7F:
            sample += (cmd & 0x0F) + 1
        elif cmd == 0x67 and need(6):
            compat = data[pc]
            block_type = data[pc + 1]
            size = u32le(data, pc + 2)
            block_data_start = pc + 6
            block_data_end = block_data_start + size
            rom_size = None
            rom_dest = None
            if compat != 0x66:
                unknown[(cmd, compat)] += 1
            if block_type == 0x80 and block_data_start + 8 <= len(data):
                rom_size = u32le(data, block_data_start)
                rom_dest = u32le(data, block_data_start + 4)
            blocks.append(
                Block(cmd_pc, block_type, size, block_data_start,
                      min(block_data_end, len(data)), rom_size, rom_dest)
            )
            pc = block_data_end
        elif cmd == 0xC0 and need(3):
            lo = data[pc]
            hi = data[pc + 1]
            dd = data[pc + 2]
            addr = (hi << 8) | lo
            mapped = addr & 0xFF
            ch, reg = reg_name_for(mapped)
            writes.append(C0Write(cmd_pc, sample, addr, mapped, dd, ch, reg))
            pc += 3
        elif cmd in (0x4F, 0x50, 0x30) and need(1):
            pc += 1
        elif 0x51 <= cmd <= 0x5F and need(2):
            pc += 2
        elif cmd == 0x68 and need(11):
            # 0x68 0x66 cc oo oo oo dd dd dd ss ss ss
            pc += 11
        elif 0x80 <= cmd <= 0x8F:
            # DAC stream command plus wait nibble.
            sample += cmd & 0x0F
        elif cmd == 0x90 and need(4):
            pc += 4
        elif cmd == 0x91 and need(4):
            pc += 4
        elif cmd == 0x92 and need(5):
            pc += 5
        elif cmd == 0x93 and need(10):
            pc += 10
        elif cmd == 0x94 and need(1):
            pc += 1
        elif cmd == 0x95 and need(4):
            pc += 4
        elif cmd == 0xA0 and need(2):
            pc += 2
        elif 0xB0 <= cmd <= 0xBF and need(2):
            pc += 2
        elif 0xC1 <= cmd <= 0xCF and need(3):
            pc += 3
        elif 0xD0 <= cmd <= 0xDF and need(3):
            pc += 3
        elif cmd == 0xE0 and need(4):
            pc += 4
        else:
            unknown[(cmd,)] += 1
            break

    header["parse_end"] = pc
    header["unknown"] = unknown
    return header, blocks, writes


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("vgm", type=pathlib.Path)
    ap.add_argument("--channel", type=int, default=3)
    ap.add_argument("--max-writes", type=int, default=100)
    args = ap.parse_args()

    data = load_vgm(args.vgm)
    header, blocks, writes = parse(data)
    type80 = [b for b in blocks if b.block_type == 0x80]
    first80 = type80[0] if type80 else None
    db = (first80.rom_dest & 0xFFFF) if first80 and first80.rom_dest is not None else 0
    size = (first80.size - 8) if first80 else 0

    selected = [w for w in writes if w.channel == args.channel]
    shadows = defaultdict(Shadow)
    snapshots = []
    start_events = []
    for w in writes:
        sh = shadows[w.channel]
        reg = sh.apply(w.mapped, w.data)
        if w.channel == args.channel:
            snap = dataclasses.replace(w, reg=reg)
            snapshots.append((snap, Shadow()))
            snapshots[-1][1].__dict__.update(sh.__dict__)
            if reg == "ctrl" and (w.data & 1) == 0:
                start_events.append((snap, snapshots[-1][1]))

    print("Summary")
    print(f"  file: {args.vgm}")
    print(f"  file_size: 0x{header['file_size']:X} ({header['file_size']} bytes)")
    print(f"  version: 0x{header['version']:08X}")
    print(f"  data_offset: 0x{header['data_offset']:X}")
    print(f"  total_samples: {header['total_samples']} ({header['total_samples']/44100.0:.3f} sec)")
    print(f"  loop_offset: 0x{header['loop_offset']:X}")
    print(f"  loop_samples: {header['loop_samples']} ({header['loop_samples']/44100.0:.3f} sec)")
    print(f"  data_blocks: {len(blocks)}, type80_blocks: {len(type80)}")
    print(f"  C0 writes: {len(writes)}, selected ch{args.channel}: {len(selected)}")
    print()

    print("SegaPCM data blocks")
    for b in blocks:
        extra = ""
        if b.block_type == 0x80:
            payload_start = b.data_start + 8
            payload_len = max(0, b.size - 8)
            extra = (
                f" rom_size=0x{b.rom_size:08X}"
                f" rom_dest=0x{b.rom_dest:08X}"
                f" DB(low)=0x{b.rom_dest & 0xFFFF:04X}"
                f" payload=0x{payload_start:X}..0x{payload_start + payload_len - 1:X}"
                f" payload_len=0x{payload_len:X}"
            )
        print(
            f"  pc=0x{b.pc:06X} type=0x{b.block_type:02X}"
            f" size=0x{b.size:X} data=0x{b.data_start:X}..0x{b.data_end-1:X}{extra}"
        )
    print()

    print(f"First {args.max_writes} C0 writes for selected ch{args.channel}")
    print("  # time(s) samp    pc      raw  map reg       data")
    for i, w in enumerate(selected[: args.max_writes]):
        print(
            f"  {i:3d} {w.seconds:7.4f} {w.sample:6d} 0x{w.pc:06X}"
            f" 0x{w.addr:04X} 0x{w.mapped:02X} {w.reg:9s} 0x{w.data:02X}"
        )
    print()

    print(f"Reconstructed start/control events for selected ch{args.channel}")
    print("  # time(s) samp    ctrl bank curRTL loop  endB  delta VL VR PI(curRTL)")
    for i, (w, sh) in enumerate(start_events[:80]):
        cur = sh.rtl_current_seed16
        print(
            f"  {i:3d} {w.seconds:7.4f} {w.sample:6d}"
            f" 0x{sh.ctrl:02X}  {sh.bank:d}   0x{cur:04X}"
            f" 0x{sh.loop16:04X} 0x{sh.end_boundary16:04X}"
            f" 0x{sh.delta:02X} 0x{sh.vol_l:02X} 0x{sh.vol_r:02X}"
            f" {payload_index(cur, db, size)}"
        )
    print()

    if start_events:
        gaps = [start_events[i][0].sample - start_events[i - 1][0].sample
                for i in range(1, len(start_events))]
        print("Start event timing")
        print(f"  count: {len(start_events)}")
        if gaps:
            print(f"  first_time: {start_events[0][0].seconds:.4f} sec")
            print(f"  last_time: {start_events[-1][0].seconds:.4f} sec")
            print(f"  min_gap: {min(gaps)} samples ({min(gaps)/44100.0:.4f} sec)")
            print(f"  max_gap: {max(gaps)} samples ({max(gaps)/44100.0:.4f} sec)")
            print(f"  avg_gap: {sum(gaps)/len(gaps):.1f} samples ({(sum(gaps)/len(gaps))/44100.0:.4f} sec)")
    print()

    print("Selected-channel observations")
    regs = Counter(w.reg for w in selected)
    print("  write counts by reg:", ", ".join(f"{k}={v}" for k, v in sorted(regs.items())))
    deltas = Counter()
    controls = Counter()
    for w, sh in start_events:
        deltas[sh.delta] += 1
        controls[sh.ctrl] += 1
    if deltas:
        print("  start-event deltas:", ", ".join(f"0x{k:02X}:{v}" for k, v in sorted(deltas.items())))
    if controls:
        print("  start-event ctrl:", ", ".join(f"0x{k:02X}:{v}" for k, v in sorted(controls.items())))
    if first80:
        print(f"  hardware-style DB low should be 0x{db:04X}; SZ should be 0x{size:04X}")
    if header["unknown"]:
        print("  parse stopped/unknown:", header["unknown"])


if __name__ == "__main__":
    main()
