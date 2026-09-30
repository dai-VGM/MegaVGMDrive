#!/usr/bin/env python3
"""Regression tests for current engines and both historical Engine D faults."""

from pathlib import Path
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
GATE = ROOT / "tests/production_engine_admission_gate.py"
FIXTURES = ROOT / "tests/fixtures/production_engine_admission"


def run(registry: Path | None = None) -> subprocess.CompletedProcess[str]:
    command = [sys.executable, str(GATE)]
    if registry is not None:
        command += [
            "--registry", str(registry),
            "--projects-root", str(FIXTURES),
        ]
    return subprocess.run(command, cwd=ROOT, text=True, capture_output=True)


current = run()
assert current.returncode == 0, current.stdout + current.stderr
for engine in "ABCD":
    assert f"ENGINE_{engine}_ADMISSION_PASS" in current.stdout, current.stdout

missing = run(FIXTURES / "old_d_missing_status/registry.json")
assert missing.returncode != 0, missing.stdout
assert "missing-status-exporter-source" in missing.stdout, missing.stdout
assert "missing-standard-status-macro" in missing.stdout, missing.stdout

gated = run(FIXTURES / "old_d_upload_gated/registry.json")
assert gated.returncode != 0, gated.stdout
assert "no-preupload-ready-expression" in gated.stdout, gated.stdout
assert "missing-lifecycle-evidence" in gated.stdout, gated.stdout

print("PRODUCTION_ENGINE_ADMISSION_REGRESSION_PASS "
      "current=A/B/C/D old_d_missing=FAIL old_d_upload_gated=FAIL")
