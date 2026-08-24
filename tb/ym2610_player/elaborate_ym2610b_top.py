#!/usr/bin/env python3
"""Elaborate the real production emu/profile graph with YM2610B enabled."""

from __future__ import annotations

import pathlib
import re
import subprocess
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[2]
QIP = ROOT / "hw/ym2610_player/files_ym2610_player.qip"


def main() -> int:
    pattern = re.compile(
        r"\[file join \$::quartus\(qip_path\)\s+([^\s\]]+)")
    sources = []
    for relative in pattern.findall(QIP.read_text()):
        path = (QIP.parent / relative).resolve()
        if path.suffix.lower() in (".v", ".sv"):
            sources.append(str(path))
    stubs = [
        str(ROOT / "tb/golden_player_shell_v1_1/stage_c/"
            "hps_io_stage_c_upload_stub.sv"),
        str(ROOT / "tb/megavgm_pll_elab_stubs.sv"),
    ]
    with tempfile.TemporaryDirectory(prefix="ym2610b-full-top-") as build:
        for product, extra_define in (("YM2610", []),
                                      ("YM2610B", ["-DYM2610B_PLAYER"])):
            command = [
                "iverilog", "-g2012", "-I", str(ROOT / "tb"),
                "-DMISTER_FB", "-DYM2610_PLAYER", *extra_define,
                "-DFIXED_REGION_MODE=5", "-DMODE5_VGM_BACKEND",
                "-DMODE5_VGM_ADDR_WIDTH=23",
                "-DMEGAVGMDRIVE_PRODUCTION_AUDIO_BUILD",
                '-DBUILD_DATE="20260824"', "-s", "emu", "-o",
                str(pathlib.Path(build) / f"{product}.vvp"), *stubs, *sources,
            ]
            result = subprocess.run(command, cwd=ROOT, text=True,
                                    stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT)
            if result.returncode:
                print(result.stdout)
                return result.returncode
            print(f"{product}_FULL_TOP_ELAB sources={len(sources)} result=PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
