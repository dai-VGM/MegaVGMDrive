#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "$0")/../.." && pwd)
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/ym2610-scanner.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT

iverilog -g2012 -s tb_ym2610_player_scanner \
  -o "$build_dir/scanner.vvp" \
  "$repo_dir/rtl/ym2610_player/ym2610_player_compat.sv" \
  "$repo_dir/rtl/ym2610_player/ym2610_player_scanner.sv" \
  "$repo_dir/tb/ym2610_player/tb_ym2610_player_scanner.sv"

python3 "$repo_dir/tools/generate_ym2610_test_vgms.py" "$build_dir/fixtures" >/dev/null
for fixture in "$build_dir"/fixtures/*.vgm; do
  map_arg=""
  if [[ "$(basename "$fixture")" == "standard_all_raw.vgm" ]]; then
    PYTHONDONTWRITEBYTECODE=1 python3 - "$repo_dir" "$fixture" "$build_dir/synthetic.map" <<'PY'
import pathlib
import random
import sys

sys.path.insert(0, str(pathlib.Path(sys.argv[1]) / "tools"))
from inspect_ym2610_vgm import inspect, map_rom

source = pathlib.Path(sys.argv[2])
target = pathlib.Path(sys.argv[3])
result = inspect(source)
payload = source.read_bytes()
rng = random.Random(0x2610)
rows = []
for space, limit, tag in (("A", 0x100000, 0), ("B", 0x80000, 1)):
    descriptors = [d for d in result.descriptors if d.space == space]
    for descriptor in descriptors:
        for logical in (descriptor.logical_start, descriptor.logical_end - 1):
            mapped = map_rom(descriptors, space, logical)
            rows.append((tag, logical, 1, mapped, payload[mapped]))
    for _ in range(256):
        descriptor = rng.choice(descriptors)
        logical = rng.randrange(descriptor.logical_start, descriptor.logical_end)
        mapped = map_rom(descriptors, space, logical)
        rows.append((tag, logical, 1, mapped, payload[mapped]))
    for logical in range(limit):
        if map_rom(descriptors, space, logical) is None:
            rows.append((tag, logical, 0, 0, 0))
            break
target.write_text("".join(f"{space} {logical:05x} {hit} {file:06x} {byte:02x}\n"
                          for space, logical, hit, file, byte in rows))
PY
    map_arg="+MAP=$build_dir/synthetic.map"
  fi
  if [[ -n "$map_arg" ]]; then
    vvp "$build_dir/scanner.vvp" "+VGM=$fixture" "$map_arg"
  else
    vvp "$build_dir/scanner.vvp" "+VGM=$fixture"
  fi
done

for count in 0 1 8 9 10; do
  vvp "$build_dir/scanner.vvp" \
    "+VGM=$build_dir/fixtures/descriptor_a_${count}.vgm" \
    +EXPECT_ACCEPTED=1 +EXPECT_REJECT=00 +EXPECT_DESC_A="$count" +EXPECT_DESC_B=0
done
vvp "$build_dir/scanner.vvp" \
  "+VGM=$build_dir/fixtures/descriptor_a_11.vgm" \
  +EXPECT_ACCEPTED=0 +EXPECT_REJECT=08 +EXPECT_DESC_A=10 +EXPECT_DESC_B=0
for count in 10; do
  vvp "$build_dir/scanner.vvp" \
    "+VGM=$build_dir/fixtures/descriptor_b_${count}.vgm" \
    +EXPECT_ACCEPTED=1 +EXPECT_REJECT=00 +EXPECT_DESC_A=0 +EXPECT_DESC_B="$count"
done
vvp "$build_dir/scanner.vvp" \
  "+VGM=$build_dir/fixtures/descriptor_b_11.vgm" \
  +EXPECT_ACCEPTED=0 +EXPECT_REJECT=08 +EXPECT_DESC_A=0 +EXPECT_DESC_B=10
vvp "$build_dir/scanner.vvp" \
  "+VGM=$build_dir/fixtures/descriptor_a10_b3.vgm" \
  +EXPECT_ACCEPTED=1 +EXPECT_REJECT=00 +EXPECT_DESC_A=10 +EXPECT_DESC_B=3

if [[ -f "/Users/daizo/Music/03 Olga Breeze.vgm" ]]; then
  PYTHONDONTWRITEBYTECODE=1 python3 - "$repo_dir" "/Users/daizo/Music/03 Olga Breeze.vgm" "$build_dir/olga.map" <<'PY'
import pathlib
import random
import sys

sys.path.insert(0, str(pathlib.Path(sys.argv[1]) / "tools"))
from inspect_ym2610_vgm import inspect, map_rom

source = pathlib.Path(sys.argv[2])
target = pathlib.Path(sys.argv[3])
result = inspect(source)
payload = source.read_bytes()
rng = random.Random(0x2610)
rows = []
for space, limit, tag in (("A", 0x100000, 0), ("B", 0x80000, 1)):
    descriptors = [d for d in result.descriptors if d.space == space]
    for descriptor in descriptors:
        for logical in (descriptor.logical_start, descriptor.logical_end - 1):
            mapped = map_rom(descriptors, space, logical)
            rows.append((tag, logical, 1, mapped, payload[mapped]))
        for logical in (descriptor.logical_start - 1, descriptor.logical_end):
            if 0 <= logical < limit and map_rom(descriptors, space, logical) is None:
                rows.append((tag, logical, 0, 0, 0))
    for _ in range(256):
        descriptor = rng.choice(descriptors)
        logical = rng.randrange(descriptor.logical_start, descriptor.logical_end)
        mapped = map_rom(descriptors, space, logical)
        rows.append((tag, logical, 1, mapped, payload[mapped]))
target.write_text("".join(f"{space} {logical:05x} {hit} {file:06x} {byte:02x}\n"
                          for space, logical, hit, file, byte in rows))
PY
  vvp "$build_dir/scanner.vvp" "+VGM=/Users/daizo/Music/03 Olga Breeze.vgm" "+MAP=$build_dir/olga.map"
fi
