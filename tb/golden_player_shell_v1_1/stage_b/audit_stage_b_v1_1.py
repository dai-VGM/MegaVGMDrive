#!/usr/bin/env python3
"""Read-only Golden Player Shell v1.1 Stage B migration audit."""

from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[3]
BASE = "750eeaea7d17dd82bd554967605a44996449a1a7"
BRANCH = "golden-player-shell-v1.1-stage-b"
STAGE_A_HW = ROOT / "hw/golden_player_shell_v1_1_stage_a"
STAGE_B_HW = ROOT / "hw/golden_player_shell_v1_1_stage_b"
QIP_NAME = "files_golden_player_shell_v1_1_stage_b.qip"
REVISION = "MegaVGMPlayer_GoldenShell_v1_1_StageB_MiSTer"
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


def protected_metadata():
    path = ROOT / "tb/golden_player_shell/audit_golden_shell.py"
    spec = importlib.util.spec_from_file_location("golden_v1_protection", path)
    require(spec is not None and spec.loader is not None,
            "cannot load protected metadata")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def immutable_and_scope_audit() -> None:
    allowed = (
        "rtl/golden_player_shell_v1_1/profiles/stage_b/",
        "tb/golden_player_shell_v1_1/stage_b/",
        "docs/golden_player_shell_v1_1/stage_b/",
        "hw/golden_player_shell_v1_1_stage_b/",
    )
    changed = run("git", "diff", "--name-only", BASE).splitlines()
    bad = [name for name in changed if not name.startswith(allowed)]
    require(not bad, f"change outside v1.1 Stage B scope: {bad}")

    expected = {
        "ym2610_golden_stage_b_compat.sv":
            "46c11f68a3456ff638ce757c18cdd4a0262995e0bc11e3b923468b8783262115",
        "ym2610_golden_stage_b_profile.sv":
            "ddb7a9e8ad2f4de0a1b5aa467d3eb12246c30edb86672db784340fb0f75db966",
        "ym2610_golden_stage_b_read_adapter.sv":
            "fe23765aa5b90d45b26800704aeba10620b5ae48a99cb825b6de5b0af6aa3b3b",
        "ym2610_golden_stage_b_scanner.sv":
            "fa8643ad830074633502ced52f0795e16e4c007dc4077e49a6421e03605deddb",
    }
    stage_b = ROOT / "rtl/ym2610_golden_profile/stage_b"
    for name, digest in expected.items():
        require(sha256(stage_b / name) == digest,
                f"existing Stage B blob changed: {name}")


def protected_audit() -> None:
    meta = protected_metadata()
    untracked = set(run("git", "ls-files", "--others",
                        "--exclude-standard").splitlines())
    protected = set(meta.PROTECTED_UNTRACKED)
    require(len(protected) == 35 and protected <= untracked,
            "protected 35 untracked set changed")
    allowed = (
        "rtl/golden_player_shell_v1_1/profiles/stage_b/",
        "tb/golden_player_shell_v1_1/stage_b/",
        "docs/golden_player_shell_v1_1/stage_b/",
        "hw/golden_player_shell_v1_1_stage_b/",
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


def qip_sources(path: Path) -> list[Path]:
    sources = []
    for line in path.read_text().splitlines():
        if not FILE_RE.search(line):
            continue
        match = JOIN_RE.search(line)
        require(match is not None, f"non-relative QIP assignment: {line}")
        raw = match.group(1).strip('"')
        require(not raw.startswith("/") and not re.match(r"^[A-Za-z]:", raw),
                f"absolute QIP path: {raw}")
        target = (path.parent / raw).resolve()
        require(target.is_file(), f"missing QIP source: {target}")
        sources.append(target)
    relative = [path.relative_to(ROOT).as_posix() for path in sources]
    require(len(relative) == len(set(relative)), "duplicate local QIP source")
    return sources


def project_audit() -> tuple[int, int]:
    template = (STAGE_A_HW /
        "MegaVGMPlayer_GoldenShell_v1_1_StageA_MiSTer.qsf").read_text()
    expected_qsf = template.replace(
        "files_golden_player_shell_v1_1_stage_a.qip", QIP_NAME)
    qsf = STAGE_B_HW / f"{REVISION}.qsf"
    require(qsf.read_text() == expected_qsf,
            "Stage B QSF differs beyond its QIP assignment")
    for support in ("sys_golden_shell.qip", "sys_golden_shell.tcl"):
        require((STAGE_B_HW / support).read_bytes() ==
                (STAGE_A_HW / support).read_bytes(),
                f"Stage B {support} differs from v1.1 Stage A")
    require(f'PROJECT_REVISION = "{REVISION}"' in
            (STAGE_B_HW / f"{REVISION}.qpf").read_text(),
            "Stage B QPF revision mismatch")

    sources = qip_sources(STAGE_B_HW / QIP_NAME)
    relative = [path.relative_to(ROOT).as_posix() for path in sources]
    expected = [
        "rtl/emu.sv", "rtl/megavgm_video_timing.sv",
        "rtl/megavgm_title_receiver.sv", "rtl/megavgm_font5x7.sv",
        "rtl/megavgm_title_renderer.sv", "rtl/vgm_ddram_backend.sv",
        "rtl/golden_player_shell/golden_player_shell_upload.sv",
        "rtl/ym2610_golden_profile/stage_b/ym2610_golden_stage_b_compat.sv",
        "rtl/ym2610_golden_profile/stage_b/ym2610_golden_stage_b_read_adapter.sv",
        "rtl/ym2610_golden_profile/stage_b/ym2610_golden_stage_b_scanner.sv",
        "rtl/ym2610_golden_profile/stage_b/ym2610_golden_stage_b_profile.sv",
        "rtl/golden_player_shell_v1_1/profiles/stage_b/golden_player_shell_v1_1_stage_b_profile.sv",
        "rtl/golden_player_shell_v1_1/mister_vgm_md_top_v1_1.sv",
    ]
    require(relative == expected, "Stage B local source order/graph mismatch")
    forbidden = (
        "stage_c", "rtl/ym2610_player", "ym2610_hw0", "jt10", "jt12",
        "jt49", "jt51", "jtoutrun", "segapcm", "adpcm-a", "adpcm-b",
        "vgm_loaded_player", "wait_engine", "md_sound_module", "tb/",
    )
    hits = [name for name in relative
            if any(token in name.lower() for token in forbidden)]
    require(not hits, f"forbidden Stage B sources: {hits}")
    require("rtl/golden_player_shell/mister_vgm_md_top_compat.sv" not in relative,
            "v1.0 shim entered Stage B graph")

    modules: dict[str, str] = {}
    duplicates = []
    public_shims = 0
    profiles = 0
    for path, name in zip(sources, relative):
        for module in MODULE_RE.findall(path.read_text(errors="replace")):
            if module in modules:
                duplicates.append(module)
            modules[module] = name
            public_shims += module == "mister_vgm_md_top"
            profiles += module == "golden_player_shell_v1_1_profile"
    require(not duplicates, f"duplicate modules: {duplicates}")
    require(public_shims == 1 and profiles == 1,
            f"public binding mismatch shim={public_shims} profile={profiles}")
    require(modules.get("mister_vgm_md_top") ==
            "rtl/golden_player_shell_v1_1/mister_vgm_md_top_v1_1.sv",
            "wrong public shim binding")
    require(modules.get("ym2610_golden_stage_b_scanner") ==
            "rtl/ym2610_golden_profile/stage_b/ym2610_golden_stage_b_scanner.sv",
            "scanner is not the existing source")
    require(modules.get("ym2610_golden_stage_b_read_adapter") ==
            "rtl/ym2610_golden_profile/stage_b/ym2610_golden_stage_b_read_adapter.sv",
            "read adapter is not the existing source")
    return len(sources), len(modules)


def contract_audit() -> None:
    wrapper = (ROOT /
        "rtl/golden_player_shell_v1_1/profiles/stage_b/golden_player_shell_v1_1_stage_b_profile.sv").read_text()
    shim = (ROOT /
        "rtl/golden_player_shell_v1_1/mister_vgm_md_top_v1_1.sv").read_text()
    emu = (ROOT / "rtl/emu.sv").read_text()
    require("ym2610_golden_stage_a #(\n" in wrapper and
            ") stage_b_core (" in wrapper,
            "existing Stage B public profile is not directly instantiated")
    require("module ym2610_golden_stage_b_scanner" not in wrapper and
            "module ym2610_golden_stage_b_read_adapter" not in wrapper,
            "Stage B core was copied into the wrapper")
    require("profile_audio_enable <= 1'b0;" in wrapper and
            "assign profile_audio_l = 16'sd0;" in wrapper and
            "assign profile_audio_r = 16'sd0;" in wrapper and
            "assign profile_audio_sample_valid = 1'b0;" in wrapper,
            "Stage B constant-zero audio contract missing")
    require("assign audio_gate_open = profile_audio_enable;" in shim and
            "assign audio_muted = !profile_audio_enable;" in shim,
            "v1.1 shim gate contract changed")
    require("(audio_gate_open && !audio_muted) ? audio_l_safe : 16'sd0" in emu and
            "assign AUDIO_L = audio_l_final;" in emu and
            "assign AUDIO_R = audio_r_final;" in emu,
            "stable emu final audio contract changed")


def no_artifacts() -> None:
    roots = [ROOT / "rtl/golden_player_shell_v1_1/profiles/stage_b",
             ROOT / "tb/golden_player_shell_v1_1/stage_b",
             ROOT / "docs/golden_player_shell_v1_1/stage_b", STAGE_B_HW]
    bad_names = {"db", "incremental_db", "output_files", "__pycache__"}
    bad_suffixes = {".rbf", ".sof", ".rpt", ".vcd", ".fst", ".wav", ".raw", ".log"}
    found = [path for root in roots for path in root.rglob("*")
             if path.name in bad_names or path.suffix.lower() in bad_suffixes]
    require(not found, f"candidate artifacts present: {found}")


def main() -> int:
    require(run("git", "branch", "--show-current") == BRANCH, "wrong branch")
    require(run("git", "merge-base", "--is-ancestor", BASE, "HEAD") == "",
            "requested base is not an ancestor")
    immutable_and_scope_audit()
    protected_audit()
    contract_audit()
    sources, modules = project_audit()
    manifest = json.loads((ROOT /
        "docs/golden_player_shell_v1_1/stage_b/reuse_manifest.json").read_text())
    require(manifest["status"] == "hardware_validation_pending",
            "Stage B candidate was promoted")
    require(manifest["v1_1_audio_lab_software_reset_retrigger"] == "not_recorded",
            "unverified Audio Lab Reset result was promoted")
    no_artifacts()
    print("V1_1_STAGE_B_AUDIT v1_0=IMMUTABLE v1_1_core=IMMUTABLE stage_abc=IMMUTABLE")
    print(f"V1_1_STAGE_B_AUDIT sources={sources} modules={modules} scanner=1 reader=1 shim_v1_1=1 shim_v1_0=0")
    print("V1_1_STAGE_B_AUDIT qsf=NORMALIZED qip=RELATIVE duplicate=0 forbidden=0 copy_fork=0")
    print("V1_1_STAGE_B_AUDIT protected=35 Sacred=PASS stash=PASS artifacts=0")
    print("GOLDEN_SHELL_V1_1_STAGE_B_STATIC_AUDIT PASS")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AuditError as error:
        print(f"GOLDEN_SHELL_V1_1_STAGE_B_STATIC_AUDIT FAIL: {error}",
              file=sys.stderr)
        raise SystemExit(1)
