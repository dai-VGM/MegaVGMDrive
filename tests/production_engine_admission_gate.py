#!/usr/bin/env python3
"""Static production-engine admission gate for Quartus source authorities."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
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
STATUS_EXPORTER_MODULE = "megavgm_playlist_status_export"


def normalized(text: str) -> str:
    return " ".join(text.split())


def sv_without_comments(text: str) -> str:
    """Remove comments without joining tokens or treating comment text as RTL."""
    return re.sub(
        r"//[^\n]*|/\*.*?\*/",
        lambda match: "\n" * match.group(0).count("\n"),
        text,
        flags=re.DOTALL,
    )


def skip_space(text: str, offset: int) -> int:
    while offset < len(text) and text[offset].isspace():
        offset += 1
    return offset


def skip_balanced_parentheses(text: str, offset: int) -> int | None:
    if offset >= len(text) or text[offset] != "(":
        return None
    depth = 0
    in_string = False
    escaped = False
    for index in range(offset, len(text)):
        char = text[index]
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            continue
        if char == '"':
            in_string = True
        elif char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
            if depth == 0:
                return index + 1
    return None


def sv_module_instances(text: str, module_name: str) -> list[str]:
    """Find direct SV instances, including optional #(parameter overrides)."""
    text = sv_without_comments(text)
    instances: list[str] = []
    module_pattern = re.compile(rf"\b{re.escape(module_name)}\b")
    identifier_pattern = re.compile(r"[A-Za-z_][A-Za-z0-9_$]*")
    for match in module_pattern.finditer(text):
        offset = skip_space(text, match.end())
        if offset < len(text) and text[offset] == "#":
            offset = skip_space(text, offset + 1)
            offset = skip_balanced_parentheses(text, offset)
            if offset is None:
                continue
            offset = skip_space(text, offset)
        instance = identifier_pattern.match(text, offset)
        if instance is None:
            continue
        offset = skip_space(text, instance.end())
        if offset < len(text) and text[offset] == "(":
            instances.append(instance.group(0))
    return instances


def sv_module_bodies(text: str, module_name: str) -> list[str]:
    text = sv_without_comments(text)
    starts = list(re.finditer(
        rf"\bmodule\s+{re.escape(module_name)}\b", text))
    bodies = []
    for start in starts:
        end = re.search(r"\bendmodule\b", text[start.end():])
        if end is not None:
            bodies.append(text[start.end():start.end() + end.start()])
    return bodies


def validate_source_hierarchy(authority: dict, root: Path, graph: "SourceGraph",
                              errors: list[str]) -> str:
    instance_path = authority.get("instance_path", "")
    module_path = authority.get("module_path", [])
    instance_parts = instance_path.split(".")
    if (len(instance_parts) < 2 or len(module_path) != len(instance_parts) or
            module_path[-1] != STATUS_EXPORTER_MODULE):
        fail(errors, "invalid-status-source-hierarchy", instance_path)
        return ""

    module_sources: dict[str, list[tuple[Path, str]]] = {}
    for module_name in module_path[:-1]:
        definitions = []
        for source in graph.sources:
            for body in sv_module_bodies(
                    source.read_text(errors="replace"), module_name):
                definitions.append((source, body))
        module_sources[module_name] = definitions

    for index, (parent_module, child_module, instance_name) in enumerate(zip(
            module_path, module_path[1:], instance_parts[1:])):
        definitions = module_sources.get(parent_module, [])
        if len(definitions) != 1:
            fail(errors, "status-hierarchy-parent-count",
                 f"{parent_module}:{len(definitions)}")
            return ""
        source, body = definitions[0]
        instances = sv_module_instances(body, child_module)
        if instances.count(instance_name) != 1:
            fail(errors, "status-hierarchy-edge-count",
                 f"{parent_module}.{instance_name}:{instances.count(instance_name)}")
            return ""
        if index == 0 and source != (root / authority["shell_file"]).resolve():
            fail(errors, "status-hierarchy-root-not-production-shell", str(source))
            return ""
    return instance_path


def status_hierarchy_instance(engine: dict, root: Path, graph: "SourceGraph",
                              errors: list[str]) -> str | None:
    """Validate a registry-declared elaboration assertion, if available."""
    authority = engine.get("status_hierarchy")
    if authority is None:
        return None

    authority_kind = authority.get("authority")
    if authority_kind == "source_path":
        source_authority = dict(authority)
        source_authority["shell_file"] = engine["shell_file"]
        return validate_source_hierarchy(
            source_authority, root, graph, errors)
    if authority_kind != "elaboration_assertion":
        fail(errors, "unknown-status-hierarchy-authority",
             str(authority_kind))
        return ""

    module = authority.get("module")
    path = authority.get("instance_path", "")
    assertion_relative = authority.get("assertion_file", "")
    runner_relative = authority.get("runner_file", "")
    if module != STATUS_EXPORTER_MODULE or "." not in path:
        fail(errors, "invalid-status-hierarchy-authority", path)
        return ""
    parent, instance = path.rsplit(".", 1)
    assertion_path = (root / assertion_relative).resolve()
    runner_path = (root / runner_relative).resolve()
    if not assertion_path.is_file() or not runner_path.is_file():
        fail(errors, "missing-status-hierarchy-proof",
             f"{assertion_relative},{runner_relative}")
        return ""

    assertion_text = sv_without_comments(
        assertion_path.read_text(errors="replace"))
    require_cell = re.compile(
        rf"require_cell\(\s*['\"]{re.escape(parent)}['\"]\s*,\s*"
        rf"['\"]{re.escape(instance)}['\"]\s*,\s*"
        rf"['\"]{re.escape(module)}['\"]\s*\)")
    runner_text = sv_without_comments(runner_path.read_text(errors="replace"))
    runner_has_proof = (
        assertion_relative in runner_text and
        re.search(rf"--top-module\s+{re.escape(parent)}\b", runner_text) and
        "--json-only" in runner_text
    )
    if not require_cell.search(assertion_text) or not runner_has_proof:
        fail(errors, "invalid-status-hierarchy-proof", path)
        return ""

    command = authority.get("command", [])
    pass_marker = authority.get("pass_marker", "")
    if (not isinstance(command, list) or not command or
            not all(isinstance(part, str) and part for part in command) or
            not pass_marker):
        fail(errors, "invalid-status-hierarchy-command", path)
        return ""
    try:
        result = subprocess.run(
            command, cwd=root, text=True, capture_output=True,
            timeout=authority.get("timeout_seconds", 600), check=False)
    except (OSError, subprocess.TimeoutExpired) as exc:
        fail(errors, "status-hierarchy-elaboration-error", str(exc))
        return ""
    if result.returncode != 0 or pass_marker not in result.stdout:
        detail_lines = (result.stdout + result.stderr).splitlines()[-5:]
        fail(errors, "status-hierarchy-elaboration-failed",
             " | ".join(detail_lines))
        return ""
    print(f"ENGINE_{engine.get('id', '?')}_STATUS_HIERARCHY_PASS "
          f"instance={path} authority=elaboration")
    return path


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

    hierarchy_instance = status_hierarchy_instance(engine, root, graph, errors)
    shell_instances = sv_module_instances(shell_text, STATUS_EXPORTER_MODULE)
    # An executed production-hierarchy assertion is stronger than source text:
    # it rejects registered-but-uninstantiated modules and inactive branches.
    # Without one, restrict fallback matching to the production shell itself.
    if hierarchy_instance is None and len(shell_instances) != 1:
        fail(errors, "status-exporter-instance-count",
             str(len(shell_instances)))
    elif hierarchy_instance == "":
        pass

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
