#!/usr/bin/env python3
"""Read-only Stage B project, provenance, and source-graph audit."""

from __future__ import annotations

import hashlib
import importlib.util
from pathlib import Path
import re
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[3]
BASE = "35d99c23852a1290257021176e1fe5bc61446726"
BRANCH = "ym2610-golden-shell-stage-b"
STAGE_A_HW = ROOT / "hw/ym2610_golden_shell"
STAGE_B_HW = ROOT / "hw/ym2610_golden_shell_stage_b"


class AuditError(RuntimeError):
    pass


def run(*args: str, binary: bool = False) -> str | bytes:
    result = subprocess.run(args, cwd=ROOT, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, check=False)
    if result.returncode:
        raise AuditError(f"command failed: {' '.join(args)}\n" +
                         result.stderr.decode(errors="replace"))
    return result.stdout if binary else result.stdout.decode().strip()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AuditError(message)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def load_stage_a_audit():
    path = ROOT / "tb/golden_player_shell/audit_golden_shell.py"
    spec = importlib.util.spec_from_file_location("golden_stage_a_audit", path)
    require(spec is not None and spec.loader is not None, "cannot load Stage A audit")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def immutable_audit(stage_a) -> None:
    immutable = [
        "rtl/golden_player_shell", "hw/ym2610_golden_shell",
        "tb/golden_player_shell",
        "docs/golden_player_shell/stable_source_manifest.json",
        "docs/golden_player_shell/IMMUTABLE_CONTRACT.md",
    ]
    changed = run("git", "diff", "--name-only", BASE, "--", *immutable)
    require(not changed, f"Stage A immutable paths changed:\n{changed}")
    stage_a.stable_blob_audit()
    stage_a.qsf_equivalence_audit()
    stage_a.protected_tracked_paths_audit()
    stage_a.manifest_audit()


def protected_audit(stage_a) -> None:
    untracked = set(run("git", "ls-files", "--others", "--exclude-standard").splitlines())
    protected = set(stage_a.PROTECTED_UNTRACKED)
    require(protected <= untracked, "one or more protected untracked files disappeared")
    extras = untracked - protected
    allowed_prefixes = (
        "rtl/ym2610_golden_profile/stage_b/",
        "tb/ym2610_golden_profile/stage_b/",
        "hw/ym2610_golden_shell_stage_b/",
        "docs/ym2610_golden_shell_stage_b/",
    )
    require(all(item.startswith(allowed_prefixes) for item in extras),
            f"unexpected untracked files: {sorted(extras)}")
    for name, expected in stage_a.PROTECTED_UNTRACKED.items():
        path = ROOT / name
        stat = path.stat()
        actual = (sha256(path), stat.st_size, int(stat.st_mtime), stat.st_ino)
        require(actual == expected, f"protected file changed: {name}")
    stash = run("git", "stash", "list").splitlines()
    require(stash and "Preserve YM2610 HW-0 amplitude audit" in stash[0],
            "amplitude stash is no longer stash@{0}")
    patch = run("git", "stash", "show", "-p", "stash@{0}", binary=True)
    require(hashlib.sha256(patch).hexdigest() ==
            "493adffd4ae4dd2083e1787466caf5b27e5c9a52c635903d704291aa672dc11f",
            "amplitude stash patch changed")


JOIN_RE = re.compile(r"\[file join \$::quartus\(qip_path\)\s+\"?([^\"\]\s]+)\"?\s*\]")
FILE_RE = re.compile(r"-name\s+(VERILOG_FILE|SYSTEMVERILOG_FILE|VHDL_FILE|SDC_FILE|QIP_FILE)")


def walk_qip(path: Path, qips: set[Path], sources: list[Path]) -> None:
    path = path.resolve()
    require(path.exists(), f"missing QIP {path}")
    require(path not in qips, f"duplicate QIP {path.relative_to(ROOT)}")
    qips.add(path)
    for line in path.read_text(errors="replace").splitlines():
        kind = FILE_RE.search(line)
        if not kind:
            continue
        match = JOIN_RE.search(line)
        require(match is not None, f"non-relative QIP assignment: {line}")
        raw = match.group(1)
        require(not raw.startswith("/") and not re.match(r"^[A-Za-z]:", raw),
                f"absolute path in QIP: {raw}")
        target = (path.parent / raw).resolve()
        require(target.exists(), f"missing source {target}")
        if kind.group(1) == "QIP_FILE":
            walk_qip(target, qips, sources)
        else:
            sources.append(target)


def project_audit() -> tuple[int, int]:
    stage_a_qsf = STAGE_A_HW / "MegaVGMPlayer_YM2610_GoldenShell_MiSTer.qsf"
    stage_b_qsf = STAGE_B_HW / "MegaVGMPlayer_YM2610_GoldenShell_StageB_MiSTer.qsf"
    expected_qsf = stage_a_qsf.read_text().replace(
        "files_ym2610_golden_shell.qip",
        "files_ym2610_golden_shell_stage_b.qip",
    )
    require(stage_b_qsf.read_text() == expected_qsf,
            "Stage B QSF differs beyond its profile QIP assignment")
    require((STAGE_B_HW / "sys_golden_shell.tcl").read_bytes() ==
            (STAGE_A_HW / "sys_golden_shell.tcl").read_bytes(),
            "system Tcl path adapter differs from Stage A")
    require((STAGE_B_HW / "sys_golden_shell.qip").read_bytes() ==
            (STAGE_A_HW / "sys_golden_shell.qip").read_bytes(),
            "system QIP path adapter differs from Stage A")

    qpf = (STAGE_B_HW /
           "MegaVGMPlayer_YM2610_GoldenShell_StageB_MiSTer.qpf").read_text()
    require('PROJECT_REVISION = "MegaVGMPlayer_YM2610_GoldenShell_StageB_MiSTer"' in qpf,
            "Stage B revision mismatch")

    qips: set[Path] = set()
    sources: list[Path] = []
    starts = [
        STAGE_B_HW / "sys_golden_shell.qip",
        ROOT / "sys/pll_hdmi.qip", ROOT / "sys/pll_audio.qip",
        ROOT / "sys/pll_cfg.qip",
        STAGE_B_HW / "files_ym2610_golden_shell_stage_b.qip",
    ]
    for start in starts:
        walk_qip(start, qips, sources)
    relative = [item.relative_to(ROOT).as_posix() for item in sources]
    require(len(relative) == len(set(relative)), "duplicate source in Stage B graph")
    forbidden = (
        "rtl/ym2610_player/", "ym2610_hw0", "jt10", "jt12", "jt49",
        "jt51", "jtoutrun", "segapcm", "vgm_loaded_player",
        "vgm_region_player", "vgm_file_loader", "md_sound_module", "/tb/",
    )
    hits = [name for name in relative if any(token in name.lower() for token in forbidden)]
    require(not hits, f"forbidden Stage B sources: {hits}")

    local_qip = (STAGE_B_HW / "files_ym2610_golden_shell_stage_b.qip").read_text()
    local_sources = JOIN_RE.findall(local_qip)
    require(len(local_sources) == 12, f"unexpected local graph size {len(local_sources)}")
    require(sum("stage_b_read_adapter.sv" in item for item in local_sources) == 1,
            "scanner DDR adapter client count is not one")
    require(sum("stage_b_scanner.sv" in item for item in local_sources) == 1,
            "compatibility scanner count is not one")

    modules: dict[str, str] = {}
    duplicate_modules: list[str] = []
    module_re = re.compile(r"^\s*module\s+([A-Za-z_][A-Za-z0-9_$]*)", re.MULTILINE)
    for path, name in zip(sources, relative):
        if path.suffix.lower() not in (".v", ".sv"):
            continue
        for module_name in module_re.findall(path.read_text(errors="replace")):
            if module_name in modules:
                duplicate_modules.append(module_name)
            modules[module_name] = name
    require(not duplicate_modules, f"duplicate modules: {duplicate_modules}")
    for required in ("emu", "mister_vgm_md_top", "vgm_ddram_backend",
                     "ym2610_golden_stage_a", "ym2610_golden_stage_b_scanner"):
        require(required in modules, f"required module missing: {required}")
    return len(sources), len(qips)


def main() -> int:
    require(run("git", "branch", "--show-current") == BRANCH, "wrong branch")
    require(run("git", "merge-base", "--is-ancestor", BASE, "HEAD") == "",
            "Stage A base is not an ancestor")
    stage_a = load_stage_a_audit()
    immutable_audit(stage_a)
    protected_audit(stage_a)
    source_count, qip_count = project_audit()
    print(f"STAGE_B_AUDIT immutable=PASS qsf_normalized=PASS sources={source_count} qips={qip_count}")
    print("STAGE_B_AUDIT forbidden=0 duplicate_sources=0 duplicate_modules=0 absolute_paths=0")
    print("STAGE_B_AUDIT production=UNCHANGED broken=UNCHANGED hw0=UNCHANGED jt10_formal=UNCHANGED")
    print("STAGE_B_AUDIT protected=35 Sacred=PASS stash=PASS")
    print("GOLDEN_SHELL_STAGE_B_STATIC_AUDIT PASS")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AuditError as error:
        print(f"GOLDEN_SHELL_STAGE_B_STATIC_AUDIT FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
