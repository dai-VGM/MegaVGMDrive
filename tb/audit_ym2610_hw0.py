#!/usr/bin/env python3
"""Static, non-Quartus audit for the YM2610 HW-0 project."""

from pathlib import Path
from hashlib import sha256
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "hw" / "ym2610_hw0"


def check(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def qip_path_rows(path: Path) -> list[tuple[str, Path]]:
    found: list[tuple[str, Path]] = []
    for line in path.read_text().splitlines():
        match = re.search(r"\$::quartus\(qip_path\)\s+([^\]\s]+)", line)
        if match:
            relative = match.group(1)
            check(not Path(relative).is_absolute(),
                  f"absolute QIP path in {path.name}: {relative}")
            found.append((relative, (path.parent / relative).resolve()))
    return found


def qip_paths(path: Path) -> list[Path]:
    return [resolved for _, resolved in qip_path_rows(path)]


def modules(path: Path) -> list[str]:
    if path.suffix.lower() not in {".v", ".sv"}:
        return []
    text = re.sub(r"/\*.*?\*/", "", path.read_text(errors="replace"),
                  flags=re.S)
    text = re.sub(r"//.*", "", text)
    return re.findall(r"(?m)^\s*module\s+([A-Za-z_$][A-Za-z0-9_$]*)", text)


PROTECTED_UNTRACKED = """tb/tb_jt49_audio_compare.sv
tb/tb_jt10_phase3cr_clear_boundary_audit.sv
tb/run_jt10_phase3cr.sh
tb/jt10_phase3cr_sources.f
tb/jt10_phase3cr_fixture.md
tb/tb_jt10_phase4ar_adpcmb_stop_contract.sv
tb/run_jt10_phase4ar.sh
tb/jt10_phase4ar_sources.f
tb/jt10_phase4ar_fixture.md
tb/tb_jt10_phase4ax_adpcmb_reset_coverage.sv
tb/run_jt10_phase4ax.sh
tb/generate_jt10_phase4ax_variants.py
tb/jt10_phase4ax_sources.f
tb/jt10_phase4ax_fixture.md
tb/tb_jt10_phase4arv1_adpcmb_stop_contract.sv
tb/run_jt10_phase4arv1.sh
tb/jt10_phase4arv1_sources.f
tb/jt10_phase4arv1_fixture.md
tb/tb_jt10_phase4ap_adpcmb_patch_matrix.sv
tb/run_jt10_phase4ap.sh
tb/generate_jt10_phase4ap_variants.py
tb/jt10_phase4ap_sources.f
tb/jt10_phase4ap_fixture.md""".splitlines()


def git(*args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


def main() -> int:
    qpf = PROJECT / "MegaVGMDrive_YM2610_HW0.qpf"
    qsf = PROJECT / "MegaVGMDrive_YM2610_HW0.qsf"
    core_qip = PROJECT / "files_ym2610_hw0.qip"
    sys_tcl = PROJECT / "sys_ym2610_hw0.tcl"
    sys_qip = PROJECT / "sys_ym2610_hw0.qip"
    required = [qpf, qsf, core_qip, sys_tcl, sys_qip]
    check(all(path.is_file() for path in required), "missing project file")

    qpf_text = qpf.read_text()
    qsf_text = qsf.read_text()
    core_text = core_qip.read_text()
    all_project_text = "\n".join(path.read_text() for path in required)
    check('PROJECT_REVISION = "MegaVGMDrive_YM2610_HW0"' in qpf_text,
          "QPF revision")
    check("TOP_LEVEL_ENTITY sys_top" in qsf_text, "top-level entity")
    check("PROJECT_OUTPUT_DIRECTORY output_files" in qsf_text,
          "output directory")
    check("GENERATE_RBF_FILE ON" in qsf_text, "RBF generation")
    qsf_sources = re.findall(r"(?m)^\s*source\s+(\S+)\s*$", qsf_text)
    check(qsf_sources == ["sys_ym2610_hw0.tcl",
                          "../../sys/sys_analog.tcl"],
          "unexpected QSF source command")
    check(qsf_sources.count("files_ym2610_hw0.qip") == 0,
          "HW-0 QIP must not be executed with source")
    qsf_qip_files = re.findall(
        r"(?m)^\s*set_global_assignment\s+-name\s+QIP_FILE\s+(\S+)\s*$",
        qsf_text)
    check(qsf_qip_files == ["files_ym2610_hw0.qip"],
          "HW-0 QIP_FILE assignment must occur exactly once")
    check(not Path(qsf_qip_files[0]).is_absolute(),
          "HW-0 QIP_FILE assignment is absolute")
    check((qsf.parent / qsf_qip_files[0]).resolve() == core_qip.resolve(),
          "HW-0 QIP_FILE path is not relative to its QSF")
    check(not re.search(r"(?:/Users/|[A-Za-z]:[\\/]|/tmp/|/private/tmp/)",
                        all_project_text), "absolute path")

    production_tcl = (ROOT / "sys" / "sys.tcl").read_text()
    expected_tcl = production_tcl.replace(
        'set_global_assignment -name PRE_FLOW_SCRIPT_FILE "quartus_sh:sys/build_id.tcl"',
        'set_global_assignment -name PRE_FLOW_SCRIPT_FILE "quartus_sh:../../sys/build_id.tcl"')
    expected_tcl = expected_tcl.replace(
        "set_global_assignment -name CDF_FILE jtag.cdf\n", "")
    expected_tcl = expected_tcl.replace(
        "set_global_assignment -name QIP_FILE sys/sys.qip",
        "set_global_assignment -name QIP_FILE sys_ym2610_hw0.qip")
    check(sys_tcl.read_text().rstrip() == expected_tcl.rstrip(),
          "board/device/pin Tcl differs beyond project-relative paths")

    production_sys_qip = (ROOT / "sys" / "sys.qip").read_text().splitlines()
    expected_sys_qip = [
        "set_global_assignment -name QIP_FILE           "
        "[file join $::quartus(qip_path) ../../rtl/pll.qip ]"
    ]
    for line in production_sys_qip[1:]:
        expected_sys_qip.append(line.replace(
            "$::quartus(qip_path) ",
            "$::quartus(qip_path) ../../sys/"))
    check(sys_qip.read_text().splitlines() == expected_sys_qip,
          "MiSTer sys QIP adapter is not mechanical")

    check('FAMILY "Cyclone V"' in sys_tcl.read_text(), "FPGA family")
    check("DEVICE 5CSEBA6U23I7" in sys_tcl.read_text(), "FPGA device")
    check("../../sys/sys_top.sdc" in sys_qip.read_text(), "SDC path")
    check("../../sys/build_id.tcl" in sys_tcl.read_text(), "post-flow path")

    forbidden = [
        "../../rtl/emu.sv", "files.qip", "vgm_loaded_player",
        "vgm_ddram_backend", "segapcm", "jt51", "ym2203",
        "title_receiver", "/tmp", "phase3", "phase4", "diagnostic",
    ]
    lowered = core_text.lower()
    check(all(token.lower() not in lowered for token in forbidden),
          "forbidden HW-0 source dependency")

    core_qip_rows = qip_path_rows(core_qip)
    sys_qip_rows = qip_path_rows(sys_qip)
    for qip, rows in ((core_qip, core_qip_rows),
                      (sys_qip, sys_qip_rows)):
        assignment_count = len(re.findall(
            r"(?m)^\s*set_global_assignment\s+-name\s+\S+", qip.read_text()))
        check(len(rows) == assignment_count,
              f"QIP assignment without qip_path context: {qip.name}")
    source_paths = ([resolved for _, resolved in core_qip_rows] +
                    [resolved for _, resolved in sys_qip_rows])
    check(len(source_paths) == len(set(source_paths)), "duplicate source path")
    missing = [path for path in source_paths if not path.is_file()]
    check(not missing, "missing source: " + ", ".join(map(str, missing)))

    owners: dict[str, Path] = {}
    duplicate_modules: list[str] = []
    for source in source_paths:
        for module in modules(source):
            if module in owners:
                duplicate_modules.append(
                    f"{module}:{owners[module]}:{source}")
            else:
                owners[module] = source
    check(not duplicate_modules,
          "duplicate module: " + ", ".join(duplicate_modules))

    production_files = [ROOT / "VGM_MD_MiSTer.qpf",
                        ROOT / "VGM_MD_MiSTer.qsf", ROOT / "files.qip"]
    production_text = "\n".join(path.read_text() for path in production_files)
    check("ym2610_hw0" not in production_text.lower(),
          "production project references HW-0")
    check("genesis_audio/jt10_ym2610" not in production_text,
          "production project references formal overlay")

    protected_rows = []
    for name in sorted(PROTECTED_UNTRACKED):
        path = ROOT / name
        check(path.is_file(), f"protected untracked missing: {name}")
        stat = path.stat()
        protected_rows.append(
            f"{name}\t{sha256(path.read_bytes()).hexdigest()}\t"
            f"{stat.st_size}\t{int(stat.st_mtime)}\t{stat.st_ino}")
    protected_digest = sha256(
        ("\n".join(protected_rows) + "\n").encode()).hexdigest()
    check(protected_digest ==
          "42ed2aca1a859f43278641607b21e5134e0b09bc053a3f0dc22e08f9a46dbf74",
          "protected untracked SHA/size/mtime/inode manifest")
    sacred = ROOT / "tb" / "tb_jt49_audio_compare.sv"
    sacred_stat = sacred.stat()
    check(sha256(sacred.read_bytes()).hexdigest() ==
          "35cbd96d057e9889815229f2c0e154614eea7956ae895afdb74f6ace2b65406c"
          and sacred_stat.st_size == 4939
          and int(sacred_stat.st_mtime) == 1784686524
          and sacred_stat.st_ino == 21984214, "sacred TB metadata")

    pin_root = ROOT / "tb" / "jt10_pinned" / "6d51e0b6"
    for row in (ROOT / "tb" / "jt10_compat" /
                "pristine_blobs.tsv").read_text().splitlines()[1:]:
        rel, expected_blob, expected_sha = row.split("\t")
        path = pin_root / rel
        check(git("hash-object", str(path.relative_to(ROOT))) == expected_blob,
              f"pristine blob: {rel}")
        check(sha256(path.read_bytes()).hexdigest() == expected_sha,
              f"pristine SHA: {rel}")

    immutable_tracked = [
        "VGM_MD_MiSTer.qpf", "VGM_MD_MiSTer.qsf", "files.qip",
        "rtl/emu.sv", "rtl/vgm_loaded_player.sv",
        "rtl/mister_vgm_md_top.sv", "rtl/vgm_ddram_backend.sv",
        "rtl/md_sound_module.sv", "sys/sys_top.v",
        "rtl/genesis_audio/jt10_ym2610",
        "rtl/genesis_audio/jt49", "tb/jt10_compat",
        "tb/jt10_phase0_warmup_wrapper.sv",
    ]
    for rel in immutable_tracked:
        check(subprocess.run(["git", "diff", "--quiet", "HEAD", "--", rel],
                             cwd=ROOT).returncode == 0,
              f"immutable tracked change: {rel}")
    check(git("rev-parse", "HEAD:files.qip") ==
          "71d98974f2672207467eac493c06bbc23c74e45b", "production QIP blob")
    check(git("rev-parse", "HEAD:VGM_MD_MiSTer.qsf") ==
          "898ae5a61d7c1f94d9f824a9007fcadff65383f9", "production QSF blob")

    source_assignments = [
        str(path.relative_to(ROOT)) for _, path in core_qip_rows
    ]
    print("HW0_STATIC top=sys_top family=Cyclone_V device=5CSEBA6U23I7 "
          f"sources={len(source_paths)} core_sources={len(source_assignments)}")
    print("HW0_QIP registration=QIP_FILE qsf_qip_file=1 "
          "qsf_direct_source=0 qip_path_expansion=SIMULATED_PASS")
    for source in source_assignments:
        print(f"HW0_SOURCE {source}")
    print("HW0_STATIC board_pin_timing=exact path_audit=PASS "
          "missing=0 duplicate_source=0 duplicate_module=0 absolute=0 "
          "production_files_qip=0 production_emu=0 simulation=0 "
          "diagnostic=0 tmp=0 production_hw0_refs=0 overlay_build_refs=0")
    print(f"HW0_PROTECTION untracked=23 aggregate={protected_digest} "
          "sacred=PASS pristine=15 overlay=PASS jt49=PASS "
          "compatibility=PASS warmup=PASS production=PASS")
    print("HW0_STATIC_PASS")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:  # concise diagnostics for the shell runner
        print(f"HW0_STATIC_FAIL {error}", file=sys.stderr)
        sys.exit(1)
