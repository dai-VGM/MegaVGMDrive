#!/usr/bin/env python3
"""Generate the original PAL/6581 manual-loop hardware fixture.

The tune is deliberately small and copyright-free.  Its first second is an
ascending introduction.  The following two seconds form a four-note loop;
the play routine returns its counter to the loop start at the end boundary.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import struct


SCHEMA = "MegaVGMPlayer-SID-loop-v1"
SID_NAME = "C7_2_Manual_Loop_PAL_6581.sid"
LOOP_START_MS = 1000
LOOP_END_MS = 3000


class Assembler:
    def __init__(self, origin: int):
        self.origin = origin
        self.code = bytearray()
        self.labels: dict[str, int] = {}
        self.fixups: list[tuple[int, str]] = []

    def emit(self, *values: int) -> None:
        self.code.extend(values)

    def label(self, name: str) -> None:
        self.labels[name] = self.origin + len(self.code)

    def branch(self, opcode: int, target: str) -> None:
        self.emit(opcode, 0)
        self.fixups.append((len(self.code) - 1, target))

    def finish(self) -> bytes:
        for operand, target in self.fixups:
            next_pc = self.origin + operand + 1
            delta = self.labels[target] - next_pc
            if not -128 <= delta <= 127:
                raise ValueError(f"branch to {target} is out of range")
            self.code[operand] = delta & 0xFF
        return bytes(self.code)


def lda_imm(a: Assembler, value: int) -> None:
    a.emit(0xA9, value)


def sta_abs(a: Assembler, address: int) -> None:
    a.emit(0x8D, address & 0xFF, address >> 8)


def emit_note(a: Assembler, frequency: int) -> None:
    lda_imm(a, frequency & 0xFF)
    sta_abs(a, 0xD400)
    lda_imm(a, frequency >> 8)
    sta_abs(a, 0xD401)
    a.emit(0x60)  # RTS


def make_sid() -> bytes:
    init = Assembler(0x1000)
    for address, value in (
        (0xD404, 0x00),  # voice 1 gate off while initializing
        (0xD418, 0x0F),  # maximum master volume
        (0xD405, 0x12),  # attack/decay
        (0xD406, 0xF2),  # sustain/release
        (0xD400, 0x67),  # audible ascending intro start
        (0xD401, 0x11),
        (0xD404, 0x21),  # sawtooth + gate
        (0x10F0, 0x00),  # frame counter outside the play routine
    ):
        lda_imm(init, value)
        sta_abs(init, address)
    init.emit(0x60)
    init_code = init.finish()
    if len(init_code) > 0x40:
        raise ValueError("init routine overlaps play routine")

    play = Assembler(0x1040)
    play.emit(0xEE, 0xF0, 0x10)       # INC $10f0
    play.emit(0xAD, 0xF0, 0x10)       # LDA $10f0
    play.emit(0xC9, 50)               # CMP #50
    play.branch(0x90, "intro")        # BCC intro
    for frame, label in ((50, "note_a"), (75, "note_b"),
                         (100, "note_c"), (125, "note_b")):
        play.emit(0xC9, frame)
        play.branch(0xF0, label)       # BEQ
    play.emit(0xC9, 150)
    play.branch(0xD0, "done")         # BNE done
    lda_imm(play, 50)
    sta_abs(play, 0x10F0)              # exact two-second loop restart
    play.branch(0xD0, "note_a")       # BNE is unconditional after LDA #50
    play.label("intro")
    play.emit(0xEE, 0x00, 0xD4)       # INC $d400: audible intro sweep
    play.label("done")
    play.emit(0x60)
    play.label("note_a")
    emit_note(play, 0x15F4)
    play.label("note_b")
    emit_note(play, 0x1A14)
    play.label("note_c")
    emit_note(play, 0x1D44)
    play_code = play.finish()

    image = bytearray(init_code)
    image.extend(b"\xEA" * (0x40 - len(image)))
    image.extend(play_code)
    if len(image) > 0xF0:
        raise ValueError("program overlaps frame counter")

    header = bytearray(0x7C)
    header[:4] = b"PSID"
    struct.pack_into(">HHHHHHHI", header, 4, 2, 0x7C, 0, 0x1000,
                     0x1040, 1, 1, 0)
    header[22:54] = b"C7.2 Manual Loop PAL 6581".ljust(32, b"\0")
    header[54:86] = b"MegaVGMPlayer original fixture".ljust(32, b"\0")
    header[86:118] = b"2026".ljust(32, b"\0")
    struct.pack_into(">H", header, 118, 0x0014)  # PAL, MOS6581
    return bytes(header) + b"\x00\x10" + bytes(image)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    sid_path = args.output_dir / SID_NAME
    sid_path.write_bytes(make_sid())
    source_sha = hashlib.sha256(sid_path.read_bytes()).hexdigest()
    sidecar = {
        "schema": SCHEMA,
        "source_sha256": source_sha,
        "subtune": 1,
        "loop_start_ms": LOOP_START_MS,
        "loop_end_ms": LOOP_END_MS,
    }
    sidecar_path = Path(str(sid_path) + ".loop.json")
    sidecar_path.write_text(json.dumps(sidecar, indent=2) + "\n")
    print(sid_path)
    print(sidecar_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
