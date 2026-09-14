#!/usr/bin/env python3
"""Prove corrected converter-commit cache identity and old-key isolation."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile


CORRECT = "6aee1ee2abad8555d2a9c34b1fd7b20f3ad295d9"
MISSTAMPED = "81fa235b7f6ef180b6c6392a042502952e72252e"
CAPACITY = 8 * 1024 * 1024


def synthetic(path: Path) -> None:
    header = bytearray(124)
    header[:4] = b"PSID"
    struct.pack_into(">7HI", header, 4, 2, 0x7C, 0, 0x1000, 0x1010, 1, 1, 0)
    header[22:30] = b"C6 Tone\0"
    header[54:60] = b"Codex\0"
    header[86:91] = b"2026\0"
    struct.pack_into(">H", header, 0x76, 0x14)
    code = bytearray([0x00, 0x10, 0xA9, 0x0F, 0x8D, 0x18, 0xD4,
                      0xA9, 0x00, 0x8D, 0x00, 0xD4, 0x60])
    code.extend([0xEA] * (18 - len(code)))
    code.extend([0xEE, 0x00, 0xD4, 0x60])
    path.write_bytes(header + code)


def run(binary: Path, source: Path, cache: Path) -> Path:
    result = subprocess.run([
        str(binary), "--input", str(source), "--cache-root", str(cache),
        "--fallback-seconds", "1",
    ], text=True, capture_output=True, check=True)
    return Path(result.stdout.strip())


def canonical(provenance: dict, converter_commit: str) -> str:
    converter = provenance["converter"]
    duration = provenance["duration"]
    selection = provenance["selection"]
    return (
        "MegaVGMPlayer-SID-cache-key-v1\n"
        f"source={provenance['source']['sha256']}\n"
        f"subtune={selection['subtune']}\n"
        f"model={selection['model']}\n"
        f"timing={selection['timing']}\n"
        f"clock={selection['clock_num']}/{selection['clock_den']}\n"
        f"duration_ms={duration['milliseconds']}\n"
        f"duration_source={duration['source']}\n"
        f"db_sha={duration['database_sha256']}\n"
        f"converter={converter['version']}@{converter_commit}\n"
        f"libsidplayfp={converter['libsidplayfp_version']}@"
        f"{converter['libsidplayfp_commit']}\n"
        "packed=2.0/encoding1\n"
        f"capacity_bytes={CAPACITY}\n"
    )


parser = argparse.ArgumentParser()
parser.add_argument("--binary", type=Path, required=True)
args = parser.parse_args()

with tempfile.TemporaryDirectory(prefix="megavgm-commit-cache-") as temporary:
    root = Path(temporary)
    source = root / "tone.sid"
    synthetic(source)

    seed_cache = root / "seed"
    correct_output = run(args.binary, source, seed_cache)
    provenance = json.loads(correct_output.with_suffix(".json").read_text())
    assert provenance["converter"]["commit"] == CORRECT
    assert provenance["converter"]["capacity_bytes"] == CAPACITY
    correct_key = hashlib.sha256(canonical(provenance, CORRECT).encode()).hexdigest()
    old_key = hashlib.sha256(canonical(provenance, MISSTAMPED).encode()).hexdigest()
    assert correct_output.stem == correct_key and old_key != correct_key

    cache = root / "cache"
    cache.mkdir()
    old_payload = cache / f"{old_key}.mvgmsid"
    old_json = cache / f"{old_key}.json"
    shutil.copy2(correct_output, old_payload)
    old_provenance = json.loads(json.dumps(provenance))
    old_provenance["cache_key"] = old_key
    old_provenance["converter"]["commit"] = MISSTAMPED
    old_provenance["artifact"]["path"] = str(old_payload)
    old_json.write_text(json.dumps(old_provenance))

    generated = run(args.binary, source, cache)
    assert generated.stem == correct_key
    assert old_payload.is_file() and old_json.is_file()
    stamp = generated.stat().st_mtime_ns
    hit = run(args.binary, source, cache)
    assert hit == generated and generated.stat().st_mtime_ns == stamp

print("mis-stamped commit cache miss, corrected commit cache hit, old cache retained PASS")
