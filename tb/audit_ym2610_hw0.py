#!/usr/bin/env python3
"""Static, non-Quartus audit for the YM2610 HW-0 project."""

from pathlib import Path
from hashlib import sha256
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "hw" / "ym2610_hw0"
QUARTUS_FILE_ASSIGNMENTS = {
    "IP_FILE", "QIP_FILE", "SDC_FILE", "SYSTEMVERILOG_FILE",
    "VERILOG_FILE", "VHDL_FILE",
}


def check(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def qip_path_rows(path: Path) -> list[tuple[str, Path]]:
    found: list[tuple[str, Path]] = []
    for line in path.read_text().splitlines():
        match = re.search(
            r'\$::quartus\(qip_path\)\s+"?([^"\]\s]+)"?', line)
        if match:
            relative = match.group(1)
            check(not Path(relative).is_absolute(),
                  f"absolute QIP path in {path.name}: {relative}")
            found.append((relative, (path.parent / relative).resolve()))
    return found


def qip_file_rows(path: Path) -> list[tuple[str, str, Path]]:
    found: list[tuple[str, str, Path]] = []
    for line in path.read_text().splitlines():
        assignment = re.search(r"-name\s+([A-Z0-9_]+)", line)
        target = re.search(
            r'\$::quartus\(qip_path\)\s+"?([^"\]\s]+)"?', line)
        if (assignment and target and
                assignment.group(1) in QUARTUS_FILE_ASSIGNMENTS):
            relative = target.group(1)
            check(not Path(relative).is_absolute(),
                  f"absolute QIP path in {path.name}: {relative}")
            found.append((assignment.group(1), relative,
                          (path.parent / relative).resolve()))
    return found


def collect_qip_graph(roots: list[Path]) -> tuple[set[Path],
                                                   list[tuple[str, Path]],
                                                   list[Path]]:
    qips: set[Path] = set()
    leaves: list[tuple[str, Path]] = []
    registrations: list[Path] = list(roots)

    def visit(qip: Path) -> None:
        check(qip.is_file(), f"missing QIP: {qip}")
        if qip in qips:
            return
        qips.add(qip)
        for kind, _, target in qip_file_rows(qip):
            check(target.is_file(), f"missing {kind}: {target}")
            if kind == "QIP_FILE":
                registrations.append(target)
                visit(target)
            else:
                leaves.append((kind, target))

    for root in roots:
        visit(root)
    check(len(registrations) == len(set(registrations)),
          "duplicate PLL QIP registration")
    return qips, leaves, registrations


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
    pll_core_qip = ROOT / "rtl" / "pll.qip"
    pll_hdmi_qip = ROOT / "sys" / "pll_hdmi.qip"
    pll_audio_qip = ROOT / "sys" / "pll_audio.qip"
    pll_cfg_qip = ROOT / "sys" / "pll_cfg.qip"
    production_pll_roots = [
        pll_core_qip, pll_hdmi_qip, pll_audio_qip, pll_cfg_qip,
    ]
    required = [qpf, qsf, core_qip, sys_tcl, sys_qip]
    check(all(path.is_file() for path in required), "missing project file")

    qpf_text = qpf.read_text()
    qsf_text = qsf.read_text()
    core_text = core_qip.read_text()
    hw0_rtl_paths = sorted((ROOT / "rtl" / "ym2610_hw0").glob("*.[sv]*"))
    hw0_rtl_text = "\n".join(path.read_text() for path in hw0_rtl_paths)
    hw0_top_text = (ROOT / "rtl" / "ym2610_hw0" /
                    "ym2610_hw0_top.sv").read_text()
    sequencer_text = (ROOT / "rtl" / "ym2610_hw0" /
                      "ym2610_hw0_sequencer.sv").read_text()
    emu_text = (ROOT / "rtl" / "ym2610_hw0" / "emu.sv").read_text()
    jt12_top_text = (ROOT / "rtl" / "ym2610_hw0" /
                     "ym2610_hw0_jt12_top.v").read_text()
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
    expected_qsf_qips = [
        "../../sys/pll_hdmi.qip", "../../sys/pll_audio.qip",
        "../../sys/pll_cfg.qip", "files_ym2610_hw0.qip",
    ]
    check(qsf_qip_files == expected_qsf_qips,
          "HW-0 QSF QIP_FILE assignment set")
    check(all(not Path(name).is_absolute() for name in qsf_qip_files),
          "HW-0 QIP_FILE assignment is absolute")
    qsf_qip_paths = [(qsf.parent / name).resolve()
                     for name in qsf_qip_files]
    check(all(path.is_file() for path in qsf_qip_paths),
          "missing QSF QIP_FILE target")
    check(len(qsf_qip_paths) == len(set(qsf_qip_paths)),
          "duplicate QSF QIP_FILE target")
    check(qsf_qip_paths[-1] == core_qip.resolve(),
          "HW-0 core QIP path is not relative to its QSF")
    check(not re.search(
        r"\b(?:[A-Za-z_$][A-Za-z0-9_$]*\.)+chon\b", hw0_rtl_text),
        "synthesis-visible hierarchical chon reference")
    hardware_counts = {
        "BOOT_SAMPLES": 159801,
        "COLOR_PREROLL_SAMPLES": 53267,
        "SOUND_DWELL_SAMPLES": 213068,
        "INTER_SILENCE_SAMPLES": 79901,
        "PAN_DWELL_SAMPLES": 159801,
        "PAN_INTER_SAMPLES": 53267,
        "NATURAL_SILENCE_SAMPLES": 79901,
        "FINAL_SILENCE_SAMPLES": 159801,
    }
    for name, value in hardware_counts.items():
        check(re.search(rf"parameter\s+integer\s+{name}\s*=\s*{value}\b",
                        sequencer_text), f"hardware pacing count: {name}")
    check("input  logic               sample_tick" in sequencer_text and
          "sample_strobe" not in sequencer_text and
          "wire sample_rise" not in sequencer_text,
          "sequencer must consume only the canonical sample tick")
    check(re.search(
        r"assign\s+debug_sample_tick\s*=\s*!test_reset\s*&&\s*"
        r"core_sample\s*&&\s*!sample_valid_d\s*;", hw0_top_text),
        "canonical public-sample rising-edge tick")
    check("sample_period_cen != 8'd144" in hw0_top_text and
          "sample_width_cen != 4'd6" in hw0_top_text,
          "sample cadence/width hardware monitor")
    check("posedge clk_sys or posedge reset" in hw0_top_text and
          "test_reset_pipe <= {test_reset_pipe[1:0], 1'b0}" in hw0_top_text,
          "synchronized test reset release")
    check("posedge clk_sys or posedge video_reset" in hw0_top_text and
          ".reset(video_timing_reset)" in hw0_top_text and
          ".phase(reset ? 4'd0 : debug_phase)" in hw0_top_text,
          "video timing/test phase reset separation")
    check("wire video_reset = !pll_locked;" in emu_text and
          "wire reset = RESET | status[0] | !pll_locked;" in emu_text,
          "shell/PLL reset boundary")
    check("ZERO_CONFIRM_SAMPLES = 32" in sequencer_text and
          "zero_run_count+1>=ZERO_CONFIRM_SAMPLES" in sequencer_text,
          "internal zero confirmation before external mute")
    check("chip_cycle_mod432 == 9'd428" in sequencer_text and
          "sample_tick_count[6:0] == 7'd53" in sequencer_text,
          "deterministic JT49 full-tone-cycle alignment")
    check(re.search(
        r"else\s+if\s*\(\s*!adpcmb_roe_n\s*\)\s*"
        r"hw0_adpcmb_request_seen\s*<=\s*1'b1\s*;", jt12_top_text),
        "HW-0 ADPCM-B request latch")
    check(re.search(
        r"assign\s+hw0_adpcmb_active\s*=\s*!rst\s*&&\s*acmd_on_b\s*&&\s*"
        r"!acmd_rst_b\s*&&\s*!adpcmb_flag\s*&&\s*"
        r"\(\s*!adpcmb_roe_n\s*\|\|\s*hw0_adpcmb_request_seen\s*\)\s*;",
        jt12_top_text), "HW-0 ADPCM-B public status routing")
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

    expected_production_pll_q17 = [
        "set_global_assignment -name QIP_FILE           rtl/pll.qip",
        "set_global_assignment -name QIP_FILE           "
        "[file join $::quartus(qip_path) pll_hdmi.qip ]",
        "set_global_assignment -name QIP_FILE           "
        "[file join $::quartus(qip_path) pll_audio.qip ]",
        "set_global_assignment -name QIP_FILE           "
        "[file join $::quartus(qip_path) pll_cfg.qip ]",
    ]
    check((ROOT / "sys" / "pll_q17.qip").read_text().splitlines() ==
          expected_production_pll_q17, "production Quartus 17 PLL bundle")

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
    sys_qip_file_targets = [
        target for kind, _, target in qip_file_rows(sys_qip)
        if kind == "QIP_FILE"
    ]
    check(sys_qip_file_targets == [pll_core_qip.resolve()],
          "HW-0 core PLL registration")
    hw0_pll_roots = sys_qip_file_targets + qsf_qip_paths[:3]
    check(hw0_pll_roots == [path.resolve()
                            for path in production_pll_roots],
          "HW-0 PLL root set differs from production pll_q17")

    pll_qips, pll_leaves, pll_registrations = collect_qip_graph(
        hw0_pll_roots)
    nested_constraints = {
        (ROOT / "rtl" / "pll" / "pll_0002.qip").resolve(),
        (ROOT / "sys" / "pll_hdmi" / "pll_hdmi_0002.qip").resolve(),
        (ROOT / "sys" / "pll_audio" / "pll_audio_0002.qip").resolve(),
    }
    check(nested_constraints.issubset(pll_qips),
          "missing nested PLL constraint QIP")
    check(all("set_instance_assignment -name PLL_" in path.read_text()
              for path in nested_constraints), "missing nested PLL constraint")
    check(not any(kind == "IP_FILE" for kind, _ in pll_leaves),
          "unexpected PLL IP_FILE assignment")
    pll_source_paths = [
        path for kind, path in pll_leaves
        if kind in {"SYSTEMVERILOG_FILE", "VERILOG_FILE", "VHDL_FILE"}
    ]
    check(len(pll_source_paths) == 10, "PLL generated source count")

    base_leaves = [
        target
        for qip in (core_qip, sys_qip)
        for kind, _, target in qip_file_rows(qip)
        if kind != "QIP_FILE"
    ]
    source_paths = base_leaves + [path for _, path in pll_leaves]
    check(len(source_paths) == len(set(source_paths)), "duplicate source path")
    missing = [path for path in source_paths if not path.is_file()]
    check(not missing, "missing source: " + ", ".join(map(str, missing)))

    pll_manifest_text = "\n".join(path.read_text() for path in pll_qips)
    check(not re.search(r"(?:/Users/|[A-Za-z]:[\\/]|/tmp/|/private/tmp/)",
                        pll_manifest_text), "absolute PLL manifest path")
    sys_sdc = ROOT / "sys" / "sys_top.sdc"
    check(sys_sdc in source_paths and
          "derive_pll_clocks" in sys_sdc.read_text() and
          "pll_hdmi|pll_hdmi_inst" in sys_sdc.read_text() and
          "pll_audio|pll_audio_inst" in sys_sdc.read_text(),
          "MiSTer PLL timing constraints")

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
    expected_pll_entities = {
        "pll_hdmi": (ROOT / "sys" / "pll_hdmi.v").resolve(),
        "pll_cfg_hdmi": (ROOT / "sys" / "pll_cfg" /
                         "pll_cfg_hdmi.v").resolve(),
        "pll_audio": (ROOT / "sys" / "pll_audio.v").resolve(),
    }
    check(all(owners.get(entity) == owner
              for entity, owner in expected_pll_entities.items()),
          "undefined or multiply-defined MiSTer PLL entity")

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
    for rel in ["hw/ym2610_hw0/MegaVGMDrive_YM2610_HW0.qpf",
                "hw/ym2610_hw0/MegaVGMDrive_YM2610_HW0.qsf",
                "hw/ym2610_hw0/files_ym2610_hw0.qip",
                "hw/ym2610_hw0/sys_ym2610_hw0.qip",
                "hw/ym2610_hw0/sys_ym2610_hw0.tcl"]:
        check(subprocess.run(["git", "diff", "--quiet", "HEAD", "--", rel],
                             cwd=ROOT).returncode == 0,
              f"frozen HW-0 project change: {rel}")
    check(git("rev-parse", "HEAD:files.qip") ==
          "71d98974f2672207467eac493c06bbc23c74e45b", "production QIP blob")
    check(git("rev-parse", "HEAD:VGM_MD_MiSTer.qsf") ==
          "898ae5a61d7c1f94d9f824a9007fcadff65383f9", "production QSF blob")

    source_assignments = [
        str(path.relative_to(ROOT)) for _, path in core_qip_rows
    ]
    print("HW0_STATIC top=sys_top family=Cyclone_V device=5CSEBA6U23I7 "
          f"sources={len(source_paths)} core_sources={len(source_assignments)} "
          f"pll_sources={len(pll_source_paths)} pll_qips={len(pll_qips)}")
    print("HW0_QIP registration=QIP_FILE qsf_qip_file=4 "
          "qsf_direct_source=0 qip_path_expansion=SIMULATED_PASS")
    print("HW0_PLL_IP production_bundle=4 hw0_bundle=4 missing=0 "
          "entities=pll_hdmi/pll_cfg_hdmi/pll_audio definitions=1/1/1 "
          f"registrations={len(pll_registrations)} nested_constraints=3 "
          "ip_file=0")
    print("HW0_ADPCMB_STATUS request_latch_eos_reset=PASS "
          "hierarchical_chon=0 audio_lifecycle_change=0")
    print("HW0_PACING_STATIC sample_tick=rising_edge cadence_cen=144 "
          "width_cen=6 old_counts_per_sample=1 new_counts_per_sample=1 "
          "boot=159801 preroll=53267 dwell=213068 inter=79901 "
          "pan=159801 pan_inter=53267 natural_inter=79901 final=159801 "
          "reset_release=SYNC video_reset=SEPARATE zero_confirm=32 "
          "ssg_align=428/mod128:53")
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
