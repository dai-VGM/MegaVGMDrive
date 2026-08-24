#!/usr/bin/env python3
"""Static audit for the dedicated YM2610B bring-up revision."""

from __future__ import annotations

import hashlib
import pathlib
import re
import subprocess


ROOT = pathlib.Path(__file__).resolve().parents[2]
BASE = "1ec8b7f5c6a085f7a00ff2dd3bf0d1476e2fe0c1"
CACHE_SHA = "5d799058123d28e2560bb081ccbacd2f81cc34e1f5b52fa273f28a3062ae6a49"
HANDOFF_FILES = (
    "rtl/ym2610_hw0/ym2610_hw0_jt12_mmr.v",
    "rtl/ym2610_hw0/ym2610_hw0_jt10_adpcm_drvA.v",
)
ALLOWED_CHANGES = {
    "rtl/ym2610_golden_profile/stage_c/ym2610_golden_stage_c_sound_adapter.sv",
    "rtl/ym2610_hw0/ym2610_hw0_jt10_acc.v",
    "rtl/ym2610_hw0/ym2610_hw0_jt10_wrapper.sv",
    "rtl/ym2610_hw0/ym2610_hw0_jt12_top.v",
    "rtl/ym2610_hw0/ym2610_hw0_top.sv",
    "rtl/ym2610_player/ym2610_player_core.sv",
    "rtl/ym2610_player/ym2610_player_production_profile.sv",
    "rtl/ym2610_player/ym2610_player_scanner.sv",
    "tools/generate_ym2610_test_vgms.py",
    "tb/ym2610_player/tb_ym2610_player_core.sv",
    "tb/ym2610_player/tb_ym2610b_acc.sv",
    "tb/ym2610_player/run_ym2610b.sh",
    "tb/ym2610_player/audit_ym2610b.py",
    "tb/ym2610_player/elaborate_ym2610b_top.py",
    "hw/ym2610_player/MegaVGMPlayer_YM2610B_Bringup_MiSTer.qpf",
    "hw/ym2610_player/MegaVGMPlayer_YM2610B_Bringup_MiSTer.qsf",
    "hw/ym2610_player/YM2610B_BRINGUP.md",
}


def git(*args: str) -> str:
    return subprocess.run(
        ["git", *args], cwd=ROOT, check=True, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    ).stdout.strip()


def sha256(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    assert git("branch", "--show-current") == "ym2610b-bringup"
    assert git("merge-base", "HEAD", BASE) == BASE
    assert git("rev-parse", "YM2610-2160-beta^{}") == BASE
    assert sha256(ROOT / "rtl/ym2610_player/ym2610_player_pcm_cache.sv") == CACHE_SHA
    assert not git("diff", "--name-only", BASE, "--",
                   "rtl/ym2610_player/ym2610_player_pcm_cache.sv")
    assert not git("diff", "--name-only", BASE, "--", *HANDOFF_FILES)
    assert not git("diff", "--name-only", BASE, "--", "rtl/emu.sv",
                   "rtl/golden_player_shell", "rtl/golden_player_shell_v1_1")
    assert not git("diff", "--name-only", BASE, "--",
                   "hw/ym2610_player/MegaVGMPlayer_YM2610_MiSTer.qpf",
                   "hw/ym2610_player/MegaVGMPlayer_YM2610_MiSTer.qsf",
                   "hw/ym2610_player/files_ym2610_player.qip")

    changed = git("diff", "--name-only", BASE).splitlines()
    assert set(changed) <= ALLOWED_CHANGES, set(changed) - ALLOWED_CHANGES
    assert not any("ym2151" in name.lower() or "segapcm" in name.lower()
                   for name in changed)

    profile = ROOT / "hw/ym2610_player"
    qpf = profile / "MegaVGMPlayer_YM2610B_Bringup_MiSTer.qpf"
    qsf = profile / "MegaVGMPlayer_YM2610B_Bringup_MiSTer.qsf"
    assert qpf.is_file() and qsf.is_file()
    assert 'PROJECT_REVISION = "MegaVGMPlayer_YM2610B_Bringup_MiSTer"' in qpf.read_text()
    qsf_text = qsf.read_text()
    assert qsf_text.count("source MegaVGMPlayer_YM2610_MiSTer.qsf") == 1
    assert qsf_text.count('VERILOG_MACRO "YM2610B_PLAYER=1"') == 1
    assert "QIP_FILE" not in qsf_text
    assert not re.search(r"(?:/Users/|mister-vgm-golden|cache-analysis)", qsf_text)

    production_qip = profile / "files_ym2610_player.qip"
    qip_text = production_qip.read_text()
    paths = re.findall(
        r"\[file join \$::quartus\(qip_path\)\s+([^\s\]]+)", qip_text)
    resolved = [(production_qip.parent / path).resolve() for path in paths]
    assert resolved and all(path.exists() for path in resolved)
    assert len(resolved) == len(set(resolved))
    assert all(str(path).startswith(str(ROOT) + "/") for path in resolved)

    upload = (ROOT / "rtl/golden_player_shell/golden_player_shell_upload.sv").read_text()
    assert ".DDRAM_BASE_ADDR({4'b0011, 25'd0})" in upload

    print(f"YM2610B_CACHE_SHA {CACHE_SHA} result=PASS")
    print("YM2610B_HANDOFF_UNCHANGED files=2 result=PASS")
    print("YM2610B_GOLDEN_SHELL unchanged=1 ddram_base=0x30000000 result=PASS")
    print(f"YM2610B_SOURCE_GRAPH inherited=1 sources={len(resolved)} duplicates=0 absolute=0 result=PASS")
    print("YM2610B_STATIC_AUDIT result=PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
