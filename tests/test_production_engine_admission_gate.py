#!/usr/bin/env python3
"""Regression tests for current engines and both historical Engine D faults."""

from pathlib import Path
import json
import shutil
import subprocess
import sys
import tempfile

import production_engine_admission_gate as gate


ROOT = Path(__file__).resolve().parents[1]
GATE = ROOT / "tests/production_engine_admission_gate.py"
FIXTURES = ROOT / "tests/fixtures/production_engine_admission"


def run(registry: Path | None = None,
        projects_root: Path = FIXTURES) -> subprocess.CompletedProcess[str]:
    command = [sys.executable, str(GATE)]
    if registry is not None:
        command += [
            "--registry", str(registry),
            "--projects-root", str(projects_root),
        ]
    return subprocess.run(command, cwd=ROOT, text=True, capture_output=True)


current = run()
assert current.returncode == 0, current.stdout + current.stderr
for engine in "ABCD":
    assert f"ENGINE_{engine}_ADMISSION_PASS" in current.stdout, current.stdout
assert "PRODUCTION_ENGINE_ADMISSION_PASS engines=A,B,C,D" in current.stdout

# The lexical fallback accepts both legal instantiation forms and ignores
# names found only in comments. Nested parameter expressions are balanced.
plain = "megavgm_playlist_status_export publisher (.clk(clk));"
parameterized = """
megavgm_playlist_status_export #(
    .IDLE_REPUBLISH_CYCLES((20 * (1_000_000)))
) playlist_status_export (.clk(clk));
"""
comments = """
// megavgm_playlist_status_export fake_line (.clk(clk));
/* megavgm_playlist_status_export #(.P(1)) fake_block (.clk(clk)); */
"""
assert gate.sv_module_instances(plain, gate.STATUS_EXPORTER_MODULE) == [
    "publisher"]
assert gate.sv_module_instances(
    parameterized, gate.STATUS_EXPORTER_MODULE) == ["playlist_status_export"]
assert gate.sv_module_instances(comments, gate.STATUS_EXPORTER_MODULE) == []

missing = run(FIXTURES / "old_d_missing_status/registry.json")
assert missing.returncode != 0, missing.stdout
assert "missing-status-exporter-source" in missing.stdout, missing.stdout
assert "missing-standard-status-macro" in missing.stdout, missing.stdout

gated = run(FIXTURES / "old_d_upload_gated/registry.json")
assert gated.returncode != 0, gated.stdout
assert "no-preupload-ready-expression" in gated.stdout, gated.stdout
for missing_contract in (
    "mode5_playback_session_id = profile_status_session_id",
    "mode5_done_session_id = profile_status_done_session_id",
    "vgm_error_session_id = profile_status_error_session_id",
    "vgm_loop_valid_debug = profile_status_loop_valid",
    "vgm_loop_boundary_pulse_debug = profile_status_loop_boundary_pulse",
):
    assert "missing-lifecycle-evidence:" in gated.stdout, gated.stdout
    assert missing_contract in gated.stdout, gated.stdout

# A registered but unreachable source must not satisfy the instance check.
# Only the production-shell path or a declared elaboration assertion counts.
with tempfile.TemporaryDirectory(prefix="megavgm-admission-") as temporary:
    temporary_root = Path(temporary)
    fixture_root = temporary_root / "unelaborated_exporter"
    shutil.copytree(FIXTURES / "old_d_upload_gated", fixture_root)
    registry = json.loads((fixture_root / "registry.json").read_text())
    registry["engines"][0]["source_worktree"] = "unelaborated_exporter"
    (fixture_root / "registry.json").write_text(json.dumps(registry, indent=2))
    (fixture_root / "rtl/emu.sv").write_text("""
module emu;
    localparam CONF_STR = {"MegaVGMDrive;;"};
    hps_io hps_io (.status_in(status_in), .status_set(status_set));
    // megavgm_playlist_status_export commented_out (.status_in(status_in));
endmodule
""")
    (fixture_root / "rtl/unelaborated.sv").write_text("""
module never_instantiated;
    megavgm_playlist_status_export hidden (.status_in(status_in));
endmodule
""")
    with (fixture_root / "files_engine_d_c140.qip").open("a") as qip:
        qip.write("\nset_global_assignment -name SYSTEMVERILOG_FILE "
                  "rtl/unelaborated.sv\n")
    unelaborated = run(fixture_root / "registry.json", temporary_root)
    assert unelaborated.returncode != 0, unelaborated.stdout
    assert "status-exporter-instance-count: 0" in unelaborated.stdout, \
        unelaborated.stdout

print("PRODUCTION_ENGINE_ADMISSION_REGRESSION_PASS "
      "current=A/B/C/D old_d_missing=FAIL old_d_upload_gated=FAIL "
      "unelaborated_exporter=FAIL")
