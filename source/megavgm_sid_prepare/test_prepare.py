#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/engine_c_packed_v2"))
import packed  # noqa: E402


def synthetic(path: Path, flags: int = 0x14, second_sid: int = 0) -> None:
    header = bytearray(124)
    header[:4] = b"PSID"
    # PSID v3 is the first revision in which the second-SID address byte is
    # defined.  Keep the ordinary fixture v2, but use v3 when exercising the
    # strict single-SID rejection gate.
    version = 3 if second_sid else 2
    struct.pack_into(">7HI", header, 4, version, 0x7C, 0, 0x1000, 0x1010, 1, 1, 0)
    header[22:30] = b"C6 Tone\0"
    header[54:60] = b"Codex\0"
    header[86:91] = b"2026\0"
    struct.pack_into(">H", header, 0x76, flags)
    header[0x7A] = second_sid
    # Init writes volume/frequency. Play performs one same-value-preserving
    # C64 bus write per call; no copyrighted tune data is included.
    code = bytearray([0x00, 0x10, 0xA9, 0x0F, 0x8D, 0x18, 0xD4,
                      0xA9, 0x00, 0x8D, 0x00, 0xD4, 0x60])
    code.extend([0xEA] * (18 - len(code)))
    code.extend([0xEE, 0x00, 0xD4, 0x60])
    path.write_bytes(header + code)


def run(binary: Path, *args: str, ok: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run([str(binary), *args], text=True, capture_output=True)
    if ok and result.returncode:
        raise AssertionError(result.stderr)
    if not ok and result.returncode == 0:
        raise AssertionError("expected failure")
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", type=Path, required=True)
    parser.add_argument("--test-binary", type=Path)
    parser.add_argument("--capacity-test-binary", type=Path)
    parser.add_argument("--commando", type=Path)
    parser.add_argument("--c1-reference", type=Path)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="megavgm-c6-test-") as temporary:
        root = Path(temporary)
        source = root / "tone.sid"
        synthetic(source)
        cache = root / "cache"
        first = run(args.binary, "--input", str(source), "--cache-root", str(cache),
                    "--fallback-seconds", "1")
        output = Path(first.stdout.strip())
        raw = output.read_bytes()
        trace = packed.decode(raw)
        assert trace.metadata.sid_model == 1 and trace.metadata.timing_standard == 1
        assert trace.metadata.flags == 4 and trace.metadata.stream_cycles == 985248
        assert trace.metadata.source_sha256 == hashlib.sha256(source.read_bytes()).digest()
        assert trace.writes and output.stat().st_size < 8 * 1024 * 1024
        provenance = json.loads(output.with_suffix(".json").read_text())
        assert provenance["capture"]["write_count"] == len(trace.writes)
        assert provenance["duration"]["capture_limit"] is True
        assert provenance["converter"]["capacity_bytes"] == 8 * 1024 * 1024

        # A strict SHA/subtune-bound JSON sidecar creates one canonical
        # intro+loop traversal. Human milliseconds snap to the nearest WRITE
        # boundary (ties earlier); the packed EOF becomes the resolved end.
        loop_source = root / "loop-tone.sid"
        shutil.copy2(source, loop_source)
        source_sha = hashlib.sha256(loop_source.read_bytes()).hexdigest()
        loop_sidecar = Path(str(loop_source) + ".loop.json")
        loop_sidecar.write_text(json.dumps({
            "schema": "MegaVGMPlayer-SID-loop-v1",
            "source_sha256": source_sha,
            "subtune": 1,
            "loop_start_ms": 100,
            "loop_end_ms": 800,
        }, separators=(",", ":")))
        loop_cache = root / "loop-cache"
        loop_result = run(args.binary, "--input", str(loop_source),
                          "--cache-root", str(loop_cache),
                          "--fallback-seconds", "1")
        loop_output = Path(loop_result.stdout.strip())
        loop_trace = packed.decode(loop_output.read_bytes())
        lm = loop_trace.metadata
        requested_start = (100 * 985_248 + 500) // 1000
        requested_end = (800 * 985_248 + 500) // 1000
        end_candidates = [trace.metadata.stream_cycles] + [
            cycle for cycle, _, _ in trace.writes if cycle > 0
        ]
        expected_end = min(end_candidates,
                           key=lambda value: (abs(value - requested_end), value))
        start_candidates = [0] + [
            cycle for cycle, _, _ in trace.writes if cycle < expected_end
        ]
        expected_start = min(start_candidates,
                             key=lambda value: (abs(value - requested_start), value))
        assert lm.flags & packed.v1.LOOP_VALID
        assert not lm.flags & (packed.v1.DURATION_KNOWN |
                               packed.v1.END_IS_CAPTURE_LIMIT)
        assert lm.loop_start_cycle == expected_start
        assert lm.loop_end_cycle == lm.stream_cycles == expected_end
        assert all(cycle < expected_end for cycle, _, _ in loop_trace.writes)
        expected_index = next((i for i, write in enumerate(loop_trace.writes)
                               if write[0] >= expected_start),
                              len(loop_trace.writes))
        assert lm.loop_write_index == expected_index
        loop_provenance = json.loads(loop_output.with_suffix(".json").read_text())
        assert loop_provenance["loop"] == {
            "loop_source": "manual_sidecar",
            "sidecar_sha256": hashlib.sha256(loop_sidecar.read_bytes()).hexdigest(),
            "requested_loop_start_ms": 100,
            "requested_loop_end_ms": 800,
            "resolved_loop_start_cycle": expected_start,
            "resolved_loop_end_cycle": expected_end,
            "loop_write_index": expected_index,
            "loop_valid": True,
        }
        assert loop_provenance["capture"]["loop_valid"] is True
        loop_stamp = loop_output.stat().st_mtime_ns
        loop_again = run(args.binary, "--input", str(loop_source),
                         "--cache-root", str(loop_cache),
                         "--fallback-seconds", "1")
        assert loop_again.stdout == loop_result.stdout
        assert loop_output.stat().st_mtime_ns == loop_stamp

        # Sidecar content is explicit cache identity even when its resolved
        # boundary happens to be unchanged.
        loop_sidecar.write_text(loop_sidecar.read_text() + "\n")
        changed_loop = run(args.binary, "--input", str(loop_source),
                           "--cache-root", str(loop_cache),
                           "--fallback-seconds", "1")
        assert changed_loop.stdout != loop_result.stdout

        def rejected_loop_sidecar(document: object, needle: str) -> None:
            loop_sidecar.write_text(document if isinstance(document, str)
                                    else json.dumps(document))
            rejected = run(args.binary, "--input", str(loop_source),
                           "--output", str(root / "rejected-loop.mvgmsid"),
                           "--fallback-seconds", "1", ok=False)
            assert needle in rejected.stderr, rejected.stderr

        base_loop = {
            "schema": "MegaVGMPlayer-SID-loop-v1",
            "source_sha256": source_sha,
            "subtune": 1,
            "loop_start_ms": 100,
            "loop_end_ms": 800,
        }
        rejected_loop_sidecar({**base_loop, "source_sha256": "0" * 64}, "source SHA")
        rejected_loop_sidecar({**base_loop, "subtune": 2}, "subtune")
        rejected_loop_sidecar("{not-json", "JSON")
        rejected_loop_sidecar({**base_loop, "loop_start_ms": 800}, "start must precede")
        rejected_loop_sidecar({**base_loop, "loop_end_ms": 1001}, "capture horizon")
        loop_sidecar.unlink()

        # Capacity is explicit cache identity rather than relying only on a
        # different converter commit after a policy change.
        converter = provenance["converter"]
        duration = provenance["duration"]
        selection = provenance["selection"]
        canonical = (
            "MegaVGMPlayer-SID-cache-key-v1\n"
            f"source={provenance['source']['sha256']}\nsubtune={selection['subtune']}\n"
            f"model={selection['model']}\ntiming={selection['timing']}\n"
            f"clock={selection['clock_num']}/{selection['clock_den']}\n"
            f"duration_ms={duration['milliseconds']}\nduration_source={duration['source']}\n"
            f"db_sha={duration['database_sha256']}\n"
            f"converter={converter['version']}@{converter['commit']}\n"
            f"libsidplayfp={converter['libsidplayfp_version']}@{converter['libsidplayfp_commit']}\n"
            "packed=2.0/encoding1\ncapacity_bytes=8388608\n"
        )
        new_key = hashlib.sha256(canonical.encode()).hexdigest()
        old_key = hashlib.sha256(canonical.replace("capacity_bytes=8388608\n", "").encode()).hexdigest()
        assert provenance["cache_key"] == new_key == output.stem
        assert old_key != new_key

        old_cache = root / "old-capacity-cache"
        old_cache.mkdir()
        shutil.copy2(output, old_cache / f"{old_key}.mvgmsid")
        old_provenance = dict(provenance)
        old_provenance["cache_key"] = old_key
        old_provenance["converter"] = dict(converter)
        old_provenance["converter"]["capacity_bytes"] = 4 * 1024 * 1024
        (old_cache / f"{old_key}.json").write_text(json.dumps(old_provenance))
        replaced = run(args.binary, "--input", str(source), "--cache-root",
                       str(old_cache), "--fallback-seconds", "1")
        assert Path(replaced.stdout.strip()).stem == new_key
        assert (old_cache / f"{old_key}.mvgmsid").is_file()

        # Songlength lookup is content-MD5 plus selected subtune, never basename.
        database = root / "Songlengths.md5"
        database.write_text("[Database]\n" +
                            provenance["duration"]["tune_md5_new"] + "=0:02.000\n")
        database_output = root / "database.mvgmsid"
        run(args.binary, "--input", str(source), "--output", str(database_output),
            "--songlength-db", str(database))
        direct_provenance = json.loads(Path(str(database_output) + ".json").read_text())
        assert direct_provenance["artifact"]["path"] == str(database_output)
        assert direct_provenance["artifact"]["sha256"] == hashlib.sha256(database_output.read_bytes()).hexdigest()
        database_trace = packed.decode(database_output.read_bytes())
        assert database_trace.metadata.flags == 1
        assert database_trace.metadata.stream_cycles == 2 * 985_248
        miss_database = root / "Songlengths-miss.md5"
        miss_database.write_text("[Database]\n" + "0" * 32 + "=0:09.000\n")
        miss_output = root / "database-miss.mvgmsid"
        run(args.binary, "--input", str(source), "--output", str(miss_output),
            "--songlength-db", str(miss_database), "--fallback-seconds", "1")
        assert packed.decode(miss_output.read_bytes()).metadata.flags == 4

        stamp = output.stat().st_mtime_ns
        second = run(args.binary, "--input", str(source), "--cache-root", str(cache),
                     "--fallback-seconds", "1")
        assert second.stdout == first.stdout and output.stat().st_mtime_ns == stamp

        # Corruption is never reused; regeneration restores canonical bytes.
        output.write_bytes(raw[:140])
        run(args.binary, "--input", str(source), "--cache-root", str(cache),
            "--fallback-seconds", "1")
        assert packed.decode(output.read_bytes()) == trace

        # A changed source cannot collide with the original cache identity.
        changed = root / "changed.sid"
        changed.write_bytes(source.read_bytes() + b"\0")
        changed_result = run(args.binary, "--input", str(changed), "--cache-root",
                             str(cache), "--fallback-seconds", "1")
        assert changed_result.stdout != first.stdout

        # Strict malformed, multi-SID, unknown model/timing and subtune gates.
        malformed = root / "malformed.sid"
        malformed.write_bytes(b"not a SID")
        run(args.binary, "--input", str(malformed), "--output", str(root / "bad.mvgmsid"), ok=False)
        multi = root / "multi.sid"
        synthetic(multi, second_sid=0x42)
        run(args.binary, "--input", str(multi), "--output", str(root / "multi.mvgmsid"), ok=False)
        unknown = root / "unknown.sid"
        synthetic(unknown, flags=0)
        unresolved = run(args.binary, "--input", str(unknown), "--output",
                         str(root / "unknown.mvgmsid"), ok=False)
        assert "unknown/any" in unresolved.stderr
        run(args.binary, "--input", str(source), "--subtune", "2", "--output",
            str(root / "subtune.mvgmsid"), ok=False)

        # Exact source-SHA/subtune sidecar resolves unknown fields and trusted duration.
        sidecar = unknown.with_name(unknown.name + ".megavgm")
        sidecar.write_text("MEGAVGMSID_OVERRIDE_V1\n" +
                           f"source_sha256={hashlib.sha256(unknown.read_bytes()).hexdigest()}\n" +
                           "subtune=1\nmodel=8580\ntiming=ntsc\nduration_ms=1250\n")
        trusted = root / "trusted.mvgmsid"
        run(args.binary, "--input", str(unknown), "--output", str(trusted))
        t = packed.decode(trusted.read_bytes())
        assert t.metadata.flags == (1 | 8 | 16)
        assert t.metadata.sid_model == 2 and t.metadata.timing_standard == 2
        assert t.metadata.stream_cycles == (1_250 * 1_022_727 + 999) // 1000
        assert t.metadata.duration_cycles == t.metadata.stream_cycles

        # Two producers serialize on flock and publish one identical cache object.
        concurrent = root / "concurrent"
        command = [str(args.binary), "--input", str(source), "--cache-root",
                   str(concurrent), "--fallback-seconds", "1"]
        left = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        right = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        lo, le = left.communicate(timeout=30)
        ro, re = right.communicate(timeout=30)
        assert left.returncode == right.returncode == 0, (le, re)
        assert lo == ro and packed.decode(Path(lo.strip()).read_bytes())
        assert not list(concurrent.glob("*.tmp.*"))

        # A cache pair is not reported successful until its containing
        # directory has been fsynced after both atomic renames.
        if args.test_binary:
            durability_cache = root / "durability"
            environment = os.environ.copy()
            environment["MEGAVGM_TEST_DIRECTORY_FSYNC_FAILURE"] = "1"
            failed_sync = subprocess.run([
                str(args.test_binary), "--input", str(source), "--cache-root",
                str(durability_cache), "--fallback-seconds", "1",
            ], text=True, capture_output=True, env=environment)
            assert failed_sync.returncode != 0
            assert "cache directory fsync" in failed_sync.stderr
            pair = list(durability_cache.glob("*.mvgmsid"))
            assert len(pair) == 1 and pair[0].with_suffix(".json").is_file()
            # A fully written pair that raced with cancellation/failure may be
            # reused, but only through the ordinary strict cache-hit gate.
            recovered = run(args.binary, "--input", str(source), "--cache-root",
                            str(durability_cache), "--fallback-seconds", "1")
            assert Path(recovered.stdout.strip()) == pair[0]

        if args.capacity_test_binary:
            capacity = subprocess.run([str(args.capacity_test_binary)], text=True,
                                      capture_output=True)
            assert capacity.returncode == 0, capacity.stderr
            assert "8 MiB capacity tests PASS" in capacity.stdout

        # Neither half of a cache pair is authoritative by itself.
        partial = root / "partial"
        complete = run(args.binary, "--input", str(source), "--cache-root",
                       str(partial), "--fallback-seconds", "1")
        partial_payload = Path(complete.stdout.strip())
        partial_provenance = partial_payload.with_suffix(".json")
        payload_bytes = partial_payload.read_bytes()
        provenance_bytes = partial_provenance.read_bytes()
        partial_payload.unlink()
        run(args.binary, "--input", str(source), "--cache-root", str(partial),
            "--fallback-seconds", "1")
        assert partial_payload.read_bytes() == payload_bytes
        partial_provenance.unlink()
        run(args.binary, "--input", str(source), "--cache-root", str(partial),
            "--fallback-seconds", "1")
        assert partial_provenance.read_bytes() == provenance_bytes

        # Optional real-corpus direct-v2 vs frozen C1->v2 byte equivalence.
        if args.commando and args.c1_reference:
            direct = root / "commando.mvgmsid"
            run(args.binary, "--input", str(args.commando), "--output", str(direct),
                "--fallback-seconds", "60")
            assert direct.read_bytes() == args.c1_reference.read_bytes()

    print("Engine C C6 converter tests PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
