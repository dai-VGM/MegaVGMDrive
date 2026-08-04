#!/usr/bin/env python3
"""Read-only Golden Player Shell v1.1 candidate audit."""

from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
BASE = "ee27173d15665330ef38bf8cf9f9a3c803be75fa"
BRANCH = "golden-player-shell-v1.1-audio-contract"
V1_HW = ROOT / "hw/ym2610_golden_shell"
STAGE_A_HW = ROOT / "hw/golden_player_shell_v1_1_stage_a"
LAB_HW = ROOT / "hw/golden_player_shell_v1_1_audio_lab"
JOIN_RE = re.compile(r"\[file join \$::quartus\(qip_path\)\s+([^\]\s]+)\s*\]")
FILE_RE = re.compile(r"-name\s+(?:SYSTEMVERILOG_FILE|VERILOG_FILE)")
MODULE_RE = re.compile(r"^\s*module\s+([A-Za-z_][A-Za-z0-9_$]*)", re.MULTILINE)


class AuditError(RuntimeError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AuditError(message)


def run(*args: str, binary: bool = False) -> str | bytes:
    result = subprocess.run(args, cwd=ROOT, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, check=False)
    if result.returncode:
        raise AuditError(f"command failed: {' '.join(args)}\n" +
                         result.stderr.decode(errors="replace"))
    return result.stdout if binary else result.stdout.decode().strip()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def stage_a_metadata():
    path = ROOT / "tb/golden_player_shell/audit_golden_shell.py"
    spec = importlib.util.spec_from_file_location("golden_v1_audit", path)
    require(spec is not None and spec.loader is not None,
            "cannot load v1.0 protected metadata")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def immutable_audit() -> None:
    immutable = [
        "AGENTS.md", "rtl/emu.sv", "rtl/golden_player_shell",
        "hw/ym2610_golden_shell", "tb/golden_player_shell",
        "docs/golden_player_shell", "rtl/ym2610_golden_profile",
        "tb/ym2610_golden_profile", "hw/ym2610_golden_shell_stage_b",
        "hw/ym2610_golden_shell_stage_c", "docs/ym2610_golden_shell_stage_b",
        "docs/ym2610_golden_shell_stage_c", "rtl/ym2610_player",
        "rtl/ym2610_hw0", "hw/ym2610_hw0", "files.qip",
        "VGM_MD_MiSTer.qsf", "rtl/genesis_audio/jt10_ym2610",
        "rtl/genesis_audio/jt12", "rtl/genesis_audio/jt49", "tb/jt10_pinned"
    ]
    changed = run("git", "diff", "--name-only", BASE, "--", *immutable)
    require(not changed, f"v1.0/stage/production files changed:\n{changed}")


def protected_audit() -> None:
    meta = stage_a_metadata()
    untracked = set(run("git", "ls-files", "--others",
                        "--exclude-standard").splitlines())
    protected = set(meta.PROTECTED_UNTRACKED)
    require(len(protected) == 35 and protected <= untracked,
            "protected 35 untracked set changed")
    allowed = (
        "rtl/golden_player_shell_v1_1/",
        "tb/golden_player_shell_v1_1/",
        "docs/golden_player_shell_v1_1/",
        "hw/golden_player_shell_v1_1_stage_a/",
        "hw/golden_player_shell_v1_1_audio_lab/",
    )
    unexpected = sorted(name for name in untracked - protected
                        if not name.startswith(allowed))
    require(not unexpected, f"unexpected untracked files: {unexpected}")
    for name, expected in meta.PROTECTED_UNTRACKED.items():
        path = ROOT / name
        stat = path.stat()
        actual = (sha256(path), stat.st_size, int(stat.st_mtime), stat.st_ino)
        require(actual == expected, f"protected file changed: {name}")
    expected_stash = [
        "stash@{0}: On ym2610-family-bringup: Preserve YM2610 HW-0 amplitude audit",
        "stash@{1}: On segapcm-ddr-header-clock-only: Preserve pre-YM2203 first-load diagnostics",
        "stash@{2}: On ddram-read-hardening: park remaining rtl tb before reverting c06e2a4",
        "stash@{3}: On ddram-read-hardening: park backend changes before reverting c06e2a4",
    ]
    require(run("git", "stash", "list").splitlines() == expected_stash,
            "stash list changed")
    patch = run("git", "stash", "show", "-p", "stash@{0}", binary=True)
    require(hashlib.sha256(patch).hexdigest() ==
            "493adffd4ae4dd2083e1787466caf5b27e5c9a52c635903d704291aa672dc11f",
            "amplitude stash patch changed")


def qip_sources(qip: Path) -> list[Path]:
    sources = []
    for line in qip.read_text().splitlines():
        if not FILE_RE.search(line):
            continue
        match = JOIN_RE.search(line)
        require(match is not None, f"non-relative QIP assignment: {line}")
        raw = match.group(1).strip('"')
        require(not raw.startswith("/") and not re.match(r"^[A-Za-z]:", raw),
                f"absolute QIP path: {raw}")
        target = (qip.parent / raw).resolve()
        require(target.is_file(), f"missing QIP source: {target}")
        sources.append(target)
    rel = [path.relative_to(ROOT).as_posix() for path in sources]
    require(len(rel) == len(set(rel)), f"duplicate QIP source: {qip}")
    return sources


def project_audit(hw: Path, revision: str, qip_name: str,
                  profile_name: str) -> tuple[int, int]:
    template = (V1_HW /
        "MegaVGMPlayer_YM2610_GoldenShell_MiSTer.qsf").read_text()
    qsf_path = hw / f"{revision}.qsf"
    expected = template.replace("files_ym2610_golden_shell.qip", qip_name)
    require(qsf_path.read_text() == expected,
            f"{revision} QSF is not normalized to v1.0 Stage A")
    require((hw / "sys_golden_shell.qip").read_bytes() ==
            (V1_HW / "sys_golden_shell.qip").read_bytes(),
            f"{revision} system QIP differs")
    require((hw / "sys_golden_shell.tcl").read_bytes() ==
            (V1_HW / "sys_golden_shell.tcl").read_bytes(),
            f"{revision} system Tcl differs")
    qpf = (hw / f"{revision}.qpf").read_text()
    require(f'PROJECT_REVISION = "{revision}"' in qpf,
            f"{revision} QPF mismatch")

    sources = qip_sources(hw / qip_name)
    rel = [path.relative_to(ROOT).as_posix() for path in sources]
    expected_sources = [
        "rtl/emu.sv", "rtl/megavgm_video_timing.sv",
        "rtl/megavgm_title_receiver.sv", "rtl/megavgm_font5x7.sv",
        "rtl/megavgm_title_renderer.sv", "rtl/vgm_ddram_backend.sv",
        "rtl/golden_player_shell/golden_player_shell_upload.sv",
        "rtl/golden_player_shell_v1_1/mister_vgm_md_top_v1_1.sv",
        f"rtl/golden_player_shell_v1_1/profiles/{profile_name}",
    ]
    require(rel == expected_sources, f"{revision} source order/graph mismatch")
    forbidden = ("stage_b", "stage_c", "ym2610_player", "ym2610_hw0",
                 "jt10", "jt12", "jt49", "jt51", "jtoutrun", "segapcm",
                 "adpcm", "testbench", "tb/")
    hits = [name for name in rel if any(token in name.lower() for token in forbidden)]
    require(not hits, f"forbidden source in {revision}: {hits}")
    require("rtl/golden_player_shell/mister_vgm_md_top_compat.sv" not in rel,
            f"v1.0 shim entered {revision}")

    modules: dict[str, str] = {}
    duplicates = []
    for path, name in zip(sources, rel):
        for module in MODULE_RE.findall(path.read_text(errors="replace")):
            if module in modules:
                duplicates.append(module)
            modules[module] = name
    require(not duplicates, f"duplicate modules in {revision}: {duplicates}")
    require(modules.get("mister_vgm_md_top") ==
            "rtl/golden_player_shell_v1_1/mister_vgm_md_top_v1_1.sv",
            f"wrong public shim binding in {revision}")
    require(modules.get("golden_player_shell_v1_1_profile") ==
            f"rtl/golden_player_shell_v1_1/profiles/{profile_name}",
            f"wrong profile binding in {revision}")
    require(len(sources) == 9 and len(modules) == 9,
            f"unexpected graph size in {revision}")
    return len(sources), len(modules)


def contract_audit() -> None:
    old = (ROOT / "rtl/golden_player_shell/mister_vgm_md_top_compat.sv").read_text()
    emu = (ROOT / "rtl/emu.sv").read_text()
    new = (ROOT / "rtl/golden_player_shell_v1_1/mister_vgm_md_top_v1_1.sv").read_text()
    stage_a = (ROOT / "rtl/golden_player_shell_v1_1/profiles/golden_player_shell_v1_1_stage_a_profile.sv").read_text()
    require("assign audio_gate_open = 1'b0;" in old and
            "assign audio_muted = 1'b1;" in old,
            "v1.0 root-cause constants changed")
    require("(audio_gate_open && !audio_muted) ? audio_l_safe : 16'sd0" in emu and
            "assign AUDIO_L = audio_l_final;" in emu and
            "assign AUDIO_R = audio_r_final;" in emu,
            "stable emu final gate contract changed")
    require("assign audio_gate_open = profile_audio_enable;" in new and
            "assign audio_muted = !profile_audio_enable;" in new,
            "v1.1 single-authority mapping missing")
    require("wire signed [15:0]        profile_audio_l;" in new and
            "wire signed [15:0]        profile_audio_r;" in new,
            "signed 16-bit ABI missing")
    require("profile_audio_enable <= 1'b0;" in stage_a and
            "assign profile_audio_l = 16'sd0;" in stage_a and
            "assign profile_audio_sample_valid = 1'b0;" in stage_a,
            "Stage A inert audio contract missing")


def no_artifacts() -> None:
    bad_names = {"db", "incremental_db", "output_files", "__pycache__"}
    roots = [ROOT / "rtl/golden_player_shell_v1_1",
             ROOT / "tb/golden_player_shell_v1_1",
             ROOT / "docs/golden_player_shell_v1_1", STAGE_A_HW, LAB_HW]
    found = []
    for base in roots:
        found.extend(path for path in base.rglob("*")
                     if path.name in bad_names or
                     path.suffix.lower() in {".rbf", ".sof", ".rpt", ".vcd", ".fst", ".wav", ".raw"})
    require(not found, f"candidate artifacts present: {found}")


def main() -> int:
    require(run("git", "branch", "--show-current") == BRANCH, "wrong branch")
    require(run("git", "merge-base", "--is-ancestor", BASE, "HEAD") == "",
            "requested base is not an ancestor")
    immutable_audit()
    protected_audit()
    contract_audit()
    stage_sources, stage_modules = project_audit(
        STAGE_A_HW, "MegaVGMPlayer_GoldenShell_v1_1_StageA_MiSTer",
        "files_golden_player_shell_v1_1_stage_a.qip",
        "golden_player_shell_v1_1_stage_a_profile.sv")
    lab_sources, lab_modules = project_audit(
        LAB_HW, "MegaVGMPlayer_GoldenShell_v1_1_AudioLab_MiSTer",
        "files_golden_player_shell_v1_1_audio_lab.qip",
        "golden_player_shell_v1_1_audio_lab_profile.sv")
    manifest = json.loads((ROOT / "docs/golden_player_shell_v1_1/stable_source_manifest.json").read_text())
    require(manifest["status"] == "hardware_validation_pending",
            "candidate manifest was promoted")
    no_artifacts()
    print("GOLDEN_SHELL_V1_1_AUDIT v1_0=IMMUTABLE stage_abc=IMMUTABLE root_cause=CONFIRMED")
    print(f"GOLDEN_SHELL_V1_1_AUDIT stage_a_sources={stage_sources} modules={stage_modules} shim=1 profile=1")
    print(f"GOLDEN_SHELL_V1_1_AUDIT audio_lab_sources={lab_sources} modules={lab_modules} shim=1 profile=1")
    print("GOLDEN_SHELL_V1_1_AUDIT qsf=NORMALIZED qip=RELATIVE duplicates=0 forbidden=0 v1_0_shim=0")
    print("GOLDEN_SHELL_V1_1_AUDIT protected=35 Sacred=PASS stash=PASS artifacts=0")
    print("GOLDEN_SHELL_V1_1_STATIC_AUDIT PASS")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AuditError as error:
        print(f"GOLDEN_SHELL_V1_1_STATIC_AUDIT FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
