#!/usr/bin/env python3
"""Extract exact canonical Gate E P/R modules into a compile-only source."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "tb/jt10_gatee_monitor_fix/gatee_monitor_contracts.sv"
SOURCE_SHA256 = "babd3fe3b98d0a9fc7ef555a858980039265db994bdc2355caeb338a4259317b"
SLICE_SHA256 = "84255d408ae6905fe950c80bce29cbb43956ad95d3d79056989a4e21be890ba8"
EXPECTED_MODULES = (
    "gatee_phase_token_monitor",
    "gatee_restart_ownership_monitor",
    "gatee_bounded_event_monitor",
)
EXTRACTED_MODULES = EXPECTED_MODULES[:2]
FORBIDDEN_MODULE = EXPECTED_MODULES[2]


@dataclass(frozen=True)
class Token:
    value: str
    start: int
    end: int


@dataclass(frozen=True)
class Module:
    name: str
    start: int
    end: int


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def lexical_tokens(text: str) -> list[Token]:
    """Tokenize identifiers outside comments, strings, and escaped IDs."""
    tokens: list[Token] = []
    index = 0
    length = len(text)
    while index < length:
        if text.startswith("//", index):
            newline = text.find("\n", index + 2)
            index = length if newline < 0 else newline + 1
            continue
        if text.startswith("/*", index):
            close = text.find("*/", index + 2)
            if close < 0:
                raise ValueError("unterminated block comment")
            index = close + 2
            continue
        if text[index] == '"':
            index += 1
            while index < length:
                if text[index] == "\\":
                    index += 2
                elif text[index] == '"':
                    index += 1
                    break
                else:
                    index += 1
            else:
                raise ValueError("unterminated string literal")
            continue
        if text[index] == "\\":
            # A Verilog escaped identifier ends at whitespace.
            index += 1
            while index < length and not text[index].isspace():
                index += 1
            continue
        match = re.match(r"[A-Za-z_$][A-Za-z0-9_$]*", text[index:])
        if match:
            end = index + len(match.group(0))
            tokens.append(Token(match.group(0), index, end))
            index = end
        else:
            index += 1
    return tokens


def module_inventory(text: str) -> list[Module]:
    """Recognize every lexical module boundary and reject malformed nesting."""
    tokens = lexical_tokens(text)
    modules: list[Module] = []
    active_name: str | None = None
    active_start = -1
    index = 0
    while index < len(tokens):
        token = tokens[index]
        if token.value == "module":
            if active_name is not None:
                raise ValueError(f"nested module before endmodule: {active_name}")
            if index + 1 >= len(tokens):
                raise ValueError("module keyword without name")
            name = tokens[index + 1]
            if name.value in ("module", "endmodule"):
                raise ValueError("invalid module name token")
            active_name = name.value
            active_start = token.start
            index += 2
            continue
        if token.value == "endmodule":
            if active_name is None:
                raise ValueError("endmodule without module")
            end = token.end
            if end < len(text) and text[end] == "\r":
                end += 1
            if end < len(text) and text[end] == "\n":
                end += 1
            modules.append(Module(active_name, active_start, end))
            active_name = None
            active_start = -1
        index += 1
    if active_name is not None:
        raise ValueError(f"truncated module: {active_name}")
    return modules


def build_extraction(source: bytes) -> tuple[bytes, dict[str, object]]:
    if sha256(source) != SOURCE_SHA256:
        raise ValueError("canonical contracts source SHA-256 mismatch")
    text = source.decode("utf-8")
    modules = module_inventory(text)
    names = [module.name for module in modules]
    if tuple(names) != EXPECTED_MODULES:
        raise ValueError(f"unexpected canonical module inventory: {names}")
    if len(names) != len(set(names)):
        raise ValueError("duplicate canonical module name")
    p_modules = [module for module in modules if module.name == EXTRACTED_MODULES[0]]
    r_modules = [module for module in modules if module.name == EXTRACTED_MODULES[1]]
    if len(p_modules) != 1 or len(r_modules) != 1:
        raise ValueError("expected exactly one P module and one R module")
    p_module, r_module = p_modules[0], r_modules[0]
    if p_module.start >= r_module.start or p_module.end > r_module.start:
        raise ValueError("P/R canonical module ordering or boundary overlap")

    # The exact canonical prefix includes only source comments/timescale plus
    # P and R.  No module body is regenerated or normalized.
    slice_end = r_module.end
    extracted = source[:slice_end]
    if sha256(extracted) != SLICE_SHA256:
        raise ValueError("canonical P/R source slice SHA-256 mismatch")
    extracted_inventory = module_inventory(extracted.decode("utf-8"))
    extracted_names = [module.name for module in extracted_inventory]
    if tuple(extracted_names) != EXTRACTED_MODULES:
        raise ValueError(f"unexpected extracted module inventory: {extracted_names}")
    if FORBIDDEN_MODULE in extracted_names:
        raise ValueError("existing H leaked into extracted source")
    if len(extracted_names) != len(set(extracted_names)):
        raise ValueError("duplicate extracted module")
    # A second in-memory construction proves deterministic reproduction before
    # any output file is written.
    reproduced = source[:slice_end]
    if extracted != reproduced or sha256(reproduced) != SLICE_SHA256:
        raise ValueError("nondeterministic extraction")

    manifest = {
        "input": {
            "path": str(SOURCE.relative_to(ROOT)),
            "sha256": SOURCE_SHA256,
            "size": len(source),
        },
        "canonical_modules": [module.__dict__ for module in modules],
        "extraction": {
            "start": 0,
            "end": slice_end,
            "size": len(extracted),
            "sha256": sha256(extracted),
            "modules": [module.__dict__ for module in extracted_inventory],
        },
        "checks": {
            "expected_p_module_count": extracted_names.count(EXTRACTED_MODULES[0]) == 1,
            "expected_r_module_count": extracted_names.count(EXTRACTED_MODULES[1]) == 1,
            "unexpected_module_count_zero": set(extracted_names) == set(EXTRACTED_MODULES),
            "h_module_count_zero": extracted_names.count(FORBIDDEN_MODULE) == 0,
            "duplicate_module_zero": len(extracted_names) == len(set(extracted_names)),
            "truncated_module_zero": True,
            "source_slice_sha_match": sha256(extracted) == SLICE_SHA256,
            "deterministic_reproduction": extracted == reproduced,
            "logic_added_or_modified": False,
        },
    }
    return extracted, manifest


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    manifest_path = args.manifest.resolve()
    if output.exists() or manifest_path.exists():
        raise SystemExit("refusing to overwrite extraction output or manifest")
    extracted, manifest = build_extraction(SOURCE.read_bytes())
    output.parent.mkdir(parents=True, exist_ok=True)
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(extracted)
    manifest["output"] = {
        "runtime_path": str(output),
        "sha256": sha256(output.read_bytes()),
        "size": output.stat().st_size,
    }
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    print("PR_EXTRACTION_PASS modules=2 P=1 R=1 H=0 unexpected=0 duplicate=0 truncated=0 "
          f"slice_sha256={SLICE_SHA256}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
