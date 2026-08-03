#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "$0")/../.." && pwd)
olga="/Users/daizo/Music/03 Olga Breeze.vgm"
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/ym2610-olga.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT

if [[ ! -f "$olga" ]]; then
  echo "missing acceptance file: $olga" >&2
  exit 1
fi
actual_sha=$(shasum -a 256 "$olga" | awk '{print $1}')
if [[ "$actual_sha" != "7fd15fe7bf9537128bc2eb2db957a8ccf40cdac394675137a40ba2a9daa66246" ]]; then
  echo "Olga acceptance SHA-256 mismatch" >&2
  exit 1
fi

python3 "$repo_dir/tools/generate_ym2610_test_vgms.py" \
  "$build_dir/fixtures" --olga "$olga" >/dev/null
(
  cd "$repo_dir"
  iverilog -g2012 -s tb_ym2610_player_core \
    -o "$build_dir/core.vvp" \
    -f tb/ym2610_player/ym2610_player_sources.f \
    tb/ym2610_player/tb_ym2610_player_core.sv
  iverilog -g2012 -s tb_ym2610_player_parser \
    -o "$build_dir/parser.vvp" \
    rtl/ym2610_player/ym2610_player_parser.sv \
    tb/ym2610_player/tb_ym2610_player_parser.sv
)

cases=(
  "olga_adpcmb_window.vgm:B"
  "olga_fm_window.vgm:FM"
  "olga_adpcma_window.vgm:A"
  "olga_ab_window.vgm:AB"
  "olga_loop_window.vgm:LOOP"
)
if [[ -n "${YM2610_WINDOW_ONLY:-}" ]]; then
  case "$YM2610_WINDOW_ONLY" in
    B) cases=("olga_adpcmb_window.vgm:B") ;;
    FM) cases=("olga_fm_window.vgm:FM") ;;
    A) cases=("olga_adpcma_window.vgm:A") ;;
    AB) cases=("olga_ab_window.vgm:AB") ;;
    LOOP) cases=("olga_loop_window.vgm:LOOP") ;;
    *) echo "unknown YM2610_WINDOW_ONLY=$YM2610_WINDOW_ONLY" >&2; exit 1 ;;
  esac
fi
for item in "${cases[@]}"; do
  fixture=${item%%:*}
  expect=${item##*:}
  path="$build_dir/fixtures/$fixture"
  python3 "$repo_dir/tools/inspect_ym2610_vgm.py" "$path" --json \
    >"$build_dir/$expect-reference.json"
  vvp "$build_dir/parser.vvp" "+VGM=$path" >"$build_dir/$expect-parser.log"
  pids=()
  for run in 1 2 3; do
    vvp "$build_dir/core.vvp" "+VGM=$path" "+EXPECT=$expect" \
      >"$build_dir/$expect-core-$run.log" &
    pids+=("$!")
  done
  for pid in "${pids[@]}"; do
    wait "$pid"
  done
  result_pattern='^(CORE_RESULT|LOOP_RESULT)'
  grep -E "$result_pattern" "$build_dir/$expect-core-1.log"
  diff -u <(grep -E "$result_pattern" "$build_dir/$expect-core-1.log") \
          <(grep -E "$result_pattern" "$build_dir/$expect-core-2.log")
  diff -u <(grep -E "$result_pattern" "$build_dir/$expect-core-1.log") \
          <(grep -E "$result_pattern" "$build_dir/$expect-core-3.log")
done

python3 - "$build_dir" <<'PY'
import json
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
for lane in ("B", "FM", "A", "AB", "LOOP"):
    reference_path = root / f"{lane}-reference.json"
    if not reference_path.exists():
        continue
    reference = json.loads(reference_path.read_text())
    rows = re.findall(
        r"PARSER_RESULT run=(\d+) writes=(\d+) p0=(\d+) p1=(\d+) samples=(\d+) hash=([0-9a-f]+) first256=([0-9a-f]+)",
        (root / f"{lane}-parser.log").read_text())
    assert len(rows) == 2, (lane, rows)
    for _, writes, p0, p1, samples, trace_hash, first_hash in rows:
        assert int(writes) == reference["total_writes"]
        assert int(p0) == reference["port0_writes"]
        assert int(p1) == reference["port1_writes"]
        assert int(samples) == reference["total_samples"]
        assert trace_hash == reference["trace_hash"]
        assert first_hash == reference["first_256_trace_hash"]
    print(f"OLGA_WINDOW_TRACE lane={lane} writes={reference['total_writes']} "
          f"samples={reference['total_samples']} hash={reference['trace_hash']} "
          "cold_reload_exact=1 result=PASS")
PY
echo "OLGA_WINDOWS selection=${YM2610_WINDOW_ONLY:-B,FM,A,AB,LOOP} runs=3 underflow=0 xz=0 deterministic=1 result=PASS"
