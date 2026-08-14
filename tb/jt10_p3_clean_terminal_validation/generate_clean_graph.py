#!/usr/bin/env python3
"""Generate the isolated P3 clean graph without touching historical outputs."""
from __future__ import annotations

import hashlib
import importlib.util
import os
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[2]
P3 = ROOT / "tb/jt10_phase_monitor_contract_fix/candidates/p3_combined.sv"
WRAPPER = ROOT / "tb/jt10_final_public_zero_dwell/candidates/s3_v3_wrapper.sv"
EXTRACTOR = ROOT / "tb/jt10_gatee_h_selector_passthrough_v2/extract_canonical_pr.py"
OUT = Path(__file__).resolve().parent / "generated"
P3_SHA = "0f069a9b83da3623440bac7f1360c9f8d89ccd47099370f5e3322034511ebf7c"
CANONICAL_SHA = "84255d408ae6905fe950c80bce29cbb43956ad95d3d79056989a4e21be890ba8"


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def write_if_changed(path: Path, data: bytes) -> bool:
    if path.is_file() and path.read_bytes() == data:
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_bytes(data)
    os.replace(temporary, path)
    return True


def main() -> None:
    spec = importlib.util.spec_from_file_location("p3_clean_extractor", EXTRACTOR)
    if spec is None or spec.loader is None:
        raise SystemExit("canonical extractor unavailable")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    source = module.SOURCE.read_bytes()
    if digest(source) != module.SOURCE_SHA256:
        raise SystemExit("canonical input SHA mismatch")
    canonical, _ = module.build_extraction(source)
    if digest(canonical) != CANONICAL_SHA or len(canonical) != 13865:
        raise SystemExit("canonical output SHA mismatch")

    top = P3.read_text()
    if digest(top.encode()) != P3_SHA:
        raise SystemExit("P3 candidate SHA mismatch")
    top = top.replace("module jt10_final_public_zero_s4_top;", "module jt10_p3_clean_isolated_s4_top;", 1)
    old_terminal = (
        '        if (failures != 0) $fatal(1, "HW0 failed (%0d)", failures);\n'
        '        $display("HW0_PASS run=%0d", run_id);\n'
        "        $finish;"
    )
    new_terminal = (
        '        $display("P3_CLEAN_LEGACY_SUMMARY failures=%0d", failures);\n'
        "        // Target-only P3 observer owns terminal acceptance and termination."
    )
    if top.count(old_terminal) != 1:
        raise SystemExit("aggregate terminal transform ambiguity")
    top = top.replace(old_terminal, new_terminal, 1).encode()

    wrapper = WRAPPER.read_text()
    if wrapper.count("module jt10_final_public_zero_v3_wrapper;") != 1 or wrapper.count("jt10_final_public_zero_s4_top base();") != 1:
        raise SystemExit("wrapper transform ambiguity")
    wrapper = wrapper.replace("module jt10_final_public_zero_v3_wrapper;", "module jt10_p3_clean_isolated_v3_wrapper;", 1)
    wrapper = wrapper.replace("jt10_final_public_zero_s4_top base();", "jt10_p3_clean_isolated_s4_top base();", 1).encode()

    changed = {
        "canonical_pr": write_if_changed(OUT / "canonical_pr.sv", canonical),
        "clean_top": write_if_changed(OUT / "p3_clean_s4_top.sv", top),
        "clean_wrapper": write_if_changed(OUT / "p3_clean_v3_wrapper.sv", wrapper),
    }
    print("P3_CLEAN_ISOLATED_GENERATED " + " ".join(f"{key}_written={int(value)}" for key, value in changed.items()) +
          f" canonical_sha={CANONICAL_SHA} top_sha={digest(top)} wrapper_sha={digest(wrapper)}")


if __name__ == "__main__":
    main()
