#!/usr/bin/env python3
"""Static safety/source-graph audit for the Metal Slug UART lab."""

from __future__ import annotations

import argparse
import pathlib
import re
import subprocess


ROOT = pathlib.Path(__file__).resolve().parents[2]
BASE = "c865f7dee7cfe7080309e3c571b207b089f2df8c"
MACRO = "YM2610B_METAL_SLUG_REJECT_UART_LAB"
REVISION = "MegaVGMPlayer_YM2610B_MetalSlugRejectSerial_MiSTer"
HW = ROOT / "hw/ym2610_player"
QPF = HW / f"{REVISION}.qpf"
QSF = HW / f"{REVISION}.qsf"
PROD_B_QSF = HW / "MegaVGMPlayer_YM2610B_Bringup_MiSTer.qsf"
PROD_QSF = HW / "MegaVGMPlayer_YM2610_MiSTer.qsf"
PROD_QIP = HW / "files_ym2610_player.qip"
OBSERVER = ROOT / "rtl/ym2610_player_lab/ym2610b_metal_slug_reject_serial_observer.sv"
GUARD = HW / "check_metal_slug_reject_ddram_base.tcl"

PASSIVE_TAPS = {
    "rtl/emu.sv",
    "rtl/golden_player_shell_v1_1/mister_vgm_md_top_v1_1.sv",
    "rtl/ym2610_player/ym2610_player_production_profile.sv",
    "rtl/ym2610_player/ym2610_player_core.sv",
    "rtl/ym2610_player/ym2610_player_bus.sv",
    "rtl/ym2610_player/ym2610_player_pcm_cache.sv",
}

LAB_ONLY = {
    f"hw/ym2610_player/{REVISION}.qpf",
    f"hw/ym2610_player/{REVISION}.qsf",
    "hw/ym2610_player/check_metal_slug_reject_ddram_base.tcl",
    "hw/ym2610_player/README_METAL_SLUG_REJECT_SERIAL_LAB.md",
    "rtl/ym2610_player_lab/ym2610b_metal_slug_reject_serial_observer.sv",
    "tb/ym2610_player/audit_metal_slug_reject_serial_lab.py",
    "tb/ym2610_player/run_metal_slug_reject_serial_lab.sh",
    "tb/ym2610_player/tb_ym2610b_metal_slug_reject_serial_observer.sv",
}


def git(*args: str) -> str:
    return subprocess.run(
        ["git", *args], cwd=ROOT, check=True, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    ).stdout


def qip_sources(path: pathlib.Path) -> list[pathlib.Path]:
    pattern = re.compile(r"\[file join \$::quartus\(qip_path\)\s+([^\s\]]+)")
    result: list[pathlib.Path] = []
    for raw in pattern.findall(path.read_text()):
        assert not pathlib.PurePosixPath(raw).is_absolute(), raw
        resolved = (path.parent / raw).resolve()
        assert ROOT in resolved.parents and resolved.is_file(), resolved
        if resolved.suffix.lower() in (".v", ".sv"):
            result.append(resolved)
    return result


def macro_off_projection(text: str) -> str:
    output: list[str] = []
    mode = "copy"
    for line in text.splitlines(keepends=True):
        stripped = line.strip()
        if mode == "copy" and stripped == f"`ifdef {MACRO}":
            mode = "skip_true"
        elif mode == "skip_true" and stripped == "`else":
            mode = "copy_false"
        elif mode in ("skip_true", "copy_false") and stripped == "`endif":
            mode = "copy"
        elif mode in ("copy", "copy_false"):
            output.append(line)
    assert mode == "copy", "unterminated lab macro block"
    return "".join(output)


def normalized_lines(text: str) -> list[str]:
    return [line.rstrip() for line in text.splitlines() if line.strip()]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--emit-sources", action="store_true")
    parser.add_argument("--emit-production-sources", action="store_true")
    args = parser.parse_args()

    sources = qip_sources(PROD_QIP)
    if args.emit_sources or args.emit_production_sources:
        for source in sources:
            print(source)
        if args.emit_sources:
            print(OBSERVER)
        return 0

    assert subprocess.run(
        ["git", "merge-base", "--is-ancestor", BASE, "HEAD"], cwd=ROOT
    ).returncode == 0, "HEAD does not include requested base"

    assert PROD_QSF.read_bytes() == subprocess.check_output(
        ["git", "show", f"{BASE}:{PROD_QSF.relative_to(ROOT)}"], cwd=ROOT
    ), "production QSF changed"
    assert PROD_B_QSF.read_bytes() == subprocess.check_output(
        ["git", "show", f"{BASE}:{PROD_B_QSF.relative_to(ROOT)}"], cwd=ROOT
    ), "YM2610B production QSF changed"
    assert PROD_QIP.read_bytes() == subprocess.check_output(
        ["git", "show", f"{BASE}:{PROD_QIP.relative_to(ROOT)}"], cwd=ROOT
    ), "production QIP changed"

    changed = set(git("diff", "--name-only", BASE).splitlines())
    changed |= set(git("ls-files", "--others", "--exclude-standard").splitlines())
    assert changed <= PASSIVE_TAPS | LAB_ONLY, sorted(changed - PASSIVE_TAPS - LAB_ONLY)
    assert LAB_ONLY <= changed, sorted(LAB_ONLY - changed)

    for relative in PASSIVE_TAPS:
        current = (ROOT / relative).read_text()
        baseline = git("show", f"{BASE}:{relative}")
        assert normalized_lines(macro_off_projection(current)) == normalized_lines(baseline), (
            f"lab-macro-off projection changed production behavior: {relative}"
        )
        assert not re.findall(
            r"\bu_[A-Za-z_][A-Za-z0-9_$]*(?:\.[A-Za-z_][A-Za-z0-9_$]*)+",
            current,
        ), f"XMR in {relative}"

    qpf = QPF.read_text()
    qsf = QSF.read_text()
    assert f'PROJECT_REVISION = "{REVISION}"' in qpf
    assert qsf.count("source MegaVGMPlayer_YM2610B_Bringup_MiSTer.qsf") == 1
    assert qsf.count("source check_metal_slug_reject_ddram_base.tcl") == 1
    assert qsf.count(f'VERILOG_MACRO "{MACRO}=1"') == 1
    assert qsf.count(OBSERVER.name) == 1
    assert "QIP_FILE" not in qsf and "set_location_assignment" not in qsf
    assert not re.search(r"(?:/Users/|mister-vgm-golden|cache-analysis)", qsf)
    assert PROD_B_QSF.read_text().count("source MegaVGMPlayer_YM2610_MiSTer.qsf") == 1
    assert PROD_B_QSF.read_text().count('VERILOG_MACRO "YM2610B_PLAYER=1"') == 1

    assert len(sources) == len(set(sources)), "duplicate source paths"
    module_owners: dict[str, pathlib.Path] = {}
    for source in sources + [OBSERVER]:
        for module in re.findall(
            r"^\s*module\s+([A-Za-z_][A-Za-z0-9_$]*)",
            source.read_text(errors="ignore"), re.MULTILINE,
        ):
            assert module not in module_owners, (
                f"duplicate module {module}: {module_owners[module]} and {source}"
            )
            module_owners[module] = source

    qip_text = PROD_QIP.read_text()
    for forbidden in (
        "rtl/ym2610_player/emu.sv",
        "ym2610_player_reset_fence.sv",
        "ym2610_player_diagnostics.sv",
        "ym2610_player_debug_renderer.sv",
        "ym2610_player_video.sv",
    ):
        assert forbidden not in qip_text, f"alternate architecture: {forbidden}"

    upload = (ROOT / "rtl/golden_player_shell/golden_player_shell_upload.sv").read_text()
    assert upload.count(".DDRAM_BASE_ADDR({4'b0011, 25'd0})") == 1
    assert upload.count(
        ".SEGAPCM_ROM_BASE_ADDR({4'b0011, 25'd0} + 29'h0010_0000)"
    ) == 1
    assert (0x3 << 25) << 3 == 0x30000000
    guard = GUARD.read_text()
    assert "0x30000000" in guard and "DDRAM_BASE_ADDR" in guard

    observer = OBSERVER.read_text()
    assert "115_200" in observer and "CLKS_PER_BIT" in observer
    assert "prev_adpcma_logical" in observer and "prev_adpcmb_logical" in observer
    assert "frozen" in observer and "capture && !frozen" in observer
    assert "reset(reset || download_active)" in (
        ROOT / "rtl/ym2610_player/ym2610_player_production_profile.sv"
    ).read_text()

    print(f"METAL_SLUG_BASE includes={BASE} result=PASS")
    print("METAL_SLUG_PRODUCTION_QSF inherited=1 unchanged=1 result=PASS")
    print("METAL_SLUG_GOLDEN_SHELL macro_off_identical=1 result=PASS")
    print("METAL_SLUG_DDRAM_BASE physical=0x30000000 result=PASS")
    print(f"METAL_SLUG_SOURCE_GRAPH sources={len(sources)+1} duplicates=0 xmr=0 alternate_backend=0 alternate_reset=0 result=PASS")
    print("METAL_SLUG_STATIC_AUDIT result=PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
