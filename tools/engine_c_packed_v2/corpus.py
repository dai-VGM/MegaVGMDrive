#!/usr/bin/env python3
"""Pack local v1 artifacts, compare every WRITE and emit reproducible evidence.

Outputs belong outside the repository; no SID music is distributed with tools.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sys

import packed


def measure(source: Path, destination: Path) -> dict:
    original = source.read_bytes()
    encoded = packed.pack(original)
    packed.equivalent(original, encoded)
    # Re-read the actual output rather than treating an in-memory check as disk proof.
    with destination.open('xb') as out:
        out.write(encoded)
    actual = destination.read_bytes()
    packed.equivalent(original, actual)
    report = packed.inspect(actual)
    metadata = report['metadata']
    seconds = metadata['stream_cycles'] * metadata['clock_den'] / metadata['clock_num']
    report.update(source_name=source.name, output_name=destination.name,
                  v1_bytes=len(original), v1_sha256=hashlib.sha256(original).hexdigest(),
                  v2_bytes=len(actual), v2_over_v1=len(actual) / len(original),
                  bytes_per_write_including_eof=((len(actual) - 128) / report['write_count']
                                                  if report['write_count'] else None),
                  capture_seconds=seconds,
                  estimated_4mib_seconds_at_observed_density=(
                      (4 * 1024 * 1024 - 128) * seconds / (len(actual) - 128)),
                  equivalence='every WRITE + EOF + all canonical metadata exactly equal',
                  deterministic=encoded == packed.pack(original))
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('inputs', nargs='+', type=Path)
    parser.add_argument('--output-dir', required=True, type=Path)
    args = parser.parse_args()
    try:
        names = [p.stem + '.mvgmsid2' for p in args.inputs]
        if len(set(names)) != len(names):
            raise ValueError('duplicate output names')
        args.output_dir.mkdir(parents=True, exist_ok=False)
        reports = [measure(src, args.output_dir / name) for src, name in zip(args.inputs, names)]
        with (args.output_dir / 'results.json').open('x') as out:
            json.dump(reports, out, indent=2, sort_keys=True)
            out.write('\n')
        print('| Input | v1 bytes | v2 bytes | v2/v1 | WRITEs | bytes/WRITE* | max delta | ULEB histogram** | 4MiB seconds*** |')
        print('|---|---:|---:|---:|---:|---:|---:|---|---:|')
        for r in reports:
            avg = r['bytes_per_write_including_eof']
            avg_text = f'{avg:.4f}' if avg is not None else 'n/a'
            print(f"| {r['source_name']} | {r['v1_bytes']:,} | {r['v2_bytes']:,} | "
                  f"{r['v2_over_v1']:.2%} | {r['write_count']:,} | {avg_text} | "
                  f"{r['maximum_delta']:,} | {r['varint_length_histogram']} | "
                  f"{r['estimated_4mib_seconds_at_observed_density']:.1f} |")
        print('\n* Body bytes including EOF / WRITE count; header excluded.\n'
              '** Varint-byte-length: record count, including EOF.\n'
              '*** Density extrapolation only, not a measured full-song capacity guarantee; '
              'current C4 does not decode v2.')
        return 0
    except (OSError, ValueError) as exc:
        print(f'ERROR: {exc}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
