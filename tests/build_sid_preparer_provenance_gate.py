#!/usr/bin/env python3
"""Regression tests for the production SID preparer checkout guard."""
from pathlib import Path
import os
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
GUARD = ROOT / "release/build_sid_preparer_arm.sh"


def run(*args: str, ok: bool) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        [str(GUARD), *args], text=True, capture_output=True, env=os.environ
    )
    assert (result.returncode == 0) == ok, (
        result.returncode,
        result.stdout,
        result.stderr,
    )
    return result


with tempfile.TemporaryDirectory(prefix="megavgm-preparer-provenance-") as temporary:
    checkout = Path(temporary) / "checkout"
    subprocess.run(["git", "init", "-q", str(checkout)], check=True)
    subprocess.run(["git", "-C", str(checkout), "config", "user.name", "Test"], check=True)
    subprocess.run(
        ["git", "-C", str(checkout), "config", "user.email", "test@example.invalid"],
        check=True,
    )
    build = checkout / "tools/engine_c_c6/build_arm.sh"
    build.parent.mkdir(parents=True)
    build.write_text(
        "#!/bin/sh\n"
        "set -eu\n"
        "printf '%s\\n' \"$MEGAVGM_EXPECTED_SOURCE_COMMIT\"\n"
    )
    build.chmod(0o755)
    subprocess.run(["git", "-C", str(checkout), "add", "."], check=True)
    subprocess.run(["git", "-C", str(checkout), "commit", "-qm", "fixture"], check=True)
    head = subprocess.check_output(
        ["git", "-C", str(checkout), "rev-parse", "HEAD"], text=True
    ).strip()

    passed = run(head, str(checkout), ok=True)
    assert passed.stdout.strip() == head

    mismatch = "0" * 40 if head != "0" * 40 else "1" * 40
    failed = run(mismatch, str(checkout), ok=False)
    assert "source commit mismatch" in failed.stderr

    short = run(head[:12], str(checkout), ok=False)
    assert "full 40-character" in short.stderr

    tracked = checkout / "tracked-dirty"
    tracked.write_text("dirty\n")
    subprocess.run(["git", "-C", str(checkout), "add", "tracked-dirty"], check=True)
    failed = run(head, str(checkout), ok=False)
    assert "source checkout is dirty" in failed.stderr
    subprocess.run(["git", "-C", str(checkout), "reset", "-q", "HEAD", "tracked-dirty"], check=True)
    tracked.unlink()

    untracked = checkout / "untracked-dirty"
    untracked.write_text("dirty\n")
    failed = run(head, str(checkout), ok=False)
    assert "source checkout is dirty" in failed.stderr
    untracked.unlink()

print("correct HEAD build, mismatch, short SHA, tracked/untracked dirty rejection PASS")
