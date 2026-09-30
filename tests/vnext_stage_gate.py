#!/usr/bin/env python3
"""Validate an unpublished four-engine staging directory."""
import hashlib
from pathlib import Path
import sys

root = Path(sys.argv[1]).resolve()
expected_rbfs = {
    "MegaVGMDrive_A.rbf": (3321456, "69efdc995e64383d5c0a7065c518aa2372e339dc54903311d1f337e4f13014d9"),
    "MegaVGMDrive_B.rbf": (3067640, "ae6c9f74d2d63528ef6a0cbe867099a0056e60a415c17f85870c5bc81ab4823f"),
    "MegaVGMDrive_C.rbf": (2687708, "e7fa0a6ca192d8ecac31048ec0497fcfd7f00944dfa8c3f5cfa4a8965e06e0e1"),
    "MegaVGMDrive_D.rbf": (2811416, "274283072f3263070e5c747f7e67408f70ca765a0506a0c1839b8bf13c319267"),
}
def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

listed = {}
for line in (root / "SHA256SUMS").read_text().splitlines():
    digest, relative = line.split("  ", 1)
    path = root / relative
    assert path.is_file() and sha(path) == digest, relative
    listed[relative] = digest
actual = {str(p.relative_to(root)) for p in root.rglob("*")
          if p.is_file() and p.name != "SHA256SUMS"}
assert set(listed) == actual
rbf_dir = root / "media/fat/_Custom Cores/Cores"
assert {p.name for p in rbf_dir.glob("*.rbf")} == set(expected_rbfs)
for name, (size, digest) in expected_rbfs.items():
    path = rbf_dir / name
    assert path.stat().st_size == size and sha(path) == digest, name
payloads = [p for p in (root / "media/fat").rglob("*") if p.is_file()]
assert len(payloads) == 11
manifest = (root / "ARTIFACT_MANIFEST.md").read_text()
for head in (
    "77573e6936a10ef1ad230477dbba57914d74d41c",
    "bd253a550ffde16857cb7d4dcd1c5cb76d21d01e",
    "b3ebce276a32c0e09cf780f1e139a675609d1304",
    "e55158db936cfd80ea04988110eb69f900ea0c61",
):
    assert head in manifest
assert "type 2" in manifest and "Filenames" in manifest
print("four-engine staging paths/SHA/provenance gate PASS")
