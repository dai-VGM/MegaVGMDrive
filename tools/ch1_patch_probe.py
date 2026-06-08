#!/usr/bin/env python3
import argparse
import csv
import struct
from pathlib import Path


CH1_OPERATOR_REGS = [
    *range(0x30, 0x40, 4),
    *range(0x40, 0x50, 4),
    *range(0x50, 0x60, 4),
    *range(0x60, 0x70, 4),
    *range(0x70, 0x80, 4),
    *range(0x80, 0x90, 4),
    *range(0x90, 0xA0, 4),
]

CH1_REGS = set(CH1_OPERATOR_REGS + [0xA0, 0xA4, 0xB0, 0xB4])
CH1_PATCH_REGS = set(CH1_OPERATOR_REGS + [0xB0, 0xB4])
CH1_CHANNEL_KEYON = 0


def u32(data, off):
    return struct.unpack_from("<I", data, off)[0]


def data_start(data):
    off = u32(data, 0x34) if len(data) >= 0x38 else 0
    return 0x40 if off == 0 else 0x34 + off


def h2(value):
    return f"{value:02X}"


def reg_name(reg):
    if reg in range(0x30, 0x40, 4):
        return f"DT/MUL op{((reg - 0x30) // 4) + 1}"
    if reg in range(0x40, 0x50, 4):
        return f"TL op{((reg - 0x40) // 4) + 1}"
    if reg in range(0x50, 0x60, 4):
        return f"RS/AR op{((reg - 0x50) // 4) + 1}"
    if reg in range(0x60, 0x70, 4):
        return f"AM/DR op{((reg - 0x60) // 4) + 1}"
    if reg in range(0x70, 0x80, 4):
        return f"SR op{((reg - 0x70) // 4) + 1}"
    if reg in range(0x80, 0x90, 4):
        return f"SL/RR op{((reg - 0x80) // 4) + 1}"
    if reg in range(0x90, 0xA0, 4):
        return f"SSG-EG op{((reg - 0x90) // 4) + 1}"
    return {
        0xA0: "FNUM low",
        0xA4: "block/FNUM high",
        0xB0: "feedback/algorithm",
        0xB4: "pan/AMS/PMS",
    }.get(reg, f"reg {reg:02X}")


def parse_vgm(path):
    data = Path(path).read_bytes()
    if data[:4] != b"Vgm ":
        raise SystemExit(f"{path}: not a VGM file")

    pc = data_start(data)
    samples = 0
    while pc < len(data):
        cmd_pc = pc
        cmd = data[pc]
        pc += 1

        if cmd == 0x66:
            yield cmd_pc, samples, "end", None
            break
        if cmd == 0x50:
            pc += 1
            continue
        if cmd == 0x4F:
            pc += 1
            continue
        if cmd in (0x52, 0x53):
            if pc + 2 > len(data):
                break
            reg = data[pc]
            val = data[pc + 1]
            pc += 2
            yield cmd_pc, samples, "ym", (1 if cmd == 0x53 else 0, reg, val)
            continue
        if cmd == 0x61:
            if pc + 2 > len(data):
                break
            wait = data[pc] | (data[pc + 1] << 8)
            pc += 2
            samples += wait
            continue
        if cmd == 0x62:
            samples += 735
            continue
        if cmd == 0x63:
            samples += 882
            continue
        if 0x70 <= cmd <= 0x7F:
            samples += (cmd & 0x0F) + 1
            continue
        if cmd == 0x67:
            if pc + 6 > len(data):
                break
            if data[pc] != 0x66:
                raise SystemExit(f"bad data block at 0x{cmd_pc:X}")
            block_type = data[pc + 1]
            size = data[pc + 2] | (data[pc + 3] << 8) | (data[pc + 4] << 16) | (data[pc + 5] << 24)
            pc += 6 + size
            yield cmd_pc, samples, "data_block", (block_type, size)
            continue
        if cmd == 0xE0:
            pc += 4
            continue
        if 0x80 <= cmd <= 0x8F:
            samples += cmd & 0x0F
            continue

        raise SystemExit(f"unsupported command 0x{cmd:02X} at 0x{cmd_pc:X}")


def snapshot(state):
    return {reg: state.get(reg, 0) for reg in sorted(CH1_REGS)}


def patch_signature(snap):
    return tuple((reg, snap.get(reg, 0)) for reg in sorted(CH1_PATCH_REGS))


def format_patch(snap):
    groups = []
    for base, label in [
        (0x30, "DT/MUL"),
        (0x40, "TL"),
        (0x50, "RS/AR"),
        (0x60, "AM/DR"),
        (0x70, "SR"),
        (0x80, "SL/RR"),
        (0x90, "SSG-EG"),
    ]:
        groups.append(f"{label}=" + ",".join(h2(snap.get(base + 4 * i, 0)) for i in range(4)))
    groups.append(f"A0={h2(snap.get(0xA0, 0))}")
    groups.append(f"A4={h2(snap.get(0xA4, 0))}")
    groups.append(f"B0={h2(snap.get(0xB0, 0))}")
    groups.append(f"B4={h2(snap.get(0xB4, 0))}")
    return " ".join(groups)


def write_vgm_header(out, total_samples, ym_clock=7670454):
    header = bytearray(0x40)
    header[0:4] = b"Vgm "
    struct.pack_into("<I", header, 0x08, 0x00000150)
    struct.pack_into("<I", header, 0x18, total_samples)
    struct.pack_into("<I", header, 0x2C, ym_clock)
    struct.pack_into("<I", header, 0x34, 0x0C)
    out.extend(header)


def ym(out, port, reg, val):
    out.extend([0x53 if port else 0x52, reg & 0xFF, val & 0xFF])


def wait_samples(out, samples):
    while samples >= 735:
        out.append(0x62)
        samples -= 735
    if samples:
        out.extend([0x61, samples & 0xFF, (samples >> 8) & 0xFF])


def generate_sustain(path, snap, variants):
    out = bytearray()
    total = 44100 * 9
    write_vgm_header(out, total)

    ym(out, 0, 0x22, 0x00)
    ym(out, 0, 0x27, 0x00)
    ym(out, 0, 0x2B, 0x00)
    ym(out, 0, 0x28, 0x00)

    for reg in sorted(CH1_OPERATOR_REGS):
        val = snap.get(reg, 0)
        if "no_ssgeg" in variants and 0x90 <= reg <= 0x9C:
            val = 0
        if "detune0" in variants and 0x30 <= reg <= 0x3C:
            val &= 0x0F
        ym(out, 0, reg, val)

    b0 = snap.get(0xB0, 0)
    for fb in range(8):
        if f"fb{fb}" in variants:
            b0 = (b0 & 0x07) | ((fb & 0x07) << 3)
    if "alg0" in variants:
        b0 &= 0x38
    ym(out, 0, 0xB0, b0)
    ym(out, 0, 0xB4, 0xC0)

    ym(out, 0, 0xA4, snap.get(0xA4, 0))
    ym(out, 0, 0xA0, snap.get(0xA0, 0))

    keyon_ops = 0xF0
    op_bits = {
        1: 0x10,
        2: 0x20,
        3: 0x40,
        4: 0x80,
    }
    selected_ops = sorted(
        int(variant[2:])
        for variant in variants
        if variant.startswith("op") and variant[2:].isdigit()
    )
    if selected_ops:
        keyon_ops = 0
        for op in selected_ops:
            keyon_ops |= op_bits[op]
    ym(out, 0, 0x28, keyon_ops | CH1_CHANNEL_KEYON)
    wait_samples(out, 44100 * 8)
    ym(out, 0, 0x28, CH1_CHANNEL_KEYON)
    wait_samples(out, 44100)
    out.append(0x66)
    eof = len(out) - 4
    struct.pack_into("<I", out, 0x04, eof)
    Path(path).write_bytes(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("vgm")
    ap.add_argument("--csv", default="out/fm_only_ch1_timeline.csv")
    ap.add_argument("--report", default="out/fm_only_ch1_report.txt")
    ap.add_argument("--generate-prefix", default="out/ch1_main_patch")
    args = ap.parse_args()

    state = {}
    events = []
    keyons = []
    patch_ids = {}
    next_patch_id = 1
    last_patch_sig = None

    for pc, samples, kind, payload in parse_vgm(args.vgm):
        if kind != "ym":
            continue
        port, reg, val = payload
        if port != 0:
            continue

        if reg in CH1_REGS:
            old = state.get(reg)
            state[reg] = val
            snap = snapshot(state)
            sig = patch_signature(snap)
            if sig not in patch_ids:
                patch_ids[sig] = next_patch_id
                next_patch_id += 1
            patch_id = patch_ids[sig]

            events.append({
                "pc": f"0x{pc:05X}",
                "sample": samples,
                "time_s": f"{samples / 44100.0:.6f}",
                "reg": f"0x{reg:02X}",
                "name": reg_name(reg),
                "old": "" if old is None else f"0x{old:02X}",
                "new": f"0x{val:02X}",
                "patch_id": patch_id,
            })

            if reg in CH1_PATCH_REGS and sig != last_patch_sig:
                last_patch_sig = sig

        if reg == 0x28 and (val & 0x07) == CH1_CHANNEL_KEYON:
            snap = snapshot(state)
            sig = patch_signature(snap)
            if sig not in patch_ids:
                patch_ids[sig] = next_patch_id
                next_patch_id += 1
            keyons.append({
                "pc": pc,
                "samples": samples,
                "time_s": samples / 44100.0,
                "data": val,
                "active": bool(val & 0xF0),
                "patch_id": patch_ids[sig],
                "snap": snap,
            })

    Path(args.csv).parent.mkdir(parents=True, exist_ok=True)
    with open(args.csv, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=["pc", "sample", "time_s", "reg", "name", "old", "new", "patch_id"])
        writer.writeheader()
        writer.writerows(events)

    active_keyons = [k for k in keyons if k["active"]]
    patch_counts = {}
    for k in active_keyons:
        patch_counts[k["patch_id"]] = patch_counts.get(k["patch_id"], 0) + 1

    lines = []
    lines.append(f"input: {args.vgm}")
    lines.append(f"timeline_csv: {args.csv}")
    lines.append(f"CH1 register events: {len(events)}")
    lines.append(f"CH1 active key-ons: {len(active_keyons)}")
    lines.append("")
    lines.append("Active CH1 key-on timeline:")
    for i, k in enumerate(active_keyons[:80], 1):
        lines.append(
            f"{i:03d} t={k['time_s']:9.3f}s sample={k['samples']:8d} pc=0x{k['pc']:05X} "
            f"data=0x{k['data']:02X} patch={k['patch_id']} {format_patch(k['snap'])}"
        )
    if len(active_keyons) > 80:
        lines.append(f"... {len(active_keyons) - 80} more active key-ons omitted")

    lines.append("")
    lines.append("Patch use counts among active CH1 key-ons:")
    for patch_id, count in sorted(patch_counts.items(), key=lambda item: (-item[1], item[0])):
        first = next(k for k in active_keyons if k["patch_id"] == patch_id)
        lines.append(
            f"patch {patch_id}: count={count} first_t={first['time_s']:.3f}s "
            f"first_pc=0x{first['pc']:05X} {format_patch(first['snap'])}"
        )

    # The first long-lived non-muted melodic CH1 patch appears after the intro
    # key-on activity settles. Prefer the most-used active patch after 15s, and
    # fall back to the first active key-on after 8s if the source is shorter.
    candidates_after_intro = [
        k for k in active_keyons
        if k["time_s"] >= 15.0
    ]
    main_patch_id = None
    if candidates_after_intro:
        counts_after_intro = {}
        for k in candidates_after_intro:
            counts_after_intro[k["patch_id"]] = counts_after_intro.get(k["patch_id"], 0) + 1
        main_patch_id = max(counts_after_intro.items(), key=lambda item: (item[1], -item[0]))[0]
    main = None
    if main_patch_id is not None:
        main = next(k for k in active_keyons if k["patch_id"] == main_patch_id)
    if main is None:
        main = next((k for k in active_keyons if k["time_s"] >= 8.0), active_keyons[0] if active_keyons else None)
    if main:
        lines.append("")
        lines.append("Selected main-melody candidate:")
        lines.append(
            f"t={main['time_s']:.3f}s pc=0x{main['pc']:05X} patch={main['patch_id']} "
            f"{format_patch(main['snap'])}"
        )
        variants = {
            "": set(),
            "_fb0": {"fb0"},
            "_detune0": {"detune0"},
            "_no_ssgeg": {"no_ssgeg"},
            "_alg0": {"alg0"},
            "_op1_only": {"op1"},
            "_op2_only": {"op2"},
            "_op3_only": {"op3"},
            "_op4_only": {"op4"},
            "_op3_plus_op4": {"op3", "op4"},
            "_op2_plus_op4": {"op2", "op4"},
            "_op1_plus_op4": {"op1", "op4"},
            "_op2_plus_op3_plus_op4": {"op2", "op3", "op4"},
            "_op1_plus_op2_plus_op3_plus_op4_fb0": {"op1", "op2", "op3", "op4", "fb0"},
        }
        for fb in range(1, 8):
            variants[f"_fb{fb}"] = {f"fb{fb}"}
        lines.append("")
        lines.append("Generated minimal CH1 main patch VGMs:")
        for suffix, opts in variants.items():
            out = f"{args.generate_prefix}{suffix}.vgm"
            generate_sustain(out, main["snap"], opts)
            lines.append(out)

        lines.append("")
        lines.append("Generated additional high-use CH1 patch candidates:")
        for patch_id, count in sorted(patch_counts.items(), key=lambda item: (-item[1], item[0]))[:4]:
            first = next(k for k in active_keyons if k["patch_id"] == patch_id)
            base = f"{args.generate_prefix}_patch{patch_id}"
            out = f"{base}.vgm"
            generate_sustain(out, first["snap"], set())
            lines.append(
                f"{out} count={count} first_t={first['time_s']:.3f}s "
                f"first_pc=0x{first['pc']:05X}"
            )

    Path(args.report).write_text("\n".join(lines) + "\n")
    print("\n".join(lines))


if __name__ == "__main__":
    main()
