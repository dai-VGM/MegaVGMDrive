#!/usr/bin/env python3
"""Generate the Z0--Z3 semantic ZERO-attempt adapter candidates."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "tb/jt10_semantic_timeline_adapter_knownfix/candidates/a1_named_wire.sv"
SOURCE_SHA256 = "8e410f0fcf989049d3b39e7c4cc91b011f4a2cf67c2c92adec1a752bc1186ff6"

FUNCTION_ANCHOR = """    endfunction

    task automatic adapter_failure(input logic [7:0] code);
"""

MATCH_ANCHOR = """                                raw_attempt == expected_raw_attempt(
                                    family_i[3:0], attempt_i[2:0], K_ZERO)) begin
"""


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def helper(predicate: str) -> str:
    return f"""    endfunction

    // Z-series seam: only the selected single-attempt family uses the same
    // semantic normalization already used by START/STOP.  Expanded families
    // retain the frozen expected_raw_attempt comparison byte-for-byte.
    function automatic logic zero_attempt_matches(
        input logic [3:0] family,
        input logic [2:0] semantic_attempt,
        input logic [2:0] raw
    );
        begin
            if ({predicate})
                zero_attempt_matches =
                    normalize_attempt(family, raw) == semantic_attempt;
            else
                zero_attempt_matches = raw == expected_raw_attempt(
                    family, semantic_attempt, K_ZERO);
        end
    endfunction

    task automatic adapter_failure(input logic [7:0] code);
"""


def make_candidate(source: str, predicate: str | None) -> str:
    if predicate is None:
        return source
    if source.count(FUNCTION_ANCHOR) != 1:
        raise SystemExit("normalize helper insertion anchor count is not one")
    if source.count(MATCH_ANCHOR) != 1:
        raise SystemExit("ZERO comparison replacement anchor count is not one")
    result = source.replace(FUNCTION_ANCHOR, helper(predicate), 1)
    result = result.replace(
        MATCH_ANCHOR,
        """                                zero_attempt_matches(
                                    family_i[3:0], attempt_i[2:0],
                                    raw_attempt)) begin
""",
        1,
    )
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--manifest", type=Path)
    args = parser.parse_args()

    source_bytes = SOURCE.read_bytes()
    if sha256_bytes(source_bytes) != SOURCE_SHA256:
        raise SystemExit("frozen A1 source identity mismatch")
    source = source_bytes.decode()
    output = (args.output_dir or
              ROOT / "tb/jt10_semantic_zero_attempt_normalize/candidates")
    output.mkdir(parents=True, exist_ok=True)

    specifications = {
        "z0_frozen.sv": None,
        "z1_fm_zero.sv": "family == F_FM",
        "z2_ssg_zero.sv": "family == F_SSG",
        "z3_fm_ssg_zero.sv": "family_attempt_count(family) == 1",
    }
    identities: dict[str, str] = {}
    for name, predicate in specifications.items():
        data = make_candidate(source, predicate).encode()
        (output / name).write_bytes(data)
        identities[name] = sha256_bytes(data)

    manifest = {
        "source": str(SOURCE.relative_to(ROOT)),
        "source_sha256": SOURCE_SHA256,
        "candidates": identities,
        "meaning": {
            "z0_frozen.sv": "frozen A1 exact",
            "z1_fm_zero.sv": "FM ZERO semantic attempt normalization only",
            "z2_ssg_zero.sv": "SSG ZERO semantic attempt normalization only",
            "z3_fm_ssg_zero.sv": "all existing single-attempt families; currently FM and SSG",
        },
    }
    manifest_path = args.manifest or output.parent / "GENERATOR_MANIFEST.json"
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
