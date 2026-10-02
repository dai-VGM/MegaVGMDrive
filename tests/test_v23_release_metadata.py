#!/usr/bin/env python3
"""Lightweight version/inventory/hash/mode negative gates; no compilation."""
import json
from pathlib import Path
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "release"))
import promote_v23 as promotion


def rejected(action):
    try:
        action()
    except AssertionError:
        return
    raise AssertionError("negative fixture was admitted")


authority, records = promotion.audit()
with tempfile.TemporaryDirectory(prefix="megavgm-v23-metadata-") as directory:
    package = Path(directory) / "MegaVGMPlayer-v2.3"
    rejected(lambda: promotion.build(Path(directory) / "MegaVGMPlayer-v2.2", authority, records))
    promotion.build(package, authority, records)
    manifest = package / "provenance/final_authorities.json"
    original = manifest.read_bytes()
    wrong = json.loads(original)
    wrong["package_version"] = "2.2"
    manifest.write_text(json.dumps(wrong))
    rejected(lambda: promotion.verify(package, records))
    manifest.write_bytes(original)
    notes = package / "RELEASE_NOTES.md"
    original = notes.read_bytes()
    notes.write_bytes(original.replace(b"# MegaVGMPlayer v2.3", b"# MegaVGMPlayer v2.2"))
    rejected(lambda: promotion.verify(package, records))
    notes.write_bytes(original)
    payload = package / "media/fat/Scripts/megavgm_classify"
    payload.chmod(0o644)
    rejected(lambda: promotion.verify(package, records))
    payload.chmod(0o755)
    original = payload.read_bytes()
    payload.write_bytes(b"!" + original[1:])
    rejected(lambda: promotion.verify(package, records))
    payload.write_bytes(original)
    extra = package / "media/fat/Scripts/unaccepted"
    extra.write_text("not accepted")
    rejected(lambda: promotion.verify(package, records))
    extra.unlink()
    promotion.verify(package, records)
print("V23_RELEASE_METADATA_VERSION_INVENTORY_HASH_MODE_NEGATIVE_GATES_PASS")
