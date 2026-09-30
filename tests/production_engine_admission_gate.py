#!/usr/bin/env python3
"""Static production-engine admission gate for Quartus source authorities."""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path


REQUIRED_HARDWARE_ACCEPTANCE = {
    "pwa_cold_start",
    "same_engine_transition",
    "cross_engine_a_new_a",
    "loop_status_abi",
    "reload_reset_contract",
}
STANDARD_MACROS = {
    "MEGAVGMDRIVE_PLAYLIST_STATUS_PHASE1B",
    "MEGAVGMDRIVE_PLAYLIST_LOOP_PHASE1E",
}
STATE_NAMES = ("STATE_IDLE", "STATE_LOADING", "STATE_PLAYING",
               "STATE_ENDED", "STATE_FATAL")


def normalized(text: str) -> str:
    return " ".join(text.split())


@dataclass
class SourceGraph:
    root: Path
    configs: set[Path] = field(default_factory=set)
    sources: set[Path] = field(default_factory=set)
    macros: set[str] = field(default_factory=set)
    missing: set[str] = field(default_factory=set)

    def resolve(self, token: str, relative_to: Path) -> Path | None:
        token = token.strip().strip('"{}[]')
        candidates = (relative_to / token, self.root / token)
        for candidate in candidates:
            try:
                resolved = candidate.resolve()
            except OSError:
                continue
            if resolved.is_file():
                return resolved
        return None

    def visit_config(self, path: Path) -> None:
        path = path.resolve()
        if path in self.configs:
            return
        if not path.is_file():
            self.missing.add(str(path))
            return
        self.configs.add(path)
        text = path.read_text(errors="replace")
        self.macros.update(re.findall(
            r'VERILOG_MACRO\s+"?([A-Za-z_][A-Za-z0-9_]*)', text))

        for token in re.findall(
                r'(?<![A-Za-z0-9_])([A-Za-z0-9_./-]+\.(?:qsf|qip|tcl))',
                text):
            child = self.resolve(token, path.parent)
            if child is not None:
                self.visit_config(child)

        for token in re.findall(
                r'(?<![A-Za-z0-9_])([A-Za-z0-9_./-]+\.(?:svh|sv|v))',
                text):
            source = self.resolve(token, path.parent)
            if source is not None:
                self.sources.add(source)

    def visit_includes(self) -> None:
        pending = list(self.sources)
        while pending:
            source = pending.pop()
            text = source.read_text(errors="replace")
            for token in re.findall(r'`include\s+"([^"]+)"', text):
                include = self.resolve(token, source.parent)
                if include is not None and include not in self.sources:
                    self.sources.add(include)
                    pending.append(include)


def fail(errors: list[str], code: str, detail: str) -> None:
    errors.append(f"{code}: {detail}")


def read_required(root: Path, relative: str, graph: SourceGraph,
                  errors: list[str]) -> tuple[Path, str]:
    path = (root / relative).resolve()
    if not path.is_file():
        fail(errors, "missing-contract-file", relative)
        return path, ""
    if path not in graph.sources:
        fail(errors, "contract-file-not-in-source-graph", relative)
    return path, path.read_text(errors="replace")


def audit_engine(engine: dict, projects_root: Path) -> list[str]:
    errors: list[str] = []
    engine_id = engine.get("id", "?")
    root = (projects_root / engine["source_worktree"]).resolve()
    qpf = root / engine["qpf"]
    qsf = root / engine["qsf"]

    if engine.get("canonical_rbf") != f"MegaVGMDrive_{engine_id}.rbf":
        fail(errors, "bad-canonical-rbf-name", engine.get("canonical_rbf", ""))
    if not qpf.is_file():
        fail(errors, "missing-qpf", str(qpf))
    if not qsf.is_file():
        fail(errors, "missing-qsf", str(qsf))
        return errors

    if qpf.is_file():
        match = re.search(r'PROJECT_REVISION\s*=\s*"([^"]+)"',
                          qpf.read_text(errors="replace"))
        if not match or match.group(1) != qsf.stem:
            fail(errors, "qpf-qsf-revision-mismatch", f"{qpf} -> {qsf}")

    graph = SourceGraph(root)
    graph.visit_config(qsf)
    graph.visit_includes()
    config_text = "\n".join(p.read_text(errors="replace")
                            for p in sorted(graph.configs))

    if not re.search(r'TOP_LEVEL_ENTITY\s+sys_top\b', config_text):
        fail(errors, "not-golden-sys-top", str(qsf))

    missing_macros = set(engine.get("required_macros", [])) - graph.macros
    if missing_macros:
        fail(errors, "missing-required-macro", ",".join(sorted(missing_macros)))
    if engine.get("status_contract") == "standard_phase1b":
        missing_standard = STANDARD_MACROS - graph.macros
        if missing_standard:
            fail(errors, "missing-standard-status-macro",
                 ",".join(sorted(missing_standard)))
    elif engine.get("status_contract") != "frozen_golden_transport":
        fail(errors, "unknown-status-contract", engine.get("status_contract", ""))

    exporter_nodes = [p for p in graph.sources
                      if p.name == "megavgm_playlist_status_export.sv"]
    if not exporter_nodes:
        fail(errors, "missing-status-exporter-source", "source graph")
    elif len(exporter_nodes) != 1:
        fail(errors, "status-exporter-source-count", str(len(exporter_nodes)))

    shell_path, shell_text = read_required(
        root, engine["shell_file"], graph, errors)
    exporter_path, exporter_text = read_required(
        root, engine["exporter_file"], graph, errors)
    del shell_path, exporter_path

    if '"MegaVGMDrive;;"' not in shell_text:
        fail(errors, "missing-corename-contract", engine["shell_file"])
    for token in ("hps_io", ".status_in", ".status_set"):
        if token not in shell_text:
            fail(errors, "missing-shell-status-wiring", token)

    source_texts = [p.read_text(errors="replace") for p in graph.sources]
    instances = sum(len(re.findall(
        r'\bmegavgm_playlist_status_export\s+[A-Za-z_][A-Za-z0-9_]*\s*\(',
        text)) for text in source_texts)
    if instances != 1:
        fail(errors, "status-exporter-instance-count", str(instances))

    for state in STATE_NAMES:
        if state not in exporter_text:
            fail(errors, "missing-status-state", state)
    for state in STATE_NAMES[1:]:
        if not re.search(rf"exported_state\s*<=\s*{state}", exporter_text):
            fail(errors, "missing-status-transition", state)
    if not re.search(r"exported_session_id\s*<=\s*32'd0", exporter_text):
        fail(errors, "missing-fresh-session-zero", engine["exporter_file"])
    if not re.search(r"exported_state\s*<=\s*STATE_IDLE", exporter_text):
        fail(errors, "missing-fresh-idle", engine["exporter_file"])
    if not re.search(r"INTERFACE_MAGIC\s*=\s*8'h4d", exporter_text,
                     re.IGNORECASE):
        fail(errors, "missing-supervisor-status-magic", engine["exporter_file"])
    if not re.search(r"INTERFACE_V2_VERSION\s*=\s*4'd2", exporter_text):
        fail(errors, "missing-loop-status-version", engine["exporter_file"])
    for token in ("done_session_id == playback_session_id",
                  "error_session_id == playback_session_id",
                  "player_loop_valid", "player_loop_boundary_pulse"):
        if normalized(token) not in normalized(exporter_text):
            fail(errors, "missing-exporter-contract", token)

    ready = engine["ready"]
    ready_path, ready_text = read_required(root, ready["file"], graph, errors)
    del ready_path
    if "direct_exporter_reset" in ready:
        marker = normalized(ready["direct_exporter_reset"])
        assignments = [marker] if marker in normalized(ready_text) else []
    else:
        assignments = re.findall(
            rf'assign\s+{re.escape(ready["signal"])}\s*=\s*(.*?);',
            ready_text, re.DOTALL)
    safe_assignments = []
    for expression in assignments:
        compact = normalized(expression)
        if (all(token in compact for token in ready.get("required", [])) and
                not any(token in compact for token in ready.get("forbidden", []))):
            safe_assignments.append(compact)
    if not safe_assignments:
        fail(errors, "no-preupload-ready-expression", ready["file"])

    for evidence in engine.get("evidence", []):
        evidence_path, evidence_text = read_required(
            root, evidence["file"], graph, errors)
        del evidence_path
        compact = normalized(evidence_text)
        for token in evidence.get("contains", []):
            if normalized(token) not in compact:
                fail(errors, "missing-lifecycle-evidence",
                     f"{evidence['file']}: {token}")

    bridge = engine.get("observation_bridge")
    if bridge:
        bridge_path, bridge_text = read_required(
            root, bridge["file"], graph, errors)
        del bridge_path
        outputs = set(re.findall(
            r'\boutput\s+(?:logic|wire)(?:\s+signed)?(?:\s*\[[^]]+\])?\s+'
            r'([A-Za-z_][A-Za-z0-9_]*)', bridge_text))
        allowed = set(bridge["allowed_outputs"])
        if outputs != allowed:
            fail(errors, "status-bridge-output-surface",
                 f"actual={sorted(outputs)} expected={sorted(allowed)}")

    return errors


def audit_registry(registry_path: Path, projects_root: Path,
                   only: set[str] | None = None) -> int:
    registry = json.loads(registry_path.read_text())
    failures = 0
    hardware_items = set(registry.get("hardware_acceptance_required", []))
    if hardware_items != REQUIRED_HARDWARE_ACCEPTANCE:
        print("REGISTRY_ADMISSION_FAIL hardware-acceptance-checklist")
        failures += 1
    if set(registry.get("new_engine_required_macros", [])) != STANDARD_MACROS:
        print("REGISTRY_ADMISSION_FAIL new-engine-required-macros")
        failures += 1

    engines = registry.get("engines", [])
    ids = [engine.get("id") for engine in engines]
    if len(ids) != len(set(ids)):
        print("REGISTRY_ADMISSION_FAIL duplicate-engine-id")
        failures += 1

    selected = [engine for engine in engines
                if only is None or engine.get("id") in only]
    if only is not None and {engine.get("id") for engine in selected} != only:
        print("REGISTRY_ADMISSION_FAIL unknown-engine-selection")
        failures += 1

    for engine in selected:
        errors = audit_engine(engine, projects_root)
        if errors:
            failures += 1
            for error in errors:
                print(f"ENGINE_{engine.get('id', '?')}_ADMISSION_FAIL {error}")
        else:
            print(
                f"ENGINE_{engine['id']}_ADMISSION_PASS "
                f"rbf={engine['canonical_rbf']} "
                f"status={engine['status_contract']}"
            )

    if failures:
        print(f"PRODUCTION_ENGINE_ADMISSION_FAIL failures={failures}")
        return 1
    print("PRODUCTION_ENGINE_ADMISSION_PASS engines=" +
          ",".join(engine["id"] for engine in selected))
    return 0


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--registry", type=Path,
        default=root / "release/production_engines.json")
    parser.add_argument(
        "--projects-root", type=Path,
        default=Path("/Users/daizo/Projects"))
    parser.add_argument("--engine", action="append")
    args = parser.parse_args()
    return audit_registry(args.registry.resolve(), args.projects_root.resolve(),
                          set(args.engine) if args.engine else None)


if __name__ == "__main__":
    sys.exit(main())
