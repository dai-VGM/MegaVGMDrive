#!/usr/bin/env python3
"""Run the staged Z0--Z3 semantic ZERO-attempt validation gates."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[2]
SCOPE = ROOT / "tb/jt10_semantic_zero_attempt_normalize"
DOCS = ROOT / "docs/jt10_semantic_zero_attempt_normalize"
BRANCH = "jt10-gatee-te-ownership-fix"
HEAD = "b531ed016c7d1f701f5c00501e995db756629a72"
BASELINE = DOCS / "BASELINE_496_START.tsv"
QUARANTINE = DOCS / "QUARANTINE_19_V2_START.tsv"
FROZEN_MANIFEST = DOCS / "FROZEN_ASSETS_V2_START.tsv"
STASH = DOCS / "STASH_4_V2_START.tsv"
ALLOWED = (
    "tb/jt10_semantic_zero_attempt_normalize/",
    "docs/jt10_semantic_zero_attempt_normalize/",
)

PACKAGE = "tb/jt10_semantic_timeline_monitor/semantic_timeline_authority_pkg.sv"
R3 = "tb/jt10_semantic_timeline_epoch_rearm/candidates/r3_epoch_fixed.sv"
SOURCE = "tb/jt10_semantic_timeline_adapter_knownfix/candidates/a1_named_wire.sv"
SOURCE_SHA = "8e410f0fcf989049d3b39e7c4cc91b011f4a2cf67c2c92adec1a752bc1186ff6"
CANDIDATES = {
    0: "tb/jt10_semantic_zero_attempt_normalize/candidates/z0_frozen.sv",
    1: "tb/jt10_semantic_zero_attempt_normalize/candidates/z1_fm_zero.sv",
    2: "tb/jt10_semantic_zero_attempt_normalize/candidates/z2_ssg_zero.sv",
    3: "tb/jt10_semantic_zero_attempt_normalize/candidates/z3_fm_ssg_zero.sv",
}
GENERATOR = SCOPE / "generate_candidates.py"

CORE = "tb/jt10_gatee_monitor_fix/core_sources.f"
FROZEN_GRAPH = [
    "rtl/genesis_audio/jt10_ym2610_adpcma_command_reset_fix/candidates/b7_guard_counter_lane_reset.v",
    "rtl/genesis_audio/jt10_ym2610_sparse_cen_fix/jt10_adpcm_drvB.v",
    "tb/jt10_semantic_silence_contract_fix/semantic_silence_monitor.sv",
    "tb/jt10_semantic_silence_contract_fix/s4_integrated_semantic.sv",
]
V3_GRAPH = [
    "tb/jt10_gatee_h4_bnd_gate_v3/candidates/v3_bnd_counter_gate.sv",
    "tb/jt10_gatee_h_selector_only/gatee_h_selector_only.sv",
    "tb/jt10_gatee_v3_epoch_integration/gatee_v3_epoch_interface.sv",
    "tb/jt10_gatee_v3_epoch_integration/v3_epoch_integrated_harness.sv",
]
EPOCH_HARNESS = "tb/jt10_semantic_timeline_epoch_rearm/epoch_rearm_integrated_harness.sv"
EXTRACTOR = ROOT / "tb/jt10_gatee_h_selector_passthrough_v2/extract_canonical_pr.py"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def git_text(*args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


def read_manifest(path: Path) -> dict[str, tuple[str, int, int, int]]:
    with path.open(newline="") as source:
        rows = csv.DictReader(source, delimiter="\t")
        return {
            row["path"]: (
                row["sha256"], int(row["size"]),
                int(row["mtime_ns"]), int(row["inode"]),
            )
            for row in rows
        }


def identity(path: Path) -> tuple[str, int, int, int]:
    stat = path.stat()
    return sha256(path), stat.st_size, stat.st_mtime_ns, stat.st_ino


def verify_manifest(path: Path, count: int) -> None:
    manifest = read_manifest(path)
    if len(manifest) != count:
        raise SystemExit(f"{path.name} count {len(manifest)} != {count}")
    for relative, expected in manifest.items():
        target = ROOT / relative
        if not target.is_file() or identity(target) != expected:
            raise SystemExit(f"protected identity changed: {relative}")


def verify_stash() -> None:
    rows = []
    for line in STASH.read_text().splitlines():
        index, object_sha, patch_sha = line.split("\t")
        rows.append((int(index), object_sha, patch_sha))
    if len(rows) != 4 or len(git_text("stash", "list").splitlines()) != 4:
        raise SystemExit("stash count mismatch")
    for index, object_sha, patch_sha in rows:
        if git_text("rev-parse", f"stash@{{{index}}}") != object_sha:
            raise SystemExit(f"stash object changed: {index}")
        patch = subprocess.check_output(
            ["git", "stash", "show", "-p", "--include-untracked",
             f"stash@{{{index}}}"], cwd=ROOT,
        )
        if sha256_bytes(patch) != patch_sha:
            raise SystemExit(f"stash patch changed: {index}")


def preservation() -> dict[str, int]:
    if git_text("branch", "--show-current") != BRANCH:
        raise SystemExit("branch mismatch")
    if git_text("rev-parse", "HEAD") != HEAD:
        raise SystemExit("HEAD mismatch")
    if git_text("diff", "--name-only") or git_text("diff", "--cached", "--name-only"):
        raise SystemExit("tracked/staged diff is not clean")
    verify_manifest(BASELINE, 496)
    verify_manifest(QUARANTINE, 19)
    verify_manifest(FROZEN_MANIFEST, 37)
    verify_stash()
    raw = subprocess.check_output(
        ["git", "ls-files", "--others", "--exclude-standard", "-z"],
        cwd=ROOT,
    ).decode().split("\0")
    untracked = set(filter(None, raw))
    baseline = set(read_manifest(BASELINE))
    if not baseline.issubset(untracked):
        raise SystemExit("starting baseline path left untracked set")
    unexpected = {
        path for path in untracked - baseline
        if not path.startswith(ALLOWED)
    }
    if unexpected:
        raise SystemExit(f"unexpected new path: {sorted(unexpected)}")
    return {"baseline": 496, "quarantine": 19,
            "frozen_assets": 37, "untracked": len(untracked), "stash": 4}


def run_logged(command: list[str], artifact: Path, stem: str,
               env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        command, cwd=ROOT, text=True, capture_output=True, check=False, env=env,
    )
    (artifact / f"{stem}.stdout.log").write_text(result.stdout)
    (artifact / f"{stem}.stderr.log").write_text(result.stderr)
    return result


def compile_ok(result: subprocess.CompletedProcess[str]) -> bool:
    text = result.stdout + result.stderr
    return (result.returncode == 0 and
            "has already been declared" not in text and
            "Unknown module type" not in text)


def artifact_dir(requested: Path | None, label: str) -> Path:
    if requested is None:
        return Path(tempfile.mkdtemp(prefix=f"jt10-zero-attempt-{label}."))
    target = requested.resolve()
    target.mkdir(parents=True, exist_ok=False)
    return target


def generation_identity() -> dict[str, str]:
    generated: list[dict[str, str]] = []
    for _ in range(2):
        with tempfile.TemporaryDirectory(prefix="jt10-zero-gen.") as temp_text:
            temp = Path(temp_text)
            result = subprocess.run(
                [sys.executable, "-B", str(GENERATOR),
                 "--output-dir", str(temp / "candidates"),
                 "--manifest", str(temp / "manifest.json")],
                cwd=ROOT, text=True, capture_output=True, check=False,
            )
            if result.returncode != 0:
                raise SystemExit(result.stderr or result.stdout)
            generated.append({
                path.name: sha256(path)
                for path in sorted((temp / "candidates").iterdir())
            })
    if generated[0] != generated[1]:
        raise SystemExit("candidate generation is not deterministic")
    versioned = {
        Path(relative).name: sha256(ROOT / relative)
        for relative in CANDIDATES.values()
    }
    if generated[0] != versioned:
        raise SystemExit("versioned candidates differ from generator")
    return versioned


def static_audit() -> dict[str, object]:
    preserved = preservation()
    generated = generation_identity()
    source = (ROOT / SOURCE).read_text()
    z0 = (ROOT / CANDIDATES[0]).read_text()
    z1 = (ROOT / CANDIDATES[1]).read_text()
    z2 = (ROOT / CANDIDATES[2]).read_text()
    z3 = (ROOT / CANDIDATES[3]).read_text()
    helper_start = z3.index("    // Z-series seam:")
    helper_end = z3.index("    task automatic adapter_failure", helper_start)
    restored = z3[:helper_start] + z3[helper_end:]
    call = """                                zero_attempt_matches(
                                    family_i[3:0], attempt_i[2:0],
                                    raw_attempt)) begin
"""
    original = """                                raw_attempt == expected_raw_attempt(
                                    family_i[3:0], attempt_i[2:0], K_ZERO)) begin
"""
    if restored.count(call) != 1:
        raise SystemExit("Z3 ZERO call count changed")
    restored = restored.replace(call, original, 1)
    candidate_text = "\n".join((z0, z1, z2, z3))
    source_sha_ok = sha256(ROOT / SOURCE) == SOURCE_SHA
    checks = {
        "z0_exact": z0 == source,
        "z3_restores_to_a1": restored == source,
        "z1_fm_only": "if (family == F_FM)" in z1 and "if (family == F_SSG)" not in z1,
        "z2_ssg_only": "if (family == F_SSG)" in z2 and "if (family == F_FM)" not in z2,
        "z3_existing_cardinality_authority":
            "if (family_attempt_count(family) == 1)" in z3,
        "same_start_stop_helper_reused":
            "normalize_attempt(family, raw) == semantic_attempt" in z3,
        "expanded_raw_comparison_preserved":
            "raw == expected_raw_attempt(\n                    family, semantic_attempt, K_ZERO)" in z3,
        "named_qualifier_unchanged": source[source.index("    wire [21:0]"):
            source.index("    function automatic logic [2:0]")] ==
            z3[z3.index("    wire [21:0]"):
               z3.index("    function automatic logic [2:0]")],
        "source_sha": source_sha_ok,
        "module_once_each": all(
            (ROOT / relative).read_text().count(
                "module semantic_timeline_adapter (") == 1
            for relative in CANDIDATES.values()
        ),
        "expected_slot_input_zero": "expected_slot" not in candidate_text,
        "failure_suppression_zero": not re.search(
            r"if\s*\([^\n]*failures[^\n]*\)\s*failures\s*=\s*0",
            candidate_text),
        "force_release_zero": not re.search(
            r"\b(?:force|release)\b", candidate_text),
        "absolute_hdl_path_zero":
            "/Users/" not in candidate_text and "/private/tmp" not in candidate_text,
    }
    if not all(checks.values()):
        raise SystemExit(f"static checks failed: {checks}")
    return {"preservation": preserved, "candidates": generated,
            "checks": checks}


def compile_run_variant(mode: int, tb: str, top: str, artifact: Path,
                        stem: str, include_r3: bool = False) -> dict[str, object]:
    image = artifact / f"{stem}.vvp"
    sources = [PACKAGE, CANDIDATES[mode]]
    if include_r3:
        sources.append(R3)
    sources.append(tb)
    command = [
        "iverilog", "-g2012", "-Wall", f"-DZMODE={mode}",
        "-s", top, "-o", str(image), *sources,
    ]
    compiled = run_logged(command, artifact, f"{stem}.compile")
    run = subprocess.CompletedProcess([], 1, "", "compile failed")
    if compile_ok(compiled):
        run = run_logged(["vvp", str(image)], artifact, f"{stem}.run")
    return {
        "compile_rc": compiled.returncode,
        "compile_pass": compile_ok(compiled),
        "run_rc": run.returncode,
        "stdout": run.stdout,
        "stderr": run.stderr,
        "image_sha256": sha256(image) if image.is_file() else None,
    }


def unit_gate(requested: Path | None) -> int:
    static = static_audit()
    artifact = artifact_dir(requested, "unit")
    results: dict[str, object] = {}
    passed = True
    for mode in range(4):
        item = compile_run_variant(
            mode,
            "tb/jt10_semantic_zero_attempt_normalize/tb_adapter_unit.sv",
            "tb_jt10_semantic_zero_attempt_adapter_unit",
            artifact, f"z{mode}",
        )
        output = item.pop("stdout") + item.pop("stderr")
        ok = (item["compile_pass"] and item["run_rc"] == 0 and
              output.count(f"ADAPTER_UNIT_PASS mode={mode}") == 1 and
              output.count("ADAPTER_ZERO_CASE_PASS") == 10 and
              output.count("ADAPTER_INVALID_PASS") == 5 and
              "FATAL:" not in output)
        item["passed"] = ok
        item["output_sha256"] = sha256_bytes(output.encode())
        results[f"z{mode}"] = item
        passed = passed and ok
    payload = {"gate": "D", "passed": passed, "static": static,
               "results": results, "compile_count": 4,
               "simulation_count": 4}
    (artifact / "result.json").write_text(json.dumps(payload, indent=2) + "\n")
    print(f"ZERO_ATTEMPT_GATE_D {'PASS' if passed else 'FAIL'} artifact={artifact}")
    return 0 if passed else 1


def negative_gate(requested: Path | None) -> int:
    static = static_audit()
    artifact = artifact_dir(requested, "negative")
    item = compile_run_variant(
        3,
        "tb/jt10_semantic_zero_attempt_normalize/tb_two_layer_negative.sv",
        "tb_jt10_semantic_zero_attempt_two_layer_negative",
        artifact, "z3", include_r3=True,
    )
    output = item.pop("stdout") + item.pop("stderr")
    passed = (item["compile_pass"] and item["run_rc"] == 0 and
              output.count("LAYER_A_PASS") == 3 and
              output.count("LAYER_B_PASS") == 4 and
              output.count("PROGRAM_AUTHORITY_PASS") == 1 and
              output.count("PHASE_AUTHORITY_PASS") == 1 and
              output.count("DUPLICATE_AUTHORITY_PASS") == 1 and
              output.count("ORDER_AUTHORITY_PASS") == 1 and
              output.count("TWO_LAYER_NEGATIVE_PASS") == 1 and
              "FATAL:" not in output)
    item["passed"] = passed
    item["output_sha256"] = sha256_bytes(output.encode())
    payload = {"gate": "E/F", "passed": passed, "static": static,
               "result": item, "compile_count": 1, "simulation_count": 1}
    (artifact / "result.json").write_text(json.dumps(payload, indent=2) + "\n")
    print(output, end="")
    print(f"ZERO_ATTEMPT_GATE_EF {'PASS' if passed else 'FAIL'} artifact={artifact}")
    return 0 if passed else 1


def offline_gate(requested: Path | None) -> int:
    static = static_audit()
    artifact = artifact_dir(requested, "offline")
    results: dict[str, object] = {}
    passed = True
    expected = {0: (62, 2), 1: (63, 1), 2: (63, 1), 3: (64, 0)}
    for mode in range(4):
        item = compile_run_variant(
            mode,
            "tb/jt10_semantic_zero_attempt_normalize/tb_offline_replay.sv",
            "tb_jt10_semantic_zero_attempt_offline_replay",
            artifact, f"z{mode}", include_r3=True,
        )
        output = item.pop("stdout") + item.pop("stderr")
        zero, failures = expected[mode]
        marker = (f"OFFLINE_REPLAY_PASS mode={mode} A1=64/64/{zero} "
                  f"failures={failures}")
        ok = (item["compile_pass"] and item["run_rc"] == 0 and
              output.count(marker) == 1 and "FATAL:" not in output)
        item["passed"] = ok
        item["output_sha256"] = sha256_bytes(output.encode())
        results[f"z{mode}"] = item
        passed = passed and ok
    payload = {"gate": "G", "passed": passed, "static": static,
               "artifact_authority": {
                   "loop1_fm_zero": "state10 phase0 raw2",
                   "loop1_ssg_zero": "state18 phase0 raw2",
                   "terminal_snapshot_stdout_sha256":
                       "3eed12a1308a040ee10cb824bf8dadf481bcb06eda6777dcf243045e37fbbd11",
                   "gate_g_stdout_sha256":
                       "a1ae2079211348265d5b2b6f1d94062ea8ce55c3888227f6ccc636d5927a0605",
               },
               "results": results, "compile_count": 4,
               "simulation_count": 4}
    (artifact / "result.json").write_text(json.dumps(payload, indent=2) + "\n")
    print(f"ZERO_ATTEMPT_GATE_G {'PASS' if passed else 'FAIL'} artifact={artifact}")
    return 0 if passed else 1


def integrated_gate(mode: str, requested: Path | None) -> int:
    static = static_audit()
    artifact = artifact_dir(requested, mode)
    runtime = artifact / "runtime"
    runtime.mkdir()
    pr_source = runtime / "canonical_pr.sv"
    pr_manifest = runtime / "canonical_pr_manifest.json"
    extracted = run_logged([
        sys.executable, "-B", str(EXTRACTOR.relative_to(ROOT)),
        "--output", str(pr_source), "--manifest", str(pr_manifest),
    ], artifact, "extraction")
    if extracted.returncode != 0:
        print(f"ZERO_ATTEMPT_{mode.upper()}_EXTRACTION_FAIL artifact={artifact}")
        return 1

    targeted = mode == "targeted"
    top = ("jt10_semantic_zero_attempt_targeted_top" if targeted else
           "jt10_semantic_timeline_epoch_rearm_two_loop")
    extra = (["tb/jt10_semantic_zero_attempt_normalize/targeted_observer.sv"]
             if targeted else [])
    image = artifact / f"{mode}.vvp"
    normalized_sources = [
        CORE, *FROZEN_GRAPH, "<runtime>/canonical_pr.sv", *V3_GRAPH,
        PACKAGE, CANDIDATES[3], R3, EPOCH_HARNESS, *extra,
    ]
    command = [
        "iverilog", "-g2012", "-Wall", "-DCENFIX_EXPOSED",
        "-DADPCMA_B_HAS_G", "-DSEMANTIC_FAST_SIM=1", "-s", top,
        "-o", str(image), "-f", CORE, *FROZEN_GRAPH, str(pr_source),
        *V3_GRAPH, PACKAGE, CANDIDATES[3], R3, EPOCH_HARNESS, *extra,
    ]
    compiled = run_logged(command, artifact, "compile")
    diagnostics = compiled.stdout + compiled.stderr
    pr_text = pr_source.read_text() if pr_source.is_file() else ""
    compile_checks = {
        "compile_rc_zero": compiled.returncode == 0,
        "duplicate_module_zero": "has already been declared" not in diagnostics,
        "undefined_module_zero": "Unknown module type" not in diagnostics,
        "p_once": pr_text.count("module gatee_phase_token_monitor") == 1,
        "r_once": pr_text.count("module gatee_restart_ownership_monitor") == 1,
        "h_zero_in_extract": "module gatee_bounded_event_monitor" not in pr_text,
        "a1_z3_once": (ROOT / CANDIDATES[3]).read_text().count(
            "module semantic_timeline_adapter (") == 1,
        "r3_once": (ROOT / R3).read_text().count(
            "module semantic_timeline_rearm_r3 #(") == 1,
        "quarantine_zero": all(
            "jt10_gatee_h_selector_integration" not in path
            for path in normalized_sources),
    }
    (artifact / "compile_manifest.json").write_text(json.dumps({
        "mode": mode, "top": top,
        "defines": ["CENFIX_EXPOSED", "ADPCMA_B_HAS_G", "SEMANTIC_FAST_SIM=1"],
        "sources": normalized_sources, "checks": compile_checks,
    }, indent=2) + "\n")
    if not all(compile_checks.values()):
        (artifact / "result.json").write_text(json.dumps({
            "gate": "H" if targeted else "I", "passed": False,
            "simulation_count": 0, "compile_checks": compile_checks,
        }, indent=2) + "\n")
        print(f"ZERO_ATTEMPT_{mode.upper()}_COMPILE_FAIL artifact={artifact}")
        return 1

    run = run_logged(["vvp", str(image), "+RUN_ID=193"], artifact, "run",
                     env=os.environ.copy())
    marker = ("ZERO_ATTEMPT_TARGETED_PASS" if targeted else
              "SEMANTIC_TIMELINE_TWO_LOOP_PASS_COUNT 1")
    output = run.stdout + run.stderr
    passed = (run.returncode == 0 and output.count(marker) == 1 and
              "FATAL:" not in output)
    payload = {
        "gate": "H" if targeted else "I", "mode": mode,
        "passed": passed, "compile_rc": compiled.returncode,
        "run_rc": run.returncode, "simulation_count": 1,
        "marker": marker, "marker_count": output.count(marker),
        "vvp_sha256": sha256(image),
        "stdout_sha256": sha256(artifact / "run.stdout.log"),
        "stderr_sha256": sha256(artifact / "run.stderr.log"),
        "compile_checks": compile_checks,
    }
    (artifact / "result.json").write_text(json.dumps(payload, indent=2) + "\n")
    print(run.stdout, end="")
    if run.stderr:
        print(run.stderr, end="", file=sys.stderr)
    print(f"ZERO_ATTEMPT_GATE_{payload['gate']} {'PASS' if passed else 'FAIL'} artifact={artifact}")
    return 0 if passed else 1


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("gate", choices=(
        "static", "unit", "negative", "offline", "targeted", "two-loop"))
    parser.add_argument("--artifact-root", type=Path)
    args = parser.parse_args()
    if args.gate == "static":
        print(json.dumps(static_audit(), indent=2, sort_keys=True))
        return 0
    if args.gate == "unit":
        return unit_gate(args.artifact_root)
    if args.gate == "negative":
        return negative_gate(args.artifact_root)
    if args.gate == "offline":
        return offline_gate(args.artifact_root)
    return integrated_gate(args.gate, args.artifact_root)


if __name__ == "__main__":
    raise SystemExit(main())
