#!/usr/bin/env python3
"""Static audit for the dedicated YM2610B bring-up revision."""

from __future__ import annotations

import hashlib
import pathlib
import re
import subprocess


ROOT = pathlib.Path(__file__).resolve().parents[2]
BASE = "1ec8b7f5c6a085f7a00ff2dd3bf0d1476e2fe0c1"
BRINGUP_COMMIT = "49c88dd3a9c9259d19bee67e95eb4684f1eda436"
METAL_SLUG_LAB_COMMIT = "9e71694800076a308a6aca1e969ca0bb9adaabec"
DADDY_MULK_BASE = "0bfed9b56d7e2a42aa0857f4a315d51564604a73"
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
    "rtl/genesis_audio/jt10_ym2610/adpcm/jt10_adpcm_drvB.v",
    "rtl/ym2610_player/ym2610_player_core.sv",
    "rtl/ym2610_player/ym2610_player_compat.sv",
    "rtl/ym2610_player/ym2610_player_pcm_cache.sv",
    "rtl/ym2610_player/ym2610_player_production_profile.sv",
    "rtl/ym2610_player/ym2610_player_scanner.sv",
    "tools/generate_ym2610_test_vgms.py",
    "tb/ym2610_player/tb_ym2610_player_core.sv",
    "tb/ym2610_player/tb_ym2610_player_scanner.sv",
    "tb/ym2610_player/tb_gf09_pcm_cache_replacement.sv",
    "tb/ym2610_player/tb_ym2610_adpcma_24bit_cache.sv",
    "tb/ym2610_player/run_adpcma_24bit_cache.sh",
    "tb/ym2610_player/run_scanner.sh",
    "tb/ym2610_player/tb_ym2610b_acc.sv",
    "tb/ym2610_player/run_ym2610b.sh",
    "tb/ym2610_player/audit_ym2610b.py",
    "tb/ym2610_player/elaborate_ym2610b_top.py",
    "tb/ym2610_player/README.md",
    "tb/ym2610_player/run_ms_adpcmb_repeat_boundary.sh",
    "tb/ym2610_player/tb_ms_adpcmb_boundary_pending_repro.sv",
    "tb/ym2610_player/run_daddy_mulk_adpcmb_startup.sh",
    "tb/ym2610_player/tb_daddy_mulk_adpcmb_startup.sv",
    "tools/inspect_ym2610_vgm.py",
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
    branch = git("branch", "--show-current")
    assert branch in ("ym2610b-bringup", "ym2610b-adpcma-24bit",
                      "ym2610b-adpcmb-24bit",
                      "ym2610b-metal-slug-first-reject-uart-lab",
                      "ym2610b-daddy-mulk-adpcmb-startup")
    if branch == "ym2610b-metal-slug-first-reject-uart-lab":
        audit_base = METAL_SLUG_LAB_COMMIT
    elif branch == "ym2610b-daddy-mulk-adpcmb-startup":
        audit_base = DADDY_MULK_BASE
    else:
        audit_base = BASE
    assert git("merge-base", "HEAD", BASE) == BASE
    assert git("rev-parse", "YM2610-2160-beta^{}") == BASE
    cache_sha = sha256(ROOT / "rtl/ym2610_player/ym2610_player_pcm_cache.sv")
    if branch == "ym2610b-bringup":
        assert cache_sha == CACHE_SHA
        assert not git("diff", "--name-only", BASE, "--",
                       "rtl/ym2610_player/ym2610_player_pcm_cache.sv")
    else:
        assert git("merge-base", "HEAD", BRINGUP_COMMIT) == BRINGUP_COMMIT
        cache_text = (ROOT / "rtl/ym2610_player/ym2610_player_pcm_cache.sv").read_text()
        for contract in ("protected_slots", "retired2_a_current_slot",
                         "prepared_a_current_slot", "replace_ptr"):
            assert contract in cache_text
    assert not git("diff", "--name-only", BASE, "--", *HANDOFF_FILES)
    assert not git("diff", "--name-only", audit_base, "--", "rtl/emu.sv",
                   "rtl/golden_player_shell", "rtl/golden_player_shell_v1_1")
    assert not git("diff", "--name-only", BASE, "--",
                   "hw/ym2610_player/MegaVGMPlayer_YM2610_MiSTer.qpf",
                   "hw/ym2610_player/MegaVGMPlayer_YM2610_MiSTer.qsf",
                   "hw/ym2610_player/files_ym2610_player.qip")

    changed = git("diff", "--name-only", audit_base).splitlines()
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

    print(f"YM2610B_CACHE_SHA {cache_sha} slot_protection=1 result=PASS")
    print("YM2610B_HANDOFF_UNCHANGED files=2 result=PASS")
    print("YM2610B_GOLDEN_SHELL unchanged=1 ddram_base=0x30000000 result=PASS")
    print(f"YM2610B_SOURCE_GRAPH inherited=1 sources={len(resolved)} duplicates=0 absolute=0 result=PASS")
    print("YM2610B_STATIC_AUDIT result=PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
