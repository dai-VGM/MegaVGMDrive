#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "$0")/../.." && pwd)
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/ym2610-parser.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT

iverilog -g2012 -s tb_ym2610_player_parser \
  -o "$build_dir/parser.vvp" \
  "$repo_dir/rtl/ym2610_player/ym2610_player_parser.sv" \
  "$repo_dir/tb/ym2610_player/tb_ym2610_player_parser.sv"

python3 "$repo_dir/tools/generate_ym2610_test_vgms.py" "$build_dir/fixtures" >/dev/null
python3 "$repo_dir/tools/inspect_ym2610_vgm.py" \
  "$build_dir/fixtures/standard_all_raw.vgm" --json >"$build_dir/reference.json"
vvp "$build_dir/parser.vvp" "+VGM=$build_dir/fixtures/standard_all_raw.vgm" |
  tee "$build_dir/synthetic.log"

if [[ -f "/Users/daizo/Music/03 Olga Breeze.vgm" ]]; then
  python3 "$repo_dir/tools/inspect_ym2610_vgm.py" \
    "/Users/daizo/Music/03 Olga Breeze.vgm" --json >"$build_dir/olga-reference.json"
  vvp "$build_dir/parser.vvp" "+VGM=/Users/daizo/Music/03 Olga Breeze.vgm" |
    tee "$build_dir/olga.log"
fi

python3 - "$build_dir" <<'PY'
import json
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
for stem, reference_name in (("synthetic", "reference.json"),
                             ("olga", "olga-reference.json")):
    log = root / f"{stem}.log"
    reference_path = root / reference_name
    if not log.exists():
        continue
    reference = json.loads(reference_path.read_text())
    rows = re.findall(r"PARSER_RESULT run=(\d+) writes=(\d+) p0=(\d+) p1=(\d+) samples=(\d+) hash=([0-9a-f]+) first256=([0-9a-f]+)", log.read_text())
    assert len(rows) == 2, rows
    for row in rows:
        _, writes, p0, p1, samples, trace_hash, first_hash = row
        assert int(writes) == reference["total_writes"]
        assert int(p0) == reference["port0_writes"]
        assert int(p1) == reference["port1_writes"]
        assert int(samples) == reference["total_samples"]
        assert trace_hash == reference["trace_hash"]
        assert first_hash == reference["first_256_trace_hash"]
    print(f"{stem} parser/reference exact PASS")
PY
