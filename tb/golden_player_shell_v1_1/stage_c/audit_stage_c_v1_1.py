#!/usr/bin/env python3
"""Read-only Golden Player Shell v1.1 Stage C migration audit."""

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
BASE = "a7728b74cd67939614f5e981557409adabbfe171"
BRANCH = "golden-player-shell-v1.1-stage-c"
STAGE_B_HW = ROOT / "hw/golden_player_shell_v1_1_stage_b"
STAGE_C_HW = ROOT / "hw/golden_player_shell_v1_1_stage_c"
QIP_NAME = "files_golden_player_shell_v1_1_stage_c.qip"
REVISION = "MegaVGMPlayer_GoldenShell_v1_1_StageC_MiSTer"
JOIN_RE = re.compile(
    r"\[file join \$::quartus\(qip_path\)\s+\"?([^\"\]\s]+)\"?\s*\]"
)
FILE_RE = re.compile(r"-name\s+(?:SYSTEMVERILOG_FILE|VERILOG_FILE)")
MODULE_RE = re.compile(
    r"^\s*module\s+([A-Za-z_][A-Za-z0-9_$]*)", re.MULTILINE
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


def protected_metadata():
    path = ROOT / "tb/golden_player_shell/audit_golden_shell.py"
    spec = importlib.util.spec_from_file_location("golden_protection", path)
    require(spec is not None and spec.loader is not None,
            "cannot load protected metadata")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def scope_and_immutable_audit() -> None:
    allowed = (
        "rtl/golden_player_shell_v1_1/profiles/stage_c/",
        "tb/golden_player_shell_v1_1/stage_c/",
        "docs/golden_player_shell_v1_1/stage_c/",
        "hw/golden_player_shell_v1_1_stage_c/",
    )
    changed = run("git", "diff", "--name-only", BASE).splitlines()
    bad = [name for name in changed if not name.startswith(allowed)]
    require(not bad, f"change outside v1.1 Stage C scope: {bad}")

    untracked = set(run("git", "ls-files", "--others",
                        "--exclude-standard").splitlines())
    protected = set(protected_metadata().PROTECTED_UNTRACKED)
    extras = untracked - protected
    bad_untracked = sorted(name for name in extras
                           if not name.startswith(allowed))
    require(not bad_untracked,
            f"unexpected untracked files: {bad_untracked}")

    expected = {
        "rtl/ym2610_golden_profile/stage_b/ym2610_golden_stage_b_compat.sv":
            "46c11f68a3456ff638ce757c18cdd4a0262995e0bc11e3b923468b8783262115",
        "rtl/ym2610_golden_profile/stage_b/ym2610_golden_stage_b_read_adapter.sv":
            "fe23765aa5b90d45b26800704aeba10620b5ae48a99cb825b6de5b0af6aa3b3b",
        "rtl/ym2610_golden_profile/stage_b/ym2610_golden_stage_b_scanner.sv":
            "fa8643ad830074633502ced52f0795e16e4c007dc4077e49a6421e03605deddb",
        "rtl/ym2610_golden_profile/stage_c/ym2610_golden_stage_c_owner.sv":
            "8641e8de3a89bd5171c800515a6c3a76ad55dfddcd4a0f030e784ccd50acb59e",
        "rtl/ym2610_golden_profile/stage_c/ym2610_golden_stage_c_parser.sv":
            "8923d87c889d5c93369a0cf6cc9ea0d55d8717476f2b17f4e9fd8ee82538f01c",
        "rtl/ym2610_golden_profile/stage_c/ym2610_golden_stage_c_sound_adapter.sv":
            "20a6bd12603d541585ee8e979f247afd9103321dd07d744ac6c5e5d874574f1f",
        "rtl/ym2610_golden_profile/stage_c/ym2610_golden_stage_c_profile.sv":
            "447fa3d36ba2ee4ca438f5619923e356fea6853395610d3b3e0235749a5a3055",
        "tb/ym2610_golden_profile/stage_c/olga_reference.json":
            "be8e73578db4db5c19d17cfc430399374c9cd7b4b88f6f5398d5c4e2b74726df",
        "tb/ym2610_golden_profile/stage_c/olga_replay_windows.json":
            "9e64f960f909945c5b3bebbc5a78002969ef8620ce61bfa8062f87e806e58b32",
        "tb/ym2610_golden_profile/stage_c/stage_c_reference.py":
            "7092df334a9318c3523519108145a985d0c9daa511de5d0410916a85fd65ce98",
    }
    for name, digest in expected.items():
        require(sha256(ROOT / name) == digest,
                f"existing Stage B/C blob changed: {name}")


def protected_audit() -> None:
    meta = protected_metadata()
    untracked = set(run("git", "ls-files", "--others",
                        "--exclude-standard").splitlines())
    protected = set(meta.PROTECTED_UNTRACKED)
    require(len(protected) == 35 and protected <= untracked,
            "protected 35 untracked set changed")
    for name, expected in meta.PROTECTED_UNTRACKED.items():
        path = ROOT / name
        stat = path.stat()
        actual = (sha256(path), stat.st_size, int(stat.st_mtime), stat.st_ino)
        require(actual == expected, f"protected file changed: {name}")
    sacred = ROOT / "tb/tb_jt49_audio_compare.sv"
    stat = sacred.stat()
    require((sha256(sacred), stat.st_size, int(stat.st_mtime), stat.st_ino) ==
            ("35cbd96d057e9889815229f2c0e154614eea7956ae895afdb74f6ace2b65406c",
             4939, 1784686524, 21984214), "Sacred TB changed")
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
    sources: list[Path] = []
    for line in path.read_text().splitlines():
        if not FILE_RE.search(line):
            continue
        match = JOIN_RE.search(line)
        require(match is not None, f"non-relative QIP assignment: {line}")
        raw = match.group(1)
        require(not raw.startswith("/") and
                not re.match(r"^[A-Za-z]:", raw),
                f"absolute QIP path: {raw}")
        target = (path.parent / raw).resolve()
        require(target.is_file(), f"missing QIP source: {target}")
        sources.append(target)
    relative = [path.relative_to(ROOT).as_posix() for path in sources]
    require(len(relative) == len(set(relative)), "duplicate QIP source")
    return sources


def project_audit() -> tuple[int, int]:
    stage_b_qsf = (STAGE_B_HW /
        "MegaVGMPlayer_GoldenShell_v1_1_StageB_MiSTer.qsf").read_text()
    expected_qsf = stage_b_qsf.replace(
        "files_golden_player_shell_v1_1_stage_b.qip", QIP_NAME)
    qsf = STAGE_C_HW / f"{REVISION}.qsf"
    require(qsf.read_text() == expected_qsf,
            "Stage C QSF differs beyond its QIP assignment")
    for support in ("sys_golden_shell.qip", "sys_golden_shell.tcl"):
        require((STAGE_C_HW / support).read_bytes() ==
                (STAGE_B_HW / support).read_bytes(),
                f"Stage C {support} differs from Stage B")
    require((STAGE_C_HW / f"{REVISION}.qpf").read_text() ==
            'QUARTUS_VERSION = "17.0"\n'
            f'PROJECT_REVISION = "{REVISION}"\n',
            "Stage C QPF mismatch")
    assignments = re.findall(r"-name QIP_FILE\s+([^\s]+)", qsf.read_text())
    require(assignments.count(QIP_NAME) == 1,
            "Stage C QIP assignment count is not one")
    require(not any(Path(value).is_absolute() for value in assignments),
            "absolute QSF QIP path")

    qip = STAGE_C_HW / QIP_NAME
    sources = qip_sources(qip)
    relative = [path.relative_to(ROOT).as_posix() for path in sources]
    old = qip_sources(ROOT /
        "hw/ym2610_golden_shell_stage_c/files_ym2610_golden_shell_stage_c.qip")
    expected = [path.relative_to(ROOT).as_posix() for path in old]
    old_shim = "rtl/golden_player_shell/mister_vgm_md_top_compat.sv"
    wrapper = ("rtl/golden_player_shell_v1_1/profiles/stage_c/"
               "golden_player_shell_v1_1_stage_c_profile.sv")
    shim = "rtl/golden_player_shell_v1_1/mister_vgm_md_top_v1_1.sv"
    shim_index = expected.index(old_shim)
    expected[shim_index:shim_index + 1] = [wrapper, shim]
    require(relative == expected,
            "Stage C graph is not the existing graph plus wrapper/v1.1 shim")

    forbidden = (
        "rtl/ym2610_player/", "ym2610_hw0_top", "ym2610_hw0_sequencer",
        "ym2610_hw0_video", "ym2610_hw0_adpcma_rom",
        "ym2610_hw0_adpcmb_rom", "ym2610_hw0_jt10_wrapper",
        "rtl/ym2610_hw0/emu.sv", "jt51", "jtoutrun", "segapcm",
        "vgm_loaded_player", "vgm_region_player", "vgm_file_loader",
        "md_sound_module", "stage_d", "pcm_cache", "pcm_ddr",
        "multi_client", "testbench", "tb_stage_",
    )
    hits = [name for name in relative
            if any(token in name.lower() for token in forbidden)]
    require(not hits, f"forbidden Stage C sources: {hits}")
    tb_sources = [name for name in relative if name.startswith("tb/")]
    pinned = "tb/jt10_pinned/6d51e0b6/adpcm/"
    require(len(tb_sources) == 7 and
            all(name.startswith(pinned) for name in tb_sources),
            f"test-only source entered QIP: {tb_sources}")
    require(old_shim not in relative, "v1.0 shim entered graph")
    require(relative.count(wrapper) == 1 and relative.count(shim) == 1,
            "v1.1 wrapper/shim source count mismatch")

    modules: dict[str, str] = {}
    duplicates: list[str] = []
    for path, name in zip(sources, relative):
        for module in MODULE_RE.findall(path.read_text(errors="replace")):
            if module in modules:
                duplicates.append(module)
            modules[module] = name
    require(not duplicates, f"duplicate modules: {duplicates}")
    required = (
        "emu", "mister_vgm_md_top", "golden_player_shell_v1_1_profile",
        "ym2610_golden_stage_a", "ym2610_golden_stage_b_scanner",
        "ym2610_golden_stage_b_read_adapter", "ym2610_golden_stage_c_owner",
        "ym2610_golden_stage_c_parser",
        "ym2610_golden_stage_c_sound_adapter",
        "ym2610_hw0_jt12_top", "jt49",
    )
    require(all(module in modules for module in required),
            "required Stage C module missing")
    require(modules["mister_vgm_md_top"] == shim,
            "wrong public shim binding")
    require(modules["golden_player_shell_v1_1_profile"] == wrapper,
            "wrong v1.1 profile binding")
    require(modules["ym2610_golden_stage_a"] ==
            "rtl/ym2610_golden_profile/stage_c/ym2610_golden_stage_c_profile.sv",
            "wrong existing Stage C binding")
    return len(sources), len(modules)


def contract_and_reference_audit() -> None:
    wrapper = (ROOT /
        "rtl/golden_player_shell_v1_1/profiles/stage_c/"
        "golden_player_shell_v1_1_stage_c_profile.sv").read_text()
    require("ym2610_golden_stage_a #(" in wrapper and
            ") stage_c_core (" in wrapper,
            "existing Stage C public profile is not directly instantiated")
    require("stage_c_core." not in wrapper,
            "synthesizable hierarchical Stage C reference")
    require("always_ff @(posedge clk_sys)" in wrapper and
            "LC_PLAYBACK_ARM" in wrapper and "LC_PLAYBACK" in wrapper,
            "registered audio-enable lifecycle missing")
    require("stage_c_reader_outstanding" in wrapper and
            "stage_c_sound_ready" in wrapper and
            "stage_c_parser_ended" in wrapper,
            "public safe-gate inputs missing")
    require("profile_audio_enable ? stage_c_audio_l : 16'sd0" in wrapper and
            "profile_audio_enable ? stage_c_audio_r : 16'sd0" in wrapper,
            "fail-closed audio mapping missing")
    require("module ym2610_golden_stage_c_parser" not in wrapper and
            "module ym2610_golden_stage_c_sound_adapter" not in wrapper and
            "module ym2610_golden_stage_b_scanner" not in wrapper,
            "existing implementation was copied into wrapper")

    shim = (ROOT /
        "rtl/golden_player_shell_v1_1/mister_vgm_md_top_v1_1.sv").read_text()
    emu = (ROOT / "rtl/emu.sv").read_text()
    require("assign audio_gate_open = profile_audio_enable;" in shim and
            "assign audio_muted = !profile_audio_enable;" in shim,
            "immutable shim gate mapping changed")
    require("profile_audio_enable ? profile_audio_l : 16'sd0" in shim and
            "(audio_gate_open && !audio_muted) ? audio_l_safe : 16'sd0" in emu and
            "assign AUDIO_L = audio_l_final;" in emu,
            "actual stable final-audio path missing")

    reference = json.loads((ROOT /
        "tb/ym2610_golden_profile/stage_c/olga_reference.json").read_text())
    expected = {
        "original_size": 933897, "physical_size": 934025,
        "clock_field": 0x807A1200, "clock": 8_000_000,
        "variant_b": True, "dual": False,
        "command_count": 171869, "total_writes": 81272,
        "port0_writes": 38246, "port1_writes": 43026,
        "total_samples": 8372668, "forwarded_fm_global": 78293,
        "forwarded_ssg": 0, "suppressed_adpcma": 2752,
        "suppressed_adpcmb": 227, "b_only_writes": 0,
        "unknown_writes": 0, "data_blocks": 7,
        "loop_target": 0xB6223, "end_pc": 0xE3F24,
        "trace_hash": "7c3088bd1d4eea6f",
        "first256_trace_hash": "155cbbc09e7b636b",
        "first_adpcmb_control_sample": 4625,
        "first_fm_key_on_sample": 120851,
        "first_adpcma_control_sample": 121270,
    }
    for key, value in expected.items():
        require(reference[key] == value,
                f"Olga reference mismatch {key}: {reference[key]}")

    windows = json.loads((ROOT /
        "tb/ym2610_golden_profile/stage_c/olga_replay_windows.json").read_text())
    window_order = [
        "first_fm_key_on", "first_sustained_fm", "mid_song_fm",
        "loop_target_first_pass", "loop_crossing",
    ]
    expected_hashes = [
        "bda45f7a067cf72d", "dc663bb0b7349cd5", "184eec59e4466a7d",
        "a4a707ca22e4bb61", "87a5398c48b391c1",
    ]
    actual_hashes = [
        windows["windows"][name]["replay_final_lr_hash"]
        for name in window_order
    ]
    require(actual_hashes == expected_hashes,
            "retained Stage C replay-window hash mismatch")


def no_artifacts() -> None:
    roots = [
        ROOT / "rtl/golden_player_shell_v1_1/profiles/stage_c",
        ROOT / "tb/golden_player_shell_v1_1/stage_c",
        ROOT / "docs/golden_player_shell_v1_1/stage_c",
        STAGE_C_HW,
    ]
    bad_names = {"db", "incremental_db", "output_files", "__pycache__"}
    bad_suffixes = {
        ".rbf", ".sof", ".rpt", ".vcd", ".fst", ".wav", ".raw",
        ".log", ".pyc",
    }
    found = [path for root in roots for path in root.rglob("*")
             if path.name in bad_names or path.suffix.lower() in bad_suffixes]
    require(not found, f"candidate artifact present: {found}")


def main() -> int:
    require(run("git", "branch", "--show-current") == BRANCH,
            "wrong branch")
    require(run("git", "merge-base", "--is-ancestor", BASE, "HEAD") == "",
            "requested base is not an ancestor")
    scope_and_immutable_audit()
    protected_audit()
    contract_and_reference_audit()
    source_count, module_count = project_audit()
    no_artifacts()
    print("V1_1_STAGE_C_AUDIT agents=PASS v1_0=IMMUTABLE v1_1_contract=IMMUTABLE existing_a_b_c=IMMUTABLE")
    print(f"V1_1_STAGE_C_AUDIT sources={source_count} modules={module_count} shim_v1_1=1 shim_v1_0=0 wrapper=1 duplicates=0")
    print("V1_1_STAGE_C_AUDIT qsf=NORMALIZED qip=RELATIVE scanner=1 parser=1 owner=1 pcm_ddr=0 copy_fork=0")
    print("V1_1_STAGE_C_AUDIT olga_reference=PASS trace=7c3088bd1d4eea6f first256=155cbbc09e7b636b windows=5")
    print("V1_1_STAGE_C_AUDIT production=UNCHANGED old_profile=UNCHANGED hw0=UNCHANGED jt10_formal_pristine=UNCHANGED")
    print("V1_1_STAGE_C_AUDIT protected=35 Sacred=PASS stash=PASS artifacts=0")
    print("GOLDEN_SHELL_V1_1_STAGE_C_STATIC_AUDIT PASS")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AuditError as error:
        print(f"GOLDEN_SHELL_V1_1_STAGE_C_STATIC_AUDIT FAIL: {error}",
              file=sys.stderr)
        raise SystemExit(1)
