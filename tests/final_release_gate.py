#!/usr/bin/env python3
"""Record final regressions and refuse publication eligibility unless all green.

This gate never tags, changes versions, deploys, or publishes anything.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import zipfile
import uuid

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "release"))
import promote_v23 as promotion


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def record_lifecycle(package, evidence):
    # Lima shared mounts may cache an older file even after macOS edits. Copy
    # exact current bytes into a fresh VM-local path; verify before executing.
    vm_root = "/tmp/megavgm-v23-lifecycle-" + uuid.uuid4().hex
    source = ROOT / "tests/phase2_install_gate.py"
    vm_test = vm_root + "/phase2_install_gate.py"
    vm_package = vm_root + "/" + package.name
    shell = ["limactl", "shell", "mister-gcc10"]
    subprocess.run(shell + ["mkdir", vm_root], check=True)
    subprocess.run(["limactl", "copy", str(source), "mister-gcc10:" + vm_test], check=True)
    subprocess.run(["limactl", "copy", "--recursive", str(package), "mister-gcc10:" + vm_package], check=True)
    test_sha = subprocess.check_output(shell + ["sha256sum", vm_test], text=True).split()[0]
    sums_sha = subprocess.check_output(shell + ["sha256sum", vm_package + "/SHA256SUMS"], text=True).split()[0]
    assert test_sha == digest(source) and sums_sha == digest(package / "SHA256SUMS")
    command = shell + ["env", "PYTHONDONTWRITEBYTECODE=1", "python3", "-u", vm_test, vm_package]
    with (evidence / "lifecycle.log").open("w") as handle:
        result = subprocess.run(command, stdout=handle, stderr=subprocess.STDOUT)
    print(f"lifecycle snapshot: exit={result.returncode}", flush=True)
    return {"command": command, "cwd": str(ROOT), "exit_code": result.returncode,
            "log_sha256": digest(evidence / "lifecycle.log"),
            "executed_test_sha256": test_sha, "executed_package_sums_sha256": sums_sha}


def record_tests(package, evidence):
    evidence.mkdir(parents=True, exist_ok=True)
    runtime = ROOT.parent / "MegaVGMPlayer_vNext_4Engine_Runtime"
    jobs = {
        "importer": (["sh", "tests/test_vgm_md_import.sh"], runtime),
        "title": (["sh", "tests/test_megavgm_title_integration.sh"], runtime),
        "autoplay2": (["sh", "tools/megavgm_autoplay2/run_host_tests.sh"], runtime),
        "admission": ([sys.executable, "-B", "tests/test_production_engine_admission_gate.py"], ROOT),
    }
    def run(item):
        name, (command, cwd) = item
        with (evidence / (name + ".log")).open("w") as handle:
            result = subprocess.run(command, cwd=cwd, stdout=handle, stderr=subprocess.STDOUT)
        print(f"{name}: exit={result.returncode}", flush=True)
        return name, {"command": command, "cwd": str(cwd), "exit_code": result.returncode,
                      "log_sha256": digest(evidence / (name + ".log"))}
    with ThreadPoolExecutor(max_workers=3) as pool:
        records = dict(pool.map(run, jobs.items()))
    records["lifecycle"] = record_lifecycle(package, evidence)
    records["package_sums_sha256"] = digest(package / "SHA256SUMS")
    records["lifecycle_test_sha256"] = digest(ROOT / "tests/phase2_install_gate.py")
    (evidence / "results.json").write_text(json.dumps(records, indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("package", type=Path)
    parser.add_argument("--host-build", type=Path, required=True)
    parser.add_argument("--arm-build", type=Path, required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--run-supplemental", action="store_true")
    parser.add_argument("--rerun-lifecycle", action="store_true")
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    package = args.package.resolve()
    if args.run_supplemental:
        record_tests(package, args.evidence.resolve())
    if args.rerun_lifecycle:
        results = json.loads((args.evidence / "results.json").read_text())
        results["lifecycle"] = record_lifecycle(package, args.evidence)
        results["lifecycle_test_sha256"] = digest(ROOT / "tests/phase2_install_gate.py")
        results["package_sums_sha256"] = digest(package / "SHA256SUMS")
        (args.evidence / "results.json").write_text(json.dumps(results, indent=2) + "\n")
    authority, records = promotion.audit()
    promotion.verify(package, records)
    checks = {"authority_manifest_inventory_modes": True,
              "release_version_identity": authority["package_version"] == "2.3" and package.name == "MegaVGMPlayer-v2.3"}
    checks["staging_matches_package"] = (promotion.STAGING / "SHA256SUMS").is_file() and digest(promotion.STAGING / "SHA256SUMS") == digest(package / "SHA256SUMS")
    if checks["staging_matches_package"]:
        promotion.verify(promotion.STAGING, records)
    archive = package.parent / (package.name + ".zip")
    sidecar = archive.with_suffix(".zip.sha256")
    checks["archive_checksum_sidecar"] = archive.is_file() and sidecar.is_file() and sidecar.read_text() == f"{digest(archive)}  {archive.name}\n"
    checks["archive_inventory_hash_modes"] = False
    if archive.is_file():
        files = {str(p.relative_to(package.parent)): p for p in package.rglob("*") if p.is_file()}
        with zipfile.ZipFile(archive) as handle:
            checks["archive_inventory_hash_modes"] = len(handle.namelist()) == len(files) and set(handle.namelist()) == set(files) and all(
                hashlib.sha256(handle.read(name)).hexdigest() == digest(path) and
                handle.getinfo(name).external_attr >> 16 & 0o777 == path.stat().st_mode & 0o777
                for name, path in files.items())
    markers = {
        "sound-chip-tests.txt": "Sound chip stream/package evidence + atomic metadata regression PASS",
        "phase2a-tests.txt": "Phase2A classifier/channel/real-controller + switch-owner integration PASS",
        "playlist-tests.txt": "megavgm_playlist host tests: PASS",
        "supervisor-tests.txt": "megavgm_supervisor host tests: PASS",
        "process-stabilization-tests.txt": "Process stabilization tests: PASS",
        "sid-prepare-tests.txt": "SID preparer bounded cancellation and PID-scoped cleanup tests PASS",
    }
    for label, build in (("host", args.host_build), ("arm_qemu", args.arm_build)):
        checks[label] = all((build / name).is_file() and marker in (build / name).read_text()
                            for name, marker in markers.items())
    checks["arm_classifier_reproducible"] = digest(args.arm_build / "megavgm_classify") == next(r["sha256"] for r in records if r["destination"] == "Scripts/megavgm_classify")
    results = json.loads((args.evidence / "results.json").read_text())
    # Reuse heavy regression evidence only across a proved metadata-only change.
    # Never relabel an old test execution as testing the new package.
    reused = results.get("reused_regressions")
    if reused:
        old_package = Path(reused["package"])
        old_evidence = Path(reused["evidence"])
        old_results = json.loads((old_evidence / "results.json").read_text())
        old_report = json.loads(Path(reused["gate_report"]).read_text())
        old_authority = json.loads((old_package / "provenance/final_authorities.json").read_text())
        checks["reused_evidence_payload_identity"] = (
            old_report["eligible_for_review"] and all(old_report["checks"].values()) and
            old_results["package_sums_sha256"] == digest(old_package / "SHA256SUMS") == reused["package_sums_sha256"] and
            old_authority["payloads"] == authority["payloads"] and
            old_authority["runtime_head"] == authority["runtime_head"] and
            old_authority["embedded_pwa"] == authority["embedded_pwa"] and
            all(digest(old_package / "media/fat" / r["destination"]) == r["sha256"] and
                (old_package / "media/fat" / r["destination"]).stat().st_size == r["bytes"] and
                (old_package / "media/fat" / r["destination"]).stat().st_mode & 0o777 == int(r["mode"], 8)
                for r in records) and
            all(results[name] == old_results[name] and digest(old_evidence / (name + ".log")) == results[name]["log_sha256"]
                for name in ("importer", "title", "autoplay2", "admission")))
    checks["test_evidence_matches_package"] = results["package_sums_sha256"] == digest(package / "SHA256SUMS")
    checks["lifecycle_test_matches_evidence"] = results["lifecycle_test_sha256"] == digest(ROOT / "tests/phase2_install_gate.py")
    checks["lifecycle_exact_vm_snapshot"] = results["lifecycle"].get("executed_test_sha256") == digest(ROOT / "tests/phase2_install_gate.py") and results["lifecycle"].get("executed_package_sums_sha256") == digest(package / "SHA256SUMS")
    expected = {"importer": "All 33 helper metadata tests passed.",
                "title": "near-limit helper trailer accepted by RTL receiver (8388608 bytes)",
                "autoplay2": "megavgm_autoplay2 CLI build/usage: PASS",
                "admission": "PRODUCTION_ENGINE_ADMISSION_REGRESSION_PASS current=A/B/C/D old_d_missing=FAIL old_d_upload_gated=FAIL unelaborated_exporter=FAIL",
                "lifecycle": "ALL INSTALL GATES PASS"}
    for name, marker in expected.items():
        log = args.evidence / (name + ".log")
        checks[name] = results[name]["exit_code"] == 0 and digest(log) == results[name]["log_sha256"] and marker in log.read_text()
    runtime = ROOT.parent / "MegaVGMPlayer_vNext_4Engine_Runtime"
    checks["runtime_exact_head"] = promotion.git(runtime, "rev-parse", "HEAD") == authority["runtime_head"]
    checks["platform_contract_unchanged"] = digest(ROOT.parent / "MegaVGMPlayer_Platform_Contract.md") == "5882e38c362a7138fb12514ed0b9377403d2d73be7dfb96e1b6a7d4f221f319d"
    contract = (ROOT.parent / "MegaVGMPlayer_Engine_Contract.md").read_text()
    checks["engine_contract_final_authorities"] = all(
        r["sha256"] in contract and r["source_head"] in contract
        for r in records if r["destination"].endswith(".rbf")) and authority["runtime_head"] in contract
    checks["engine_contract_admission_result"] = "PRODUCTION_ENGINE_ADMISSION_REGRESSION_PASS current=A/B/C/D old_d_missing=FAIL old_d_upload_gated=FAIL unelaborated_exporter=FAIL" in contract
    checks["engine_contract_snapshot_matches"] = digest(ROOT / "release/ENGINE_CONTRACT_SNAPSHOT.md") == digest(ROOT.parent / "MegaVGMPlayer_Engine_Contract.md")
    dirty = {}
    worktrees = {ROOT, runtime} | {ROOT.parent / r["worktree"] for r in records if "worktree" in r}
    for tree in sorted(worktrees):
        subprocess.run(["git", "-C", str(tree), "diff", "--check"], check=True)
        status = promotion.git(tree, "status", "--porcelain")
        if status:
            dirty[str(tree)] = status
    checks["git_diff_check"] = True
    checks["worktrees_clean"] = not dirty
    report = {"eligible_for_review": all(checks.values()), "publication_executed": False,
              "package_version": authority["package_version"], "package": str(package),
              "runtime_head": authority["runtime_head"], "rc_head": promotion.git(ROOT, "rev-parse", "HEAD"),
              "package_sums_sha256": digest(package / "SHA256SUMS"), "checks": checks, "dirty_worktrees": dirty}
    args.report.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    return 0 if report["eligible_for_review"] else 1


if __name__ == "__main__":
    sys.exit(main())
