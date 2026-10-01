#!/usr/bin/env python3
"""Validate an unpublished four-engine staging directory."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys

repo = Path(__file__).resolve().parents[1]
registry = json.loads((repo / "release/production_engines.json").read_text())
subprocess.run(
    [sys.executable, str(repo / "tests/production_engine_admission_gate.py")],
    cwd=repo, check=True)
root = Path(sys.argv[1]).resolve()
expected_rbfs = {
    "MegaVGMDrive_A.rbf": (3321456, "69efdc995e64383d5c0a7065c518aa2372e339dc54903311d1f337e4f13014d9"),
    "MegaVGMDrive_B.rbf": (3067640, "ae6c9f74d2d63528ef6a0cbe867099a0056e60a415c17f85870c5bc81ab4823f"),
    "MegaVGMDrive_C.rbf": (2687708, "e7fa0a6ca192d8ecac31048ec0497fcfd7f00944dfa8c3f5cfa4a8965e06e0e1"),
    "MegaVGMDrive_D.rbf": (2876688, "155a87c1b3421397be62d51b1020bb96edfbad045759b8e5f7e71daa26860865"),
}
expected_platform = {
    "media/fat/MegaVGMPlayer/megavgm_supervisor": (
        1162524,
        "7a8b48334f6bf9fa72fde4407cf88c00e1245cb8bb001bbcd56d40f67e8c2fc7",
    ),
    "media/fat/MegaVGMPlayer/megavgm_playlist-phase2a": (
        1068308,
        "29a0fc7ad60d2003757d87f14da831a24b84d517ad51dc6c1e741878092efd25",
    ),
    "media/fat/MegaVGMPlayer/megavgm_remote": (
        10121840,
        "04d5b2e6d6b135de7f919a97c39e07743a414e0cbf33a36f3c9ee54e9645a388",
    ),
}
assert set(expected_rbfs) == {
    engine["canonical_rbf"] for engine in registry["engines"]
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
for relative, (size, digest) in expected_platform.items():
    path = root / relative
    assert path.stat().st_size == size and sha(path) == digest, relative
payloads = [p for p in (root / "media/fat").rglob("*") if p.is_file()]
assert len(payloads) == 11
manifest = (root / "ARTIFACT_MANIFEST.md").read_text()
for head in (
    "77573e6936a10ef1ad230477dbba57914d74d41c",
    "bd253a550ffde16857cb7d4dcd1c5cb76d21d01e",
    "b3ebce276a32c0e09cf780f1e139a675609d1304",
    "5cf9faea2f2a07ead9c3e54653b27fbff8a0b654",
    "27a93571a3b4da7cfc5ab38b35085ff901998d16",
    "76cf4abff9eac21a7acc090514385d5c8c534b10",
    "fab3f55fa601ddd8e0931615aa3bfe91b8c6b66c",
):
    assert head in manifest
assert "megavgm-ff892105.js" in manifest
assert "0ea1ba5090707425182ea94b4b2d66c4a8df3f48616e13a0666193c327680ffd" in manifest
assert "6b2ae98d9d996339710084c34862e5c2c737a939e50c970f1ef3b0335be3f73e" not in manifest
assert "22a67d0bb1262c0a2a88cb839520664f740a9321dee60c0edc31d69cc46df2ea" not in manifest
assert "f63e358b7eb7014b891ff2bd7e4a782b26a94893" not in manifest
assert "type 2" in manifest and "Filenames" in manifest
print("four-engine staging paths/SHA/provenance gate PASS")
