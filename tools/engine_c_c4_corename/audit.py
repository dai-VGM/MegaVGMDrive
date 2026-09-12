#!/usr/bin/env python3
"""Audit the C4 validation project's CORENAME-only synthesis delta."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]
BASE = "aaea4d01becafba262b712f148ee092265a932b7"
OLD_NAME = "MegaVGM Engine C C2 Lab"
NEW_NAME = "MegaVGMDrive"
DEFINE = "ENGINE_C_C4_MEGAVGMDRIVE_CORENAME=1"
OLD_QSF = ROOT / "hw/engine_c_c4/MegaVGMPlayer_EngineC_C4_Transport_MiSTer.qsf"
NEW_QSF = ROOT / "hw/engine_c_c4/MegaVGMPlayer_EngineC_C4_Transport_Validation_MiSTer.qsf"
EMU = ROOT / "rtl/engine_c_c2/shell/emu_c2.sv"


def run(*args: str) -> str:
    return subprocess.check_output(args, cwd=ROOT, text=True)


def resolve(qsf: Path) -> list[tuple[str, str]]:
    output = run("tclsh", "tools/engine_c_c2/audit_qsf.tcl", str(qsf))
    return [tuple(line.split("\t", 1)) for line in output.splitlines()]


def preprocess(extra_define: bool) -> str:
    with tempfile.NamedTemporaryFile(prefix="c4-corename-", delete=False) as output:
        output_path = Path(output.name)
    try:
        command = ["iverilog", "-E", "-g2012", "-I.", "-Itb"]
        if extra_define:
            command.append("-D" + DEFINE)
        command += ["-o", str(output_path), str(EMU)]
        subprocess.run(command, cwd=ROOT, check=True)
        return output_path.read_text()
    finally:
        output_path.unlink(missing_ok=True)


def assignments(path: Path) -> list[str]:
    return [line for line in path.read_text().splitlines()
            if line and not line.startswith("#")]


def effective_conf_literals(preprocessed: str) -> list[str]:
    start = preprocessed.index("localparam CONF_STR = {")
    end = preprocessed.index("    };", start)
    return re.findall(r'"([^"\\]*(?:\\.[^"\\]*)*)"', preprocessed[start:end])


def main() -> None:
    base_source = run("git", "show", f"{BASE}:rtl/engine_c_c2/shell/emu_c2.sv")
    replacement = (
        "`ifdef ENGINE_C_C4_MEGAVGMDRIVE_CORENAME\n"
        '        "MegaVGMDrive;;",\n'
        "`else\n"
        '        "MegaVGM Engine C C2 Lab;;",\n'
        "`endif"
    )
    expected_source = base_source.replace(
        '        "MegaVGM Engine C C2 Lab;;",', replacement, 1)
    assert expected_source == EMU.read_text(), "emu delta is not CORENAME-only"

    old_preprocessed = preprocess(False)
    new_preprocessed = preprocess(True)
    old_conf = effective_conf_literals(old_preprocessed)
    new_conf = effective_conf_literals(new_preprocessed)
    assert old_conf[0] == OLD_NAME + ";;"
    assert new_conf[0] == NEW_NAME + ";;"
    assert old_conf[1:] == new_conf[1:], "CONF_STR changed beyond CORENAME"

    old_assignments = assignments(OLD_QSF)
    normalized_new = []
    for line in assignments(NEW_QSF):
        if line == f'set_global_assignment -name VERILOG_MACRO "{DEFINE}"':
            continue
        normalized_new.append(line.replace(
            "PROJECT_OUTPUT_DIRECTORY output_files_validation",
            "PROJECT_OUTPUT_DIRECTORY output_files"))
    assert normalized_new == old_assignments, "QSF differs beyond output directory and CORENAME define"

    old_entries = resolve(OLD_QSF)
    new_entries = resolve(NEW_QSF)
    source_keys = {"SYSTEMVERILOG_FILE", "VERILOG_FILE", "VHDL_FILE", "SDC_FILE", "QIP_FILE"}
    old_sources = [(kind, str(Path(path).relative_to(ROOT)))
                   for kind, path in old_entries if kind in source_keys]
    new_sources = [(kind, str(Path(path).relative_to(ROOT)))
                   for kind, path in new_entries if kind in source_keys]
    assert old_sources == new_sources, "QSF/QIP source set or order changed"
    assert len(new_sources) == len(set(new_sources)), "duplicate validation source assignment"

    old_macros = [value for kind, value in old_entries if kind == "MACRO"]
    new_macros = [value for kind, value in new_entries if kind == "MACRO"]
    assert [value for value in new_macros if value != DEFINE] == old_macros
    assert new_macros.count(DEFINE) == 1

    hdl_paths = [Path(path) for kind, path in new_entries
                 if kind in {"SYSTEMVERILOG_FILE", "VERILOG_FILE", "VHDL_FILE"}]
    core_sources = [str(path) for path in hdl_paths
                    if str(path.relative_to(ROOT)).startswith("rtl/")
                    and "/pll" not in str(path)]
    subprocess.run([
        "verilator", "--lint-only", "--timing", "-Wno-fatal",
        "--top-module", "emu", "-I.", "-Itb",
        *("+define+" + macro for macro in new_macros),
        "tools/engine_c_c4/hps_io_elab_stub.sv",
        "tb/megavgm_pll_elab_stubs.sv", *core_sources,
    ], cwd=ROOT, check=True, stdout=subprocess.DEVNULL,
       stderr=subprocess.DEVNULL)

    frozen = [
        "rtl/engine_c_c4/transport.sv",
        "rtl/engine_c_c4/megavgm_playlist_status_export.sv",
        "rtl/engine_c_c4/sid_native_scheduler.sv",
        "rtl/engine_c_c4/engine_c_lab.sv",
        "rtl/engine_c_c2/sid_session_wrapper.sv",
    ]
    frozen_hashes = {}
    for relative in frozen:
        current = (ROOT / relative).read_bytes()
        base = subprocess.check_output(["git", "show", f"{BASE}:{relative}"], cwd=ROOT)
        assert current == base, relative
        frozen_hashes[relative] = hashlib.sha256(current).hexdigest()

    changed_rtl = [path for path in run("git", "diff", "--name-only", BASE, "--", "rtl").splitlines()]
    assert changed_rtl == ["rtl/engine_c_c2/shell/emu_c2.sv"], changed_rtl

    report = {
        "base": BASE,
        "old_corename": OLD_NAME,
        "new_corename": NEW_NAME,
        "effective_conf_str_delta": "CORENAME only",
        "qsf_qip_source_set_equal": True,
        "resolved_source_entries": len(new_sources),
        "validation_only_macro": DEFINE,
        "old_project_retains_old_corename": True,
        "validation_emu_elaboration": "PASS (Verilator, not Quartus)",
        "transport_status_sid_rtl_unchanged": frozen_hashes,
    }
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
