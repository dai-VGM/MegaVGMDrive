#!/usr/bin/env python3
"""Build/verify the unpublished v2.2 RC from exact accepted artifacts.

No compilation, tag, publication, or MiSTer deployment is performed.
The public predecessor is read-only. Existing staging is retained as a backup.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]
PROJECTS = ROOT.parent
PUBLIC = PROJECTS / "MegaVGMPlayer_v2.2_Release/MegaVGMPlayer-v2.2"
STAGING = PROJECTS / "MegaVGMPlayer_vNext_4Engine_Staging/MegaVGMPlayer-vNext-4Engine-RC"
AUTHORITY = ROOT / "release/final_authorities.json"
PUBLIC_SUMS_SHA = "78a8a174890d341dab2c3d66bc1e762a131442627dfca31737ca8a2145d184e6"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def git(worktree, *args):
    return subprocess.check_output(["git", "-C", str(worktree), *args], text=True).strip()


def audit():
    authority = json.loads(AUTHORITY.read_text())
    runtime = PROJECTS / "MegaVGMPlayer_vNext_4Engine_Runtime"
    assert git(runtime, "rev-parse", "HEAD") == authority["runtime_head"]
    assert not git(runtime, "status", "--porcelain"), "Runtime is dirty"
    assert sha(PUBLIC / "SHA256SUMS") == PUBLIC_SUMS_SHA, "public predecessor changed"
    for line in (PUBLIC / "SHA256SUMS").read_text().splitlines():
        expected, relative = line.split("  ", 1)
        assert sha(PUBLIC / relative) == expected, f"public predecessor mismatch: {relative}"
    pwa = ROOT / authority["embedded_pwa"]["path"]
    assert sha(pwa) == authority["embedded_pwa"]["sha256"]
    records = []
    for entry in authority["payloads"]:
        entry = dict(entry)
        source = PROJECTS / entry["source"]
        assert source.is_file() and not source.is_symlink(), source
        assert source.stat().st_size == entry["bytes"], source
        assert sha(source) == entry["sha256"], source
        if "source_head" in entry:
            worktree = PROJECTS / entry["worktree"]
            entry["source_head"] = git(worktree, "rev-parse", entry["source_head"] + "^{commit}")
        records.append(entry)
    assert len(records) == len({r["destination"] for r in records}) == 12
    remote = PROJECTS / next(r["source"] for r in records if r["destination"].endswith("/megavgm_remote"))
    assert pwa.read_bytes() in remote.read_bytes(), "accepted PWA absent from Remote"
    return authority, records


def verify(package, records):
    expected = {r["destination"] for r in records}
    payload = package / "media/fat"
    actual = {str(p.relative_to(payload)) for p in payload.rglob("*") if p.is_file()}
    assert actual == expected, (actual - expected, expected - actual)
    for r in records:
        path = payload / r["destination"]
        assert not path.is_symlink()
        assert path.stat().st_size == r["bytes"] and sha(path) == r["sha256"], path
        assert path.stat().st_mode & 0o777 == int(r["mode"], 8), path
    lines = (package / "SHA256SUMS").read_text().splitlines()
    paths = set()
    for line in lines:
        digest, rel = line.split("  ", 1)
        assert rel not in paths
        paths.add(rel)
        assert sha(package / rel) == digest, rel
    files = {str(p.relative_to(package)) for p in package.rglob("*") if p.is_file() and p != package / "SHA256SUMS"}
    assert files == paths
    assert sha(PUBLIC / "SHA256SUMS") == PUBLIC_SUMS_SHA
    print("FINAL_AUTHORITY_MANIFEST_INVENTORY_PASS payloads=12 matched_importer_classifier=0755")


def build(output, authority, records):
    assert not output.exists(), f"refusing overwrite: {output}"
    output.mkdir(parents=True)
    for r in records:
        destination = output / "media/fat" / r["destination"]
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(PROJECTS / r["source"], destination)
        destination.chmod(int(r["mode"], 8))
    # Retain the accepted preparer's complete corresponding source/licenses.
    shutil.copytree(PUBLIC / "source", output / "source")
    (output / "provenance").mkdir()
    shutil.copy2(PUBLIC / "provenance/LICENSE.backend", output / "provenance/LICENSE.backend")
    for name in ("install.sh", "upgrade.sh", "rollback.sh", "common.sh", "startup.block"):
        shutil.copy2(ROOT / "release" / name, output / name)
        if name.endswith(".sh"):
            (output / name).chmod(0o755)
    shutil.copy2(AUTHORITY, output / "provenance/final_authorities.json")
    provenance = ["# MegaVGMPlayer v2.2 final RC provenance", "",
                  f"Runtime authority: `{authority['runtime_head']}`.", "",
                  "All twelve payloads are byte-preserving copies of accepted local artifacts.",
                  "Source commits and input paths are recorded below; no Quartus/RBF regeneration occurs.", ""]
    for r in records:
        provenance.append(f"- `{r['destination']}`: `{r.get('source_head', 'retained public v2.2 authority')}`; input `{PROJECTS / r['source']}`; SHA256 `{r['sha256']}`.")
    provenance += ["", "## SID corresponding source and retained helper", "",
                   "The unchanged SID preparer source authority is `247d0f198d52ca7789a845a878679c87b2f7e7dc`. Its full corresponding source, libsidplayfp 3.1.1 archive, dependency lock, observer patch, build recipes and GPL license remain under `source/megavgm_sid_prepare/`.",
                   "The unchanged control helper source authority is `9e2dd45fbd986378bbdaba326d8e722df2b89c27`.",
                   "No Commodore ROM, third-party SID tune, lab fixture or prepared test stream is installed.", ""]
    (output / "provenance/PROVENANCE.md").write_text("\n".join(provenance))
    readme = """# MegaVGMPlayer v2.2 final release candidate

Unpublished. User-confirmed hardware acceptance is recorded in the manifest.
Publication/tag requires a separate reviewed release-gate approval.

Return Player to STOCK and close Player tabs, then run `sh install.sh`.
`sh upgrade.sh` uses the same journaled installation. Retain the printed backup
path. `sh rollback.sh` restores the predecessor; introduced files are retained
under the checkpoint's `retired/` directory. Later edits cause safe refusal.
The installer validates all hashes, backs up all targets, stages on the FAT
filesystem, and renames individual files. An interruption is recoverable through
the PREPARED checkpoint; multi-file installation is not a single atomic rename.

Paths remain /media/fat/_Custom Cores/Cores/MegaVGMDrive_A/B/C/D.rbf,
/media/fat/MegaVGMPlayer/{MiSTer.megavgm,megavgm_supervisor,
megavgm_playlist-phase2a,megavgm_remote,megavgm_sid_prepare}, and
/media/fat/Scripts/{megavgm_ctl,vgm_md_import.sh,megavgm_classify}.
Importer/classifier are a matched set with mode 0755. Re-import malformed Mega
Drive tracks from originals with `vgm_md_import.sh`; normalization changes only
the unpublished prepared body. Originals are preserved.

Music, playlists/Favorites, legacy rescue RBFs, and Scripts/remote.sh are user
data and are preserved. No diagnostic VGM/SID fixtures are installed.
The existing startup block/service semantics and package layout are unchanged.
"""
    (output / "README.md").write_text(readme)
    (output / "README.ja.md").write_text("# MegaVGMPlayer v2.2 最終RC\n\n未公開。STOCKへ戻して `sh install.sh`、更新は `sh upgrade.sh`、復旧は `sh rollback.sh`。\nbackup pathを保存してください。Importerとclassifierは0755のmatched setです。\n詳細と配置はREADME.md、全artifactの実測hashはARTIFACT_MANIFEST.mdを参照してください。\n")
    (output / "RELEASE_NOTES.md").write_text("# v2.2 final RC\n\nFour-engine accepted authorities; transparent INFO/loading, Engine B Stage 6 bank fix, same-track restart, and preparation-only missing SN76489 clock normalization. No version bump/tag/publication performed.\n")
    manifest = ["# MegaVGMPlayer v2.2 final artifact manifest", "", "Unpublished final RC; exact user-accepted hardware artifacts.", "", f"Runtime authority: `{authority['runtime_head']}`.", "", authority["hardware_acceptance"], "", f"Embedded PWA: `{Path(authority['embedded_pwa']['path']).name}` SHA256 `{authority['embedded_pwa']['sha256']}`.", "", "| Installed path relative to /media/fat | Bytes | SHA256 | Mode | Source HEAD |", "|---|---:|---|---|---|"]
    for r in records:
        p = output / "media/fat" / r["destination"]
        manifest.append(f"| `{r['destination']}` | {p.stat().st_size} | `{sha(p)}` | {r['mode']} | `{r.get('source_head', 'retained public v2.2 authority')}` |")
    manifest += ["", "## Exact local inputs", ""] + [f"- `{PROJECTS / r['source']}`" for r in records]
    manifest += ["", "Hashes/sizes above were calculated from the final payload. Engine C is OSD_Visual. RBFs were copied byte-for-byte without regeneration.", ""]
    (output / "ARTIFACT_MANIFEST.md").write_text("\n".join(manifest))
    files = sorted(p for p in output.rglob("*") if p.is_file())
    (output / "SHA256SUMS").write_text("".join(f"{sha(p)}  {p.relative_to(output)}\n" for p in files))
    verify(output, records)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--audit", action="store_true")
    parser.add_argument("--record-preflight", type=Path)
    parser.add_argument("--build", type=Path)
    parser.add_argument("--verify", type=Path)
    parser.add_argument("--promote-staging", type=Path, help="verified new package to promote")
    parser.add_argument("--archive", type=Path, help="verified package; create unpublished ZIP")
    args = parser.parse_args()
    authority, records = audit()
    if args.record_preflight:
        report = {"runtime_head": authority["runtime_head"], "worktrees": {}, "inventories": {}}
        for name in ("MegaVGMPlayer_vNext_4Engine_Runtime", "MegaVGMPlayer_vNext_4Engine_RC", "mister-vgm-fade-only-a", "MegaVGMPlayer_EngineB_FM6_Activity", "MegaVGMPlayer_EngineC_TransparentInfo", "MegaVGMPlayer_EngineD_TransparentInfo", "Main_MiSTer-megavgm-bottom-loading"):
            tree = PROJECTS / name
            report["worktrees"][name] = {"head": git(tree, "rev-parse", "HEAD"), "branch": git(tree, "branch", "--show-current"), "status": git(tree, "status", "--porcelain")}
        for label, tree in (("predecessor_public", PUBLIC), ("predecessor_staging", STAGING)):
            report["inventories"][label] = [{"path": str(p.relative_to(tree)), "bytes": p.stat().st_size, "sha256": sha(p), "mode": oct(p.stat().st_mode & 0o777)} for p in sorted(tree.rglob("*")) if p.is_file()]
        report["platform_contract_sha256"] = sha(PROJECTS / "MegaVGMPlayer_Platform_Contract.md")
        report["authority"] = records
        with args.record_preflight.open("x") as handle:
            json.dump(report, handle, indent=2)
            handle.write("\n")
    if args.audit:
        print(json.dumps({"authority": authority, "resolved_payloads": records}, indent=2))
    if args.build:
        build(args.build.resolve(), authority, records)
    if args.verify:
        verify(args.verify.resolve(), records)
    if args.promote_staging:
        package = args.promote_staging.resolve()
        verify(package, records)
        backup = STAGING.with_name(STAGING.name + ".pre-final-f381918")
        new = STAGING.with_name(STAGING.name + ".new-f381918")
        assert not backup.exists() and not new.exists()
        shutil.copytree(package, new)
        verify(new, records)
        STAGING.rename(backup)
        try:
            new.rename(STAGING)
        except BaseException:
            backup.rename(STAGING)
            raise
        print(f"STAGING_PROMOTION_PASS previous retained at {backup}")
    if args.archive:
        package = args.archive.resolve()
        verify(package, records)
        archive = package.with_suffix(".zip")
        with zipfile.ZipFile(archive, "x", zipfile.ZIP_DEFLATED) as handle:
            for path in sorted(package.rglob("*")):
                if path.is_file():
                    handle.write(path, str(path.relative_to(package.parent)))
        archive.with_suffix(".zip.sha256").write_text(f"{sha(archive)}  {archive.name}\n")
        print(f"UNPUBLISHED_ARCHIVE {archive} bytes={archive.stat().st_size} sha256={sha(archive)}")


if __name__ == "__main__":
    main()
