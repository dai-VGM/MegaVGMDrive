#!/usr/bin/env python3
"""Stage the unpublished four-engine candidate from exact local authorities."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
PROJECTS = ROOT.parent
PUBLIC = PROJECTS / "MegaVGMPlayer_v2.2_Release/MegaVGMPlayer-v2.2"
PUBLIC_SUMS_SHA = "78a8a174890d341dab2c3d66bc1e762a131442627dfca31737ca8a2145d184e6"
RUNTIME_HEAD = "27a93571a3b4da7cfc5ab38b35085ff901998d16"
ENGINE_REGISTRY = json.loads(
    (ROOT / "release/production_engines.json").read_text())

RBF_AUTHORITIES = {
    "A": (PROJECTS / "MegaVGMPlayer_Transport13FadeOnly_A_MiSTer.rbf",
     3321456, "69efdc995e64383d5c0a7065c518aa2372e339dc54903311d1f337e4f13014d9",
     "77573e6936a10ef1ad230477dbba57914d74d41c"),
    "B": (PROJECTS / "MegaVGMPlayer_Transport13FadeOnly_B_MiSTer.rbf",
     3067640, "ae6c9f74d2d63528ef6a0cbe867099a0056e60a415c17f85870c5bc81ab4823f",
     "bd253a550ffde16857cb7d4dcd1c5cb76d21d01e"),
    "C": (Path("/Users/daizo/rbf/MegaVGMDrive_C.rbf"),
     2687708, "e7fa0a6ca192d8ecac31048ec0497fcfd7f00944dfa8c3f5cfa4a8965e06e0e1",
     "b3ebce276a32c0e09cf780f1e139a675609d1304"),
    "D": (PROJECTS / "MegaVGMDrive_D6.rbf",
     2876688, "155a87c1b3421397be62d51b1020bb96edfbad045759b8e5f7e71daa26860865",
     "5cf9faea2f2a07ead9c3e54653b27fbff8a0b654"),
}
RBF_ITEMS = [
    (engine["id"], *RBF_AUTHORITIES[engine["id"]])
    for engine in ENGINE_REGISTRY["engines"]
]

def sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

def copy_item(source: Path, destination: Path, executable: bool) -> dict:
    if not source.is_file():
        raise SystemExit(f"missing staging source: {source}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)
    destination.chmod(0o755 if executable else 0o644)
    return {"path": str(destination), "bytes": destination.stat().st_size,
            "sha256": sha(destination)}

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path)
    parser.add_argument("runtime_build", type=Path)
    parser.add_argument("remote_binary", type=Path)
    parser.add_argument("--remote-source-head", required=True)
    args = parser.parse_args()
    subprocess.run(
        [sys.executable, str(ROOT / "tests/production_engine_admission_gate.py")],
        cwd=ROOT, check=True)
    output = args.output.resolve()
    if output.exists():
        raise SystemExit(f"refusing to overwrite staging: {output}")
    if sha(PUBLIC / "SHA256SUMS") != PUBLIC_SUMS_SHA:
        raise SystemExit("public v2.2 authority changed")

    records = []
    output.mkdir(parents=True)
    for engine, source, size, expected, source_head in RBF_ITEMS:
        if source.stat().st_size != size or sha(source) != expected:
            raise SystemExit(f"Engine {engine} RBF authority mismatch: {source}")
        relative = Path("media/fat/_Custom Cores/Cores") / f"MegaVGMDrive_{engine}.rbf"
        item = copy_item(source, output / relative, False)
        item.update(kind=f"Engine {engine} hardware-PASS RBF",
                    source=str(source), source_head=source_head)
        records.append(item)

    fixed = [
        ("media/fat/MegaVGMPlayer/MiSTer.megavgm",
         PUBLIC / "media/fat/MegaVGMPlayer/MiSTer.megavgm", False,
         "public v2.2 Main; source 144ae51a2b289fc86f2e09131e3173be9f0e45e2"),
        ("media/fat/MegaVGMPlayer/megavgm_sid_prepare",
         PUBLIC / "media/fat/MegaVGMPlayer/megavgm_sid_prepare", True,
         "public v2.2 SID preparer"),
        ("media/fat/Scripts/megavgm_ctl",
         PUBLIC / "media/fat/Scripts/megavgm_ctl", True,
         "public v2.2 control helper"),
        ("media/fat/Scripts/vgm_md_import.sh",
         PUBLIC / "media/fat/Scripts/vgm_md_import.sh", True,
         "public v2.2 importer"),
        ("media/fat/MegaVGMPlayer/megavgm_supervisor",
         args.runtime_build / "megavgm_supervisor", True,
         f"four-engine runtime source {RUNTIME_HEAD}"),
        ("media/fat/MegaVGMPlayer/megavgm_playlist-phase2a",
         args.runtime_build / "megavgm_playlist", True,
         f"four-engine runtime source {RUNTIME_HEAD}"),
        ("media/fat/MegaVGMPlayer/megavgm_remote",
         args.remote_binary, True,
         f"Remote/PWA source {args.remote_source_head}"),
    ]
    for relative, source, executable, provenance in fixed:
        item = copy_item(source, output / relative, executable)
        item.update(kind=provenance, source=str(source), source_head="")
        records.append(item)

    manifest = [
        "# MegaVGMPlayer four-engine release candidate",
        "",
        "**UNPUBLISHED STAGING — hardware acceptance through the PWA is pending.**",
        "",
        "Public v2.2 was used read-only and remains immutable. Engine RBF bytes are exact",
        "hardware-PASS authorities; no RBF was rebuilt or transformed.",
        "",
        "| Payload | Bytes | SHA-256 | Provenance |",
        "|---|---:|---|---|",
    ]
    for item in records:
        rel = Path(item["path"]).relative_to(output)
        provenance = item["kind"]
        if item["source_head"]:
            provenance += f"; source `{item['source_head']}`"
        manifest.append(f"| `{rel}` | {item['bytes']} | `{item['sha256']}` | {provenance} |")
    manifest += [
        "", "## Runtime selection", "",
        "C140 command usage plus a C140 0x8D ROM block selects Engine D. C140",
        "legacy/type 0 selects System 2, type 1 selects System 21, and type 2",
        "ASIC219 is rejected. Filenames, directories, and titles are not evidence.",
        "", "The existing switch-generation, session-rebase, immutable playlist snapshot,",
        "fade, Stop, Repeat, Shuffle, Previous/Next, and reconnect contracts are retained.",
    ]
    (output / "ARTIFACT_MANIFEST.md").write_text("\n".join(manifest) + "\n")
    shutil.copy2(ROOT / "release/VNEXT_DEPLOYMENT.md", output / "DEPLOYMENT.md")
    files = sorted(p for p in output.rglob("*") if p.is_file())
    (output / "SHA256SUMS").write_text("".join(
        f"{sha(path)}  {path.relative_to(output)}\n" for path in files))
    subprocess.run(["shasum", "-a", "256", "-c", "SHA256SUMS"],
                   cwd=output, check=True)
    print(output)

if __name__ == "__main__":
    main()
