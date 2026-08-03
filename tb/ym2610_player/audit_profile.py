#!/usr/bin/env python3
"""Static/provenance audit for the independent YM2610 player profile."""

from __future__ import annotations

import hashlib
import json
import pathlib
import re
import subprocess
import sys


ROOT = pathlib.Path(__file__).resolve().parents[2]
PROFILE = ROOT / "hw/ym2610_player"
EXPECTED_BRANCH = "ym2610-vgm-player"
EXPECTED_BASE = "1049dafdd82be97be6e7de3dec9422bc86b13863"
SACRED = ROOT / "tb/tb_jt49_audio_compare.sv"
PROTECTED = [
    "ch0.dec", "ch1.dec", "ch2.dec", "ch3.dec", "ch4.dec", "ch5.dec",
    "fm0.raw", "fm1.raw", "fm2.raw", "fm4.raw", "fm5.raw", "fm6.raw",
    "tb/generate_jt10_phase4ap_variants.py",
    "tb/generate_jt10_phase4ax_variants.py",
    "tb/jt10_phase3cr_fixture.md", "tb/jt10_phase3cr_sources.f",
    "tb/jt10_phase4ap_fixture.md", "tb/jt10_phase4ap_sources.f",
    "tb/jt10_phase4ar_fixture.md", "tb/jt10_phase4ar_sources.f",
    "tb/jt10_phase4arv1_fixture.md", "tb/jt10_phase4arv1_sources.f",
    "tb/jt10_phase4ax_fixture.md", "tb/jt10_phase4ax_sources.f",
    "tb/run_jt10_phase3cr.sh", "tb/run_jt10_phase4ap.sh",
    "tb/run_jt10_phase4ar.sh", "tb/run_jt10_phase4arv1.sh",
    "tb/run_jt10_phase4ax.sh",
    "tb/tb_jt10_phase3cr_clear_boundary_audit.sv",
    "tb/tb_jt10_phase4ap_adpcmb_patch_matrix.sv",
    "tb/tb_jt10_phase4ar_adpcmb_stop_contract.sv",
    "tb/tb_jt10_phase4arv1_adpcmb_stop_contract.sv",
    "tb/tb_jt10_phase4ax_adpcmb_reset_coverage.sv",
    "tb/tb_jt49_audio_compare.sv",
]
FROZEN = [
    "rtl/emu.sv", "rtl/mister_vgm_md_top.sv", "rtl/vgm_loaded_player.sv",
    "rtl/vgm_ddram_backend.sv", "VGM_MD_MiSTer.qsf", "files.qip",
    "rtl/ym2610_hw0", "hw/ym2610_hw0",
    "rtl/genesis_audio/jt10_ym2610/adpcm",
    "tb/jt10_pinned/6d51e0b6",
]


def git(*args: str, check: bool = True) -> str:
    result = subprocess.run(["git", *args], cwd=ROOT, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if check and result.returncode:
        raise AssertionError(result.stderr or result.stdout)
    return result.stdout


def qip_paths(path: pathlib.Path) -> list[pathlib.Path]:
    found = []
    pattern = re.compile(r"\[file join \$::quartus\(qip_path\)\s+([^\s\]]+)")
    for match in pattern.finditer(path.read_text()):
        raw = match.group(1)
        assert not pathlib.PurePosixPath(raw).is_absolute(), (path, raw)
        found.append((path.parent / raw).resolve())
    return found


def main() -> int:
    assert git("branch", "--show-current").strip() == EXPECTED_BRANCH
    assert git("merge-base", "HEAD", EXPECTED_BASE).strip() == EXPECTED_BASE

    qsf = PROFILE / "MegaVGMPlayer_YM2610_MiSTer.qsf"
    qpf = PROFILE / "MegaVGMPlayer_YM2610_MiSTer.qpf"
    main_qip = PROFILE / "files_ym2610_player.qip"
    system_qip = PROFILE / "sys_ym2610_hw0.qip"
    for required in (qsf, qpf, main_qip, system_qip,
                     PROFILE / "ym2610_player.sdc"):
        assert required.is_file(), required
    qsf_text = qsf.read_text()
    assert qsf_text.count("QIP_FILE files_ym2610_player.qip") == 1
    assert not re.search(r"^\s*source\s+.*\.qip", qsf_text, re.MULTILINE)
    assert "PROJECT_REVISION = \"MegaVGMPlayer_YM2610_MiSTer\"" in qpf.read_text()

    sources = qip_paths(main_qip)
    system_sources = qip_paths(system_qip)
    assert sources and system_sources
    assert all(path.exists() for path in sources + system_sources)
    assert len(sources) == len(set(sources)), "duplicate source in player QIP"
    forbidden_names = ("ym2610_hw0_sequencer", "ym2610_hw0_video",
                       "ym2610_hw0_adpcma_rom", "ym2610_hw0_adpcmb_rom",
                       "jtoutrun", "jt51", "jt89")
    assert not any(any(name in str(path) for name in forbidden_names)
                   for path in sources)
    assert not any("tb_" in path.name for path in sources)
    assert not any(path == ROOT / "rtl/emu.sv" or
                   path == ROOT / "rtl/mister_vgm_md_top.sv" or
                   path == ROOT / "rtl/vgm_loaded_player.sv"
                   for path in sources)

    module_names: dict[str, pathlib.Path] = {}
    for source in sources:
        if source.suffix.lower() not in (".v", ".sv"):
            continue
        for name in re.findall(r"^\s*module\s+([A-Za-z_][A-Za-z0-9_$]*)",
                               source.read_text(errors="ignore"), re.MULTILINE):
            assert name not in module_names, f"duplicate module {name}"
            module_names[name] = source

    assert git("diff", "--quiet", "HEAD", "--", *FROZEN, check=False) == ""
    frozen_rc = subprocess.run(["git", "diff", "--quiet", "HEAD", "--", *FROZEN],
                               cwd=ROOT).returncode
    assert frozen_rc == 0, "frozen production/HW-0/JT10 path changed"

    stash_patch = subprocess.run(
        ["git", "stash", "show", "-p", "stash@{0}"], cwd=ROOT,
        stdout=subprocess.PIPE, check=True).stdout
    assert hashlib.sha256(stash_patch).hexdigest() == (
        "493adffd4ae4dd2083e1787466caf5b27e5c9a52c635903d704291aa672dc11f")
    assert all((ROOT / path).exists() for path in PROTECTED)
    protected_rows = []
    for name in sorted(path for path in PROTECTED if path.startswith("tb/")):
        path = ROOT / name
        stat = path.stat()
        protected_rows.append(
            f"{name}\t{hashlib.sha256(path.read_bytes()).hexdigest()}\t"
            f"{stat.st_size}\t{int(stat.st_mtime)}\t{stat.st_ino}")
    protected_digest = hashlib.sha256(
        ("\n".join(protected_rows) + "\n").encode()).hexdigest()
    assert protected_digest == (
        "42ed2aca1a859f43278641607b21e5134e0b09bc053a3f0dc22e08f9a46dbf74")
    sacred_stat = SACRED.stat()
    assert hashlib.sha256(SACRED.read_bytes()).hexdigest() == (
        "35cbd96d057e9889815229f2c0e154614eea7956ae895afdb74f6ace2b65406c")
    assert (sacred_stat.st_size, int(sacred_stat.st_mtime), sacred_stat.st_ino) == (
        4939, 1784686524, 21984214)

    pinned_root = ROOT / "tb/jt10_pinned/6d51e0b6"
    pinned_rows = (ROOT / "tb/jt10_compat/pristine_blobs.tsv").read_text().splitlines()[1:]
    assert len(pinned_rows) == 15
    for row in pinned_rows:
        relative, expected_blob, expected_sha = row.split("\t")
        path = pinned_root / relative
        assert git("hash-object", str(path.relative_to(ROOT))).strip() == expected_blob
        assert hashlib.sha256(path.read_bytes()).hexdigest() == expected_sha

    metadata = json.loads((ROOT / "tb/ym2610_player/olga_breeze_audit.json").read_text())
    assert metadata["total_writes"] == 81272
    assert metadata["b_only_writes"] == 0
    assert metadata["unknown_writes"] == 0
    assert len(metadata["descriptors"]) == 7

    generated_forbidden = (".vgm", ".wav", ".vcd", ".fst", ".rbf")
    profile_files = [path for base in (ROOT / "rtl/ym2610_player", PROFILE,
                                       ROOT / "tb/ym2610_player")
                     for path in base.rglob("*") if path.is_file()]
    assert not any(path.suffix.lower() in generated_forbidden for path in profile_files)
    assert not any(part in ("db", "incremental_db", "output_files")
                   for path in profile_files for part in path.parts)

    print(f"YM2610_PROFILE_QIP sources={len(sources)} system_sources={len(system_sources)} duplicates=0 absolute=0 forbidden=0")
    print("YM2610_PROFILE_FROZEN production=PASS hw0=PASS formal=PASS pristine_blobs=15/15")
    print("YM2610_PROFILE_PROTECTED existing=35 metadata_digest=PASS sacred=PASS stash=PASS")
    print("YM2610_PROFILE_STATIC_PASS")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as error:
        print(f"YM2610_PROFILE_STATIC_FAIL {error}", file=sys.stderr)
        raise SystemExit(1)
