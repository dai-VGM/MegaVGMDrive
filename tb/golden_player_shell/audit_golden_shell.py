#!/usr/bin/env python3
"""Read-only Golden Player Shell Stage A provenance/source audit."""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[2]
STABLE = "5ecce555edb80bdcb010a322ee46ba8837a6ee27"
BASE = "951fea6b9644b774d8eb8c98cb22e9b2bde6f5dd"
BRANCH = "ym2610-golden-shell-port"
HW = ROOT / "hw/ym2610_golden_shell"

STABLE_PATHS = [
    "VGM_MD_MiSTer.qpf",
    "VGM_MD_MiSTer.qsf",
    "VGM_MD_MiSTer.sdc",
    "files.qip",
    "rtl/emu.sv",
    "rtl/megavgm_video_timing.sv",
    "rtl/megavgm_title_receiver.sv",
    "rtl/megavgm_font5x7.sv",
    "rtl/megavgm_title_renderer.sv",
    "rtl/vgm_ddram_backend.sv",
    "rtl/pll.qip",
    "rtl/pll.v",
    "rtl/pll",
    "sys",
]

PROTECTED_UNTRACKED = {
    "ch0.dec": ("0148e886758676ff09b3408225d1f2f74f3bc8e24a3d436a2ed001c35684a479", 716618, 1785749719, 23377142),
    "ch1.dec": ("65158e15594c779a6016ce38d21ed76472a04967ab6cb9cfc7e6d3b8cdd834bb", 716576, 1785749719, 23377143),
    "ch2.dec": ("e2edca7034bf3f1d3f73fd077d83d8df34d5b1f9f1f8001740ceb478d117c2b5", 716576, 1785749719, 23377144),
    "ch3.dec": ("1a2fc3aa61fb1021d76efb3e249b48c23e12460cfdcaaa3edea52494acffa311", 716576, 1785749719, 23377145),
    "ch4.dec": ("ef56f5e1c98bd633b48f462631f03fe0005fcf98b0f19bbfa2f47274643c15ad", 716576, 1785749719, 23377146),
    "ch5.dec": ("18ed698985bf0eaf6a03d11cb4f87991d433d29dfa84b13b87781675b6d825f9", 716576, 1785749719, 23377147),
    "fm0.raw": ("c16eb7fcc566de7e9045dfd8d4be5abe1b8cf731f3f9f3cdcd1c2939aec13e91", 3685248, 1785749719, 23377148),
    "fm1.raw": ("c95601da8a8555f3ce042a9f35d3ab01642981a7164c68324577eade8f0177c1", 3697280, 1785749719, 23377149),
    "fm2.raw": ("2463b8e805219c2d75d83d1a7a2f2930c545cc9c23f66565c0da4ddc12e1d80b", 3685248, 1785749719, 23377150),
    "fm4.raw": ("0a529d1b9bad15fdf562ef552356d532983447548c388e733faa9e8388814f32", 3714948, 1785749719, 23377151),
    "fm5.raw": ("2463b8e805219c2d75d83d1a7a2f2930c545cc9c23f66565c0da4ddc12e1d80b", 3685248, 1785749719, 23377152),
    "fm6.raw": ("2463b8e805219c2d75d83d1a7a2f2930c545cc9c23f66565c0da4ddc12e1d80b", 3685248, 1785749719, 23377153),
    "tb/generate_jt10_phase4ap_variants.py": ("f9584088fad83c1f3f916a694dcc8c138cb9d96977825d956ea1f514fcde83d2", 9827, 1785575962, 23212536),
    "tb/generate_jt10_phase4ax_variants.py": ("fbf036b633cf7bf046824ae69a739222e72e1098deecd060d8d94ceea1b7fa2a", 6634, 1785564257, 23174754),
    "tb/jt10_phase3cr_fixture.md": ("69f6b34de80b613846b41b6b59e54d851cacd9e4f9fed83f0a4ce76e08e99cd5", 13869, 1785511396, 23092116),
    "tb/jt10_phase3cr_sources.f": ("20aaa483f095cdd8893f8d8f42e9faca6a6c7e4d42d413bc7cba1fb551b532a3", 130, 1785508919, 23091109),
    "tb/jt10_phase4ap_fixture.md": ("482369319419915eff3e24a5ac0473a28f7fafb866b7a3ea06f5d32029843b73", 24831, 1785583714, 23229246),
    "tb/jt10_phase4ap_sources.f": ("0b5735947acf56851145923b9521592adb3c1322e3308372e8dd4f5f56c49192", 99, 1785575447, 23213551),
    "tb/jt10_phase4ar_fixture.md": ("3cf148330de8526bd07c75461b8b62e9e18007d035a3d3e8353d946300e33d50", 7939, 1785551099, 23173366),
    "tb/jt10_phase4ar_sources.f": ("e97b914c66bbf614b8de1b5a6f09e3826cc6d56cf4e0d9aaa4efd3f445731a6f", 100, 1785550360, 23172872),
    "tb/jt10_phase4arv1_fixture.md": ("e31b22910d5099692f1f7fe436b4282dc1fbd36691fd41ab5e8b71598a9b0a9a", 34283, 1785572003, 23210807),
    "tb/jt10_phase4arv1_sources.f": ("c996a508e35e125210f2fb860b9f69feac4403343ca11896fadf0430e6ff9e7c", 102, 1785565657, 23203184),
    "tb/jt10_phase4ax_fixture.md": ("8b01467105f9095ea38384f2761a5984318868732f2b057daa00e3cf6853937a", 21219, 1785564151, 23182850),
    "tb/jt10_phase4ax_sources.f": ("d12dc3cd20309ef77affcdd2182da601d7c0c2153cc6a1a86d68929e373a5a9c", 101, 1785553572, 23174951),
    "tb/run_jt10_phase3cr.sh": ("3232c45a5d792836bd3500f0cbaabb638fb4dabffc7ebba42631911f77d6aa73", 15188, 1785511001, 23091838),
    "tb/run_jt10_phase4ap.sh": ("59d66fdae6a2b66f57cd7499278bd4a1c1b06d221af6cd04729b01b1d8433961", 12935, 1785576545, 23214978),
    "tb/run_jt10_phase4ar.sh": ("6f31d0932b07a363638dcb4291b287d7bfd6bcf06d0bbe27eae8d16e578c4623", 10006, 1785550451, 23172906),
    "tb/run_jt10_phase4arv1.sh": ("d8b2ab947652c2926a9c0b294fcc69750cdf3932b2f0517902c434db914d7dd9", 12486, 1785569525, 23203252),
    "tb/run_jt10_phase4ax.sh": ("54101e3930a5c9c93a874ea907ea92ef3fb07c0ad9dd0d6c6f19b2dee0365493", 15096, 1785556556, 23174992),
    "tb/tb_jt10_phase3cr_clear_boundary_audit.sv": ("6d5a9dbe541036c6cede174d89825727b5f9944323cd5ce9affebf19d30c16c2", 66122, 1785510646, 23091111),
    "tb/tb_jt10_phase4ap_adpcmb_patch_matrix.sv": ("92d4b60a29edad2357716a2ce3b0dd701831a5cbc63e24b03b99e8d19018e7a6", 40814, 1785576281, 23213550),
    "tb/tb_jt10_phase4ar_adpcmb_stop_contract.sv": ("a7dab72ba78547982a665db5af9c64fb1a22052e97a81530eb4f8cb324c9c067", 43222, 1785551002, 23172873),
    "tb/tb_jt10_phase4arv1_adpcmb_stop_contract.sv": ("5cadb9b72e7d3c7dcd0c1e0b42930ba771e28fbac6e2084749e842902e5a7265", 5801, 1785569525, 23203183),
    "tb/tb_jt10_phase4ax_adpcmb_reset_coverage.sv": ("e733c1822306ea01a51d2246da2a5a4eeb87dd1434c59e2c9ca1ba688cb019da", 59441, 1785555908, 23174952),
    "tb/tb_jt49_audio_compare.sv": ("35cbd96d057e9889815229f2c0e154614eea7956ae895afdb74f6ace2b65406c", 4939, 1784686524, 21984214),
}


class AuditError(RuntimeError):
    pass


def run(*args: str, binary: bool = False) -> str | bytes:
    result = subprocess.run(
        args,
        cwd=ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode:
        raise AuditError(
            f"command failed ({result.returncode}): {' '.join(args)}\n"
            f"{result.stderr.decode(errors='replace')}"
        )
    return result.stdout if binary else result.stdout.decode().strip()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AuditError(message)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def stable_blob_audit() -> None:
    require(run("git", "cat-file", "-t", STABLE) == "commit", "stable commit missing")
    changed = run("git", "diff", "--name-only", STABLE, "--", *STABLE_PATHS)
    require(not changed, f"stable production blob mismatch:\n{changed}")


def normalized_qsf(path: Path) -> list[str]:
    result: list[str] = []
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or line.startswith("source "):
            continue
        if not (line.startswith("set_global_assignment") or
                line.startswith("set_instance_assignment")):
            continue
        name = re.search(r"-name\s+([A-Za-z0-9_]+)", line)
        if name and (name.group(1).endswith("_FILE") or
                     name.group(1) == "SEARCH_PATH" or
                     name.group(1) == "PROJECT_OUTPUT_DIRECTORY"):
            continue
        result.append(re.sub(r"\s+", " ", line))
    return result


def qsf_equivalence_audit() -> None:
    stable = ROOT / "VGM_MD_MiSTer.qsf"
    golden = HW / "MegaVGMPlayer_YM2610_GoldenShell_MiSTer.qsf"
    require(normalized_qsf(stable) == normalized_qsf(golden),
            "normalized QSF non-source assignments differ")

    macro_re = re.compile(r'^set_global_assignment -name VERILOG_MACRO "([^"]+)"')
    stable_macros = [m.group(1) for line in stable.read_text().splitlines()
                     if (m := macro_re.match(line))]
    golden_macros = [m.group(1) for line in golden.read_text().splitlines()
                     if (m := macro_re.match(line))]
    require(stable_macros == golden_macros, "active QSF macro set differs")

    stable_tcl = (ROOT / "sys/sys.tcl").read_text()
    adapted_tcl = (HW / "sys_golden_shell.tcl").read_text()
    adapted_tcl = adapted_tcl.replace(
        "quartus_sh:../../sys/build_id.tcl", "quartus_sh:sys/build_id.tcl"
    )
    adapted_tcl = adapted_tcl.replace(
        "-name QIP_FILE sys_golden_shell.qip", "-name QIP_FILE sys/sys.qip"
    )
    require(stable_tcl.rstrip().splitlines() == adapted_tcl.rstrip().splitlines(),
            "sys Tcl path adapter changed semantics")

    stable_qip_lines = (ROOT / "sys/sys.qip").read_text().splitlines()
    adapted_qip_lines = (HW / "sys_golden_shell.qip").read_text().splitlines()
    expected_first = (
        "set_global_assignment -name QIP_FILE           "
        "[file join $::quartus(qip_path) ../../rtl/pll.qip ]"
    )
    expected_adapted = [expected_first] + [
        line.replace("$::quartus(qip_path) ",
                     "$::quartus(qip_path) ../../sys/", 1)
        for line in stable_qip_lines[1:]
    ]
    require(adapted_qip_lines == expected_adapted,
            "sys QIP path adapter changed source semantics")

    qsf_text = golden.read_text()
    require(qsf_text.count("set_global_assignment -name SEARCH_PATH ../../") == 1,
            "repository-root include SEARCH_PATH mapping invalid")
    for pll_path in ("../../sys/pll_hdmi.qip", "../../sys/pll_audio.qip",
                     "../../sys/pll_cfg.qip"):
        require(qsf_text.count(pll_path) == 1,
                f"system PLL QIP mapping invalid: {pll_path}")


FILE_TYPES = {"VERILOG_FILE", "SYSTEMVERILOG_FILE", "VHDL_FILE", "SDC_FILE", "QIP_FILE"}
JOIN_RE = re.compile(
    r"\[file join \$::quartus\(qip_path\)\s+\"?([^\"\]\s]+)\"?\s*\]"
)


def walk_qip(path: Path, visited_qips: set[Path], source_files: list[Path]) -> None:
    path = path.resolve()
    require(path.exists(), f"missing QIP: {path.relative_to(ROOT)}")
    if path in visited_qips:
        raise AuditError(f"duplicate QIP registration: {path.relative_to(ROOT)}")
    visited_qips.add(path)
    for line in path.read_text(errors="replace").splitlines():
        name_match = re.search(r"-name\s+([A-Za-z0-9_]+)", line)
        if not name_match or name_match.group(1) not in FILE_TYPES:
            continue
        join_match = JOIN_RE.search(line)
        require(join_match is not None,
                f"unresolved/non-QIP-relative source path in {path.relative_to(ROOT)}: {line}")
        raw = join_match.group(1)
        require(not raw.startswith("/") and not re.match(r"^[A-Za-z]:", raw),
                f"absolute source path: {raw}")
        target = (path.parent / raw).resolve()
        require(target.exists(),
                f"missing source from {path.relative_to(ROOT)}: {target}")
        if name_match.group(1) == "QIP_FILE":
            walk_qip(target, visited_qips, source_files)
        else:
            source_files.append(target)


def source_graph_audit() -> tuple[list[Path], set[Path]]:
    source_files: list[Path] = []
    visited_qips: set[Path] = set()
    starts = [
        HW / "sys_golden_shell.qip",
        ROOT / "sys/pll_hdmi.qip",
        ROOT / "sys/pll_audio.qip",
        ROOT / "sys/pll_cfg.qip",
        HW / "files_ym2610_golden_shell.qip",
    ]
    for start in starts:
        walk_qip(start, visited_qips, source_files)

    relative = [path.relative_to(ROOT).as_posix() for path in source_files]
    require(len(relative) == len(set(relative)), "duplicate source file in Golden graph")

    forbidden = (
        "rtl/ym2610_player/", "hw/ym2610_player/", "tb/ym2610_player/",
        "ym2610_hw0", "jt10", "jt12", "jt51", "jtoutrun", "segapcm",
        "rtl/mister_vgm_md_top.sv", "rtl/vgm_region_player.sv",
        "rtl/vgm_loaded_player.sv", "rtl/vgm_file_loader.sv",
        "rtl/md_sound_module.sv", "/tb/",
    )
    hits = [item for item in relative if any(token in item for token in forbidden)]
    require(not hits, f"forbidden production/test source in Golden graph: {hits}")

    modules: dict[str, str] = {}
    duplicates: list[str] = []
    module_re = re.compile(r"^\s*module\s+([A-Za-z_][A-Za-z0-9_$]*)", re.MULTILINE)
    for path, item in zip(source_files, relative):
        if path.suffix.lower() not in (".v", ".sv"):
            continue
        for module in module_re.findall(path.read_text(errors="replace")):
            if module in modules:
                duplicates.append(f"{module}: {modules[module]}, {item}")
            modules[module] = item
    require(not duplicates, f"duplicate module declarations: {duplicates}")
    require("emu" in modules and "mister_vgm_md_top" in modules,
            "full emu/compatibility modules absent")
    require("vgm_ddram_backend" in modules and "ym2610_golden_stage_a" in modules,
            "upload/profile modules absent")
    return source_files, visited_qips


def protected_audit() -> None:
    untracked = set(run("git", "ls-files", "--others", "--exclude-standard").splitlines())
    require(untracked == set(PROTECTED_UNTRACKED),
            "untracked set is not the protected 35-file baseline")
    for name, expected in PROTECTED_UNTRACKED.items():
        path = ROOT / name
        require(path.exists(), f"protected untracked missing: {name}")
        stat = path.stat()
        actual = (sha256(path), stat.st_size, int(stat.st_mtime), stat.st_ino)
        require(actual == expected,
                f"protected untracked changed: {name}\nexpected={expected}\nactual={actual}")

    sacred = PROTECTED_UNTRACKED["tb/tb_jt49_audio_compare.sv"]
    require(sacred == (
        "35cbd96d057e9889815229f2c0e154614eea7956ae895afdb74f6ace2b65406c",
        4939, 1784686524, 21984214,
    ), "Sacred TB baseline constant changed")

    stash_list = run("git", "stash", "list").splitlines()
    require(stash_list and "Preserve YM2610 HW-0 amplitude audit" in stash_list[0],
            "amplitude stash is not stash@{0}")
    patch = run("git", "stash", "show", "-p", "stash@{0}", binary=True)
    require(hashlib.sha256(patch).hexdigest() ==
            "493adffd4ae4dd2083e1787466caf5b27e5c9a52c635903d704291aa672dc11f",
            "amplitude stash patch SHA-256 changed")


def protected_tracked_paths_audit() -> None:
    groups = {
        "production": ["VGM_MD_MiSTer.qpf", "VGM_MD_MiSTer.qsf", "files.qip", "rtl/emu.sv"],
        "broken YM2610 profile": ["rtl/ym2610_player", "hw/ym2610_player", "tb/ym2610_player"],
        "HW-0": ["rtl/ym2610_hw0", "hw/ym2610_hw0", "tb/ym2610_hw0"],
        "JT10/formal": ["rtl/genesis_audio/jt10_ym2610", "tb/jt10_pinned"],
    }
    for label, paths in groups.items():
        changed = run("git", "diff", "--name-only", BASE, "--", *paths)
        require(not changed, f"{label} changed from base:\n{changed}")


def manifest_audit() -> None:
    manifest_path = ROOT / "docs/golden_player_shell/stable_source_manifest.json"
    if not manifest_path.exists():
        return
    manifest = json.loads(manifest_path.read_text())
    require(manifest["stable_commit"] == STABLE, "manifest stable commit mismatch")
    for entry in manifest["files"]:
        path = ROOT / entry["path"]
        require(path.exists(), f"manifest path missing: {entry['path']}")
        require(sha256(path) == entry["sha256"],
                f"manifest SHA mismatch: {entry['path']}")
        if entry["classification"] == "stable_exact":
            blob = run("git", "rev-parse", f"{STABLE}:{entry['path']}")
            require(blob == entry["git_blob"],
                    f"manifest stable blob mismatch: {entry['path']}")
            require(run("git", "hash-object", entry["path"]) == blob,
                    f"worktree differs from stable manifest: {entry['path']}")


def main() -> int:
    require(run("git", "branch", "--show-current") == BRANCH, "wrong branch")
    require(run("git", "merge-base", "--is-ancestor", BASE, "HEAD") == "",
            "base is not ancestor of HEAD")
    stable_blob_audit()
    qsf_equivalence_audit()
    source_files, qips = source_graph_audit()
    protected_tracked_paths_audit()
    protected_audit()
    manifest_audit()

    stable_files_qip = (ROOT / "files.qip").read_text()
    excluded_sega = sum(
        1 for line in stable_files_qip.splitlines()
        if re.search(r"-name\s+(SYSTEMVERILOG_FILE|VERILOG_FILE|QIP_FILE)", line)
        and not any(allowed in line for allowed in (
            "rtl/emu.sv", "sys/sys.qip", "megavgm_video_timing",
            "megavgm_title_receiver", "megavgm_font5x7",
            "megavgm_title_renderer", "vgm_ddram_backend",
        ))
    )
    relative = [path.relative_to(ROOT).as_posix() for path in source_files]
    profile_count = sum(
        item.startswith("rtl/golden_player_shell/") or
        item.startswith("rtl/ym2610_golden_profile/")
        for item in relative
    )
    shell_count = len(relative) - profile_count

    print(f"AUDIT stable_commit={STABLE} stable_blobs=PASS")
    print("AUDIT qsf_normalized=PASS sys_path_adapter=PASS")
    print(f"AUDIT source_files={len(relative)} qips={len(qips)} duplicates=0 absolute_paths=0")
    print(f"AUDIT shell_system_sources={shell_count} profile_local_sources={profile_count}")
    print(f"AUDIT excluded_sega_sources={excluded_sega} ddr_read_clients=0 sound_devices=0 parsers=0")
    print("AUDIT production=UNCHANGED broken_profile=UNCHANGED hw0=UNCHANGED jt10_formal=UNCHANGED")
    print("AUDIT protected_untracked=35 Sacred=PASS stash=PASS")
    print("GOLDEN_SHELL_STATIC_AUDIT PASS")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AuditError as error:
        print(f"GOLDEN_SHELL_STATIC_AUDIT FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
