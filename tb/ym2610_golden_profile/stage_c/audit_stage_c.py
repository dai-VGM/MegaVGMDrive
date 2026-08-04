#!/usr/bin/env python3
"""Read-only Stage C project, provenance, and source-graph audit."""

from __future__ import annotations

import hashlib
import importlib.util
from pathlib import Path
import re
import subprocess
import sys

sys.dont_write_bytecode = True


ROOT = Path(__file__).resolve().parents[3]
BASE = "b3869ef9a3c57da5d714d8598af052e914e3a3e9"
BRANCH = "ym2610-golden-shell-stage-c"
STAGE_B_HW = ROOT / "hw/ym2610_golden_shell_stage_b"
STAGE_C_HW = ROOT / "hw/ym2610_golden_shell_stage_c"
JOIN_RE = re.compile(
    r"\[file join \$::quartus\(qip_path\)\s+\"?([^\"\]\s]+)\"?\s*\]"
)
FILE_RE = re.compile(
    r"-name\s+(VERILOG_FILE|SYSTEMVERILOG_FILE|VHDL_FILE|SDC_FILE|QIP_FILE)"
)


class AuditError(RuntimeError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AuditError(message)


def run(*args: str, binary: bool = False) -> str | bytes:
    result = subprocess.run(args, cwd=ROOT, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, check=False)
    if result.returncode:
        raise AuditError(
            f"command failed: {' '.join(args)}\n" +
            result.stderr.decode(errors="replace")
        )
    return result.stdout if binary else result.stdout.decode().strip()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def load_stage_a_audit():
    path = ROOT / "tb/golden_player_shell/audit_golden_shell.py"
    spec = importlib.util.spec_from_file_location("stage_a_audit", path)
    require(spec is not None and spec.loader is not None,
            "cannot load Stage A audit metadata")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def immutable_audit() -> None:
    immutable = [
        "AGENTS.md",
        "rtl/golden_player_shell", "tb/golden_player_shell",
        "hw/ym2610_golden_shell", "docs/golden_player_shell",
        "rtl/ym2610_golden_profile/stage_b",
        "tb/ym2610_golden_profile/stage_b",
        "hw/ym2610_golden_shell_stage_b",
        "docs/ym2610_golden_shell_stage_b",
        "rtl/ym2610_player", "rtl/ym2610_hw0", "hw/ym2610_hw0",
        "files.qip", "VGM_MD_MiSTer.qsf",
        "rtl/genesis_audio/jt10_ym2610",
        "rtl/genesis_audio/jt12", "rtl/genesis_audio/jt49",
        "tb/jt10_pinned",
    ]
    changed = run("git", "diff", "--name-only", BASE, "--", *immutable)
    require(not changed, f"immutable/production paths changed:\n{changed}")


def protected_audit() -> None:
    stage_a = load_stage_a_audit()
    untracked = set(
        run("git", "ls-files", "--others", "--exclude-standard").splitlines()
    )
    protected = set(stage_a.PROTECTED_UNTRACKED)
    require(len(protected) == 35, "protected metadata is not 35 files")
    require(protected <= untracked,
            "one or more protected untracked diagnostics disappeared")
    extras = untracked - protected
    allowed = (
        "rtl/ym2610_golden_profile/stage_c/",
        "tb/ym2610_golden_profile/stage_c/",
        "hw/ym2610_golden_shell_stage_c/",
        "docs/ym2610_golden_shell_stage_c/",
    )
    unexpected = sorted(name for name in extras if not name.startswith(allowed))
    require(not unexpected, f"unexpected untracked files: {unexpected}")
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


def local_source_graph() -> list[Path]:
    qip = STAGE_C_HW / "files_ym2610_golden_shell_stage_c.qip"
    sources: list[Path] = []
    for line in qip.read_text().splitlines():
        kind = FILE_RE.search(line)
        if not kind:
            continue
        match = JOIN_RE.search(line)
        require(match is not None, f"non-relative QIP assignment: {line}")
        raw = match.group(1)
        require(not raw.startswith("/") and
                not re.match(r"^[A-Za-z]:", raw),
                f"absolute QIP path: {raw}")
        target = (qip.parent / raw).resolve()
        require(target.is_file(), f"missing QIP source: {target}")
        require(kind.group(1) != "QIP_FILE",
                "nested profile QIP is not allowed")
        sources.append(target)
    relative = [path.relative_to(ROOT).as_posix() for path in sources]
    require(len(relative) == len(set(relative)), "duplicate Stage C source")
    return sources


def project_audit() -> tuple[int, int, int]:
    stage_b_qsf = (
        STAGE_B_HW /
        "MegaVGMPlayer_YM2610_GoldenShell_StageB_MiSTer.qsf"
    ).read_text()
    stage_c_qsf_path = (
        STAGE_C_HW /
        "MegaVGMPlayer_YM2610_GoldenShell_StageC_MiSTer.qsf"
    )
    expected_qsf = stage_b_qsf.replace(
        "files_ym2610_golden_shell_stage_b.qip",
        "files_ym2610_golden_shell_stage_c.qip",
    )
    require(stage_c_qsf_path.read_text() == expected_qsf,
            "Stage C QSF differs beyond its profile QIP assignment")
    require((STAGE_C_HW / "sys_golden_shell.tcl").read_bytes() ==
            (STAGE_B_HW / "sys_golden_shell.tcl").read_bytes(),
            "Stage C system Tcl differs from Stage B")
    require((STAGE_C_HW / "sys_golden_shell.qip").read_bytes() ==
            (STAGE_B_HW / "sys_golden_shell.qip").read_bytes(),
            "Stage C system QIP differs from Stage B")
    qpf = (STAGE_C_HW /
           "MegaVGMPlayer_YM2610_GoldenShell_StageC_MiSTer.qpf").read_text()
    require('PROJECT_REVISION = '
            '"MegaVGMPlayer_YM2610_GoldenShell_StageC_MiSTer"' in qpf,
            "Stage C revision mismatch")

    qsf_qips = re.findall(r"-name QIP_FILE\s+([^\s]+)",
                          stage_c_qsf_path.read_text())
    require(qsf_qips.count("files_ym2610_golden_shell_stage_c.qip") == 1,
            "Stage C profile QIP registration is not exactly one")
    require(not any(Path(item).is_absolute() for item in qsf_qips),
            "absolute QSF QIP path")

    sources = local_source_graph()
    relative = [path.relative_to(ROOT).as_posix() for path in sources]
    forbidden = (
        "rtl/ym2610_player/", "ym2610_hw0_top", "ym2610_hw0_sequencer",
        "ym2610_hw0_video", "ym2610_hw0_adpcma_rom",
        "ym2610_hw0_adpcmb_rom", "ym2610_hw0_jt10_wrapper",
        "rtl/ym2610_hw0/emu.sv", "jt51", "jtoutrun", "segapcm",
        "vgm_loaded_player", "vgm_region_player", "vgm_file_loader",
        "md_sound_module", "testbench", "tb_stage_",
    )
    hits = [name for name in relative
            if any(token in name.lower() for token in forbidden)]
    require(not hits, f"forbidden Stage C sources: {hits}")
    tb_sources = [name for name in relative if name.startswith("tb/")]
    pinned_prefix = "tb/jt10_pinned/6d51e0b6/adpcm/"
    require(all(name.startswith(pinned_prefix) for name in tb_sources),
            f"test-only source in QIP: {tb_sources}")
    require(len(tb_sources) == 7,
            f"expected seven immutable vendor-pin leaves, got {tb_sources}")

    required_once = (
        "rtl/ym2610_golden_profile/stage_b/ym2610_golden_stage_b_compat.sv",
        "rtl/ym2610_golden_profile/stage_b/ym2610_golden_stage_b_read_adapter.sv",
        "rtl/ym2610_golden_profile/stage_b/ym2610_golden_stage_b_scanner.sv",
        "rtl/ym2610_golden_profile/stage_c/ym2610_golden_stage_c_owner.sv",
        "rtl/ym2610_golden_profile/stage_c/ym2610_golden_stage_c_parser.sv",
        "rtl/ym2610_golden_profile/stage_c/ym2610_golden_stage_c_sound_adapter.sv",
        "rtl/ym2610_golden_profile/stage_c/ym2610_golden_stage_c_profile.sv",
        "rtl/ym2610_hw0/ym2610_hw0_jt12_top.v",
    )
    for required in required_once:
        require(relative.count(required) == 1,
                f"required source count is not one: {required}")
    require(not any("stage_b_profile.sv" in name for name in relative),
            "Stage B drop-in profile remained in Stage C graph")
    require(not any("pcm_cache" in name or "pcm_ddr" in name or
                    "multi_client" in name for name in relative),
            "PCM client/cache/arbiter entered Stage C")

    module_re = re.compile(
        r"^\s*module\s+([A-Za-z_][A-Za-z0-9_$]*)", re.MULTILINE
    )
    modules: dict[str, str] = {}
    duplicates: list[str] = []
    for path, name in zip(sources, relative):
        if path.suffix.lower() not in (".v", ".sv"):
            continue
        for module in module_re.findall(path.read_text(errors="replace")):
            if module in modules:
                duplicates.append(module)
            modules[module] = name
    require(not duplicates, f"duplicate modules: {duplicates}")
    for module in ("emu", "mister_vgm_md_top", "vgm_ddram_backend",
                   "ym2610_golden_stage_a",
                   "ym2610_golden_stage_b_scanner",
                   "ym2610_golden_stage_c_parser",
                   "ym2610_golden_stage_c_sound_adapter",
                   "ym2610_hw0_jt12_top", "jt49"):
        require(module in modules, f"required module missing: {module}")
    return len(sources), len(modules), len(tb_sources)


def no_artifacts() -> None:
    forbidden_names = {"db", "incremental_db", "output_files"}
    found = [path for path in STAGE_C_HW.rglob("*")
             if path.name in forbidden_names or
             path.suffix.lower() in {".rbf", ".sof", ".rpt", ".vcd", ".fst"}]
    require(not found, f"build artifacts present: {found}")


def main() -> int:
    require(run("git", "branch", "--show-current") == BRANCH,
            "wrong branch")
    require(run("git", "merge-base", "--is-ancestor", BASE, "HEAD") == "",
            "Stage C base is not an ancestor")
    immutable_audit()
    protected_audit()
    source_count, module_count, pinned_count = project_audit()
    no_artifacts()
    print("STAGE_C_AUDIT agents=PASS stage_a=IMMUTABLE stage_b=IMMUTABLE changed_a_b=0")
    print("STAGE_C_AUDIT qsf_normalized=PASS qip_relative=PASS "
          f"sources={source_count} modules={module_count} duplicates=0")
    print("STAGE_C_AUDIT scanner=1 parser=1 simultaneous=0 pcm_ddr=0 "
          f"vendor_pin_leaves={pinned_count} testbench_sources=0")
    print("STAGE_C_AUDIT production=UNCHANGED broken=UNCHANGED hw0=UNCHANGED "
          "jt10_formal_pristine=UNCHANGED")
    print("STAGE_C_AUDIT protected=35 Sacred=PASS stash=PASS artifacts=0")
    print("GOLDEN_SHELL_STAGE_C_STATIC_AUDIT PASS")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AuditError as error:
        print(f"GOLDEN_SHELL_STAGE_C_STATIC_AUDIT FAIL: {error}",
              file=sys.stderr)
        raise SystemExit(1)
