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
for space, limit, tag in (("A", 0x100000, 0), ("B", 0x1000000, 1)):
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

# JT10-compatible Neo Geo no-op writes.  Port-1 register 02 is the ADPCM-A
# test-register location; FM operator selector 3 is the physical channel hole;
# operator selector 0 is an inaudible insertion-slot channel in YM2610 mode.
# Both modes accept them, while key/frequency/control access to selector 0 and
# semantically different reserved encodings remain strict scanner rejects.
for fixture in adpcma_test_noop fm_operator_hole_noop fm_operator_hole_noop_b \
               fm_operator_insertion_slot_noop fm_operator_insertion_slot_b; do
  vvp "$build_dir/scanner.vvp" \
    "+VGM=$build_dir/fixtures/$fixture.vgm" \
    +EXPECT_ACCEPTED=1 +EXPECT_REJECT=00 +EXPECT_DESC_A=0 +EXPECT_DESC_B=0
done
for fixture in unknown_register reserved_adpcma_03 \
               reserved_keyon_selector3 reserved_fm_frequency_hole; do
  vvp "$build_dir/scanner.vvp" \
    "+VGM=$build_dir/fixtures/$fixture.vgm" \
    +EXPECT_ACCEPTED=0 +EXPECT_REJECT=04 +EXPECT_DESC_A=0 +EXPECT_DESC_B=0
done
echo "YM2610_NEO_GEO_NOOP_POLICY adpcma_test02=PASS fm_operator_slot0=PASS fm_operator_hole3=PASS keyon_selector3_reject=PASS adjacent_reserved_reject=PASS result=PASS"

for count in 0 1 8 9 10 11 64; do
  vvp "$build_dir/scanner.vvp" \
    "+VGM=$build_dir/fixtures/descriptor_a_${count}.vgm" \
    +EXPECT_ACCEPTED=1 +EXPECT_REJECT=00 +EXPECT_DESC_A="$count" +EXPECT_DESC_B=0
done
vvp "$build_dir/scanner.vvp" \
  "+VGM=$build_dir/fixtures/descriptor_a_65.vgm" \
  +EXPECT_ACCEPTED=0 +EXPECT_REJECT=08 +EXPECT_DESC_A=64 +EXPECT_DESC_B=0
for count in 10 11 16; do
  vvp "$build_dir/scanner.vvp" \
    "+VGM=$build_dir/fixtures/descriptor_b_${count}.vgm" \
    +EXPECT_ACCEPTED=1 +EXPECT_REJECT=00 +EXPECT_DESC_A=0 +EXPECT_DESC_B="$count"
done
vvp "$build_dir/scanner.vvp" \
  "+VGM=$build_dir/fixtures/descriptor_b_17.vgm" \
  +EXPECT_ACCEPTED=0 +EXPECT_REJECT=08 +EXPECT_DESC_A=0 +EXPECT_DESC_B=16
vvp "$build_dir/scanner.vvp" \
  "+VGM=$build_dir/fixtures/descriptor_a10_b3.vgm" \
  +EXPECT_ACCEPTED=1 +EXPECT_REJECT=00 +EXPECT_DESC_A=10 +EXPECT_DESC_B=3

PYTHONDONTWRITEBYTECODE=1 python3 - "$repo_dir" \
  "$build_dir/fixtures/wide_a_24bit.vgm" "$build_dir/wide-a.map" <<'PY'
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(sys.argv[1]) / "tools"))
from inspect_ym2610_vgm import inspect, map_rom

source = pathlib.Path(sys.argv[2])
target = pathlib.Path(sys.argv[3])
result = inspect(source)
payload = source.read_bytes()
addresses = (0x0FFFFE, 0x0FFFFF, 0x100000, 0x100001,
             0x168B00, 0x16AFFF, 0x170000, 0x17EAFF,
             0x301AFF, 0x100002)
rows = []
for address in addresses:
    mapped = map_rom(result.descriptors, "A", address)
    rows.append((0, address, int(mapped is not None), mapped or 0,
                 payload[mapped] if mapped is not None else 0))
target.write_text("".join(
    f"{space} {logical:06x} {hit} {file:06x} {byte:02x}\n"
    for space, logical, hit, file, byte in rows))
PY
vvp "$build_dir/scanner.vvp" \
  "+VGM=$build_dir/fixtures/wide_a_24bit.vgm" \
  "+MAP=$build_dir/wide-a.map" \
  +EXPECT_ACCEPTED=1 +EXPECT_REJECT=00 +EXPECT_DESC_A=6 +EXPECT_DESC_B=0
vvp "$build_dir/scanner.vvp" \
  "+VGM=$build_dir/fixtures/a_exact_end.vgm" \
  +EXPECT_ACCEPTED=1 +EXPECT_REJECT=00 +EXPECT_DESC_A=1 +EXPECT_DESC_B=0
printf '0 ffffff 1 00008f c7\n' >"$build_dir/a-last.map"
vvp "$build_dir/scanner.vvp" \
  "+VGM=$build_dir/fixtures/a_last_address.vgm" \
  "+MAP=$build_dir/a-last.map" \
  +EXPECT_ACCEPTED=1 +EXPECT_REJECT=00 +EXPECT_DESC_A=1 +EXPECT_DESC_B=0
for fixture in a_declared_overflow a_space_overflow a_declared_over_24; do
  vvp "$build_dir/scanner.vvp" \
    "+VGM=$build_dir/fixtures/$fixture.vgm" \
    +EXPECT_ACCEPTED=0 +EXPECT_REJECT=07 +EXPECT_DESC_A=0 +EXPECT_DESC_B=0
done
vvp "$build_dir/scanner.vvp" \
  "+VGM=$build_dir/fixtures/a_zero_length.vgm" \
  +EXPECT_ACCEPTED=1 +EXPECT_REJECT=00 +EXPECT_DESC_A=0 +EXPECT_DESC_B=0

# Empty 0x83 blocks are metadata only. Nonempty blocks independently obey
# their declared size and the full 24-bit logical B contract.
vvp "$build_dir/scanner.vvp" \
  "+VGM=$build_dir/fixtures/empty_b_512k.vgm" \
  +EXPECT_ACCEPTED=1 +EXPECT_REJECT=00 +EXPECT_DESC_A=0 +EXPECT_DESC_B=0
vvp "$build_dir/scanner.vvp" \
  "+VGM=$build_dir/fixtures/empty_b_1m.vgm" \
  +EXPECT_ACCEPTED=1 +EXPECT_REJECT=00 +EXPECT_DESC_A=0 +EXPECT_DESC_B=0
vvp "$build_dir/scanner.vvp" \
  "+VGM=$build_dir/fixtures/valid_b_512k.vgm" \
  +EXPECT_ACCEPTED=1 +EXPECT_REJECT=00 +EXPECT_DESC_A=0 +EXPECT_DESC_B=1
vvp "$build_dir/scanner.vvp" \
  "+VGM=$build_dir/fixtures/valid_b_1m_low.vgm" \
  +EXPECT_ACCEPTED=1 +EXPECT_REJECT=00 +EXPECT_DESC_A=0 +EXPECT_DESC_B=1
vvp "$build_dir/scanner.vvp" \
  "+VGM=$build_dir/fixtures/valid_b_8m_low.vgm" \
  +EXPECT_ACCEPTED=1 +EXPECT_REJECT=00 +EXPECT_DESC_A=0 +EXPECT_DESC_B=1
vvp "$build_dir/scanner.vvp" \
  "+VGM=$build_dir/fixtures/b_declared_too_small.vgm" \
  +EXPECT_ACCEPTED=0 +EXPECT_REJECT=07 +EXPECT_DESC_A=0 +EXPECT_DESC_B=0
vvp "$build_dir/scanner.vvp" \
  "+VGM=$build_dir/fixtures/b_above_window.vgm" \
  +EXPECT_ACCEPTED=1 +EXPECT_REJECT=00 +EXPECT_DESC_A=0 +EXPECT_DESC_B=1
vvp "$build_dir/scanner.vvp" \
  "+VGM=$build_dir/fixtures/b_arithmetic_overflow.vgm" \
  +EXPECT_ACCEPTED=0 +EXPECT_REJECT=07 +EXPECT_DESC_A=0 +EXPECT_DESC_B=0
vvp "$build_dir/scanner.vvp" \
  "+VGM=$build_dir/fixtures/malformed_b.vgm" \
  +EXPECT_ACCEPTED=0 +EXPECT_REJECT=06 +EXPECT_DESC_A=0 +EXPECT_DESC_B=0
vvp "$build_dir/scanner.vvp" \
  "+VGM=$build_dir/fixtures/empty_b_with_a.vgm" \
  +EXPECT_ACCEPTED=1 +EXPECT_REJECT=00 +EXPECT_DESC_A=2 +EXPECT_DESC_B=0
vvp "$build_dir/scanner.vvp" \
  "+VGM=$build_dir/fixtures/empty_b_then_valid.vgm" \
  +EXPECT_ACCEPTED=1 +EXPECT_REJECT=00 +EXPECT_DESC_A=0 +EXPECT_DESC_B=1
vvp "$build_dir/scanner.vvp" \
  "+VGM=$build_dir/fixtures/empty_b_then_invalid.vgm" \
  +EXPECT_ACCEPTED=0 +EXPECT_REJECT=07 +EXPECT_DESC_A=0 +EXPECT_DESC_B=0
vvp "$build_dir/scanner.vvp" \
  "+VGM=$build_dir/fixtures/b_out_of_range.vgm" \
  +EXPECT_ACCEPTED=0 +EXPECT_REJECT=07 +EXPECT_DESC_A=0 +EXPECT_DESC_B=0
vvp "$build_dir/scanner.vvp" \
  "+VGM=$build_dir/fixtures/b_overlap.vgm" \
  +EXPECT_ACCEPTED=0 +EXPECT_REJECT=08 +EXPECT_DESC_A=0 +EXPECT_DESC_B=1
PYTHONDONTWRITEBYTECODE=1 python3 - "$repo_dir" \
  "$build_dir/fixtures/wide_b_24bit.vgm" "$build_dir/wide-b.map" <<'PY'
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(sys.argv[1]) / "tools"))
from inspect_ym2610_vgm import inspect, map_rom

source = pathlib.Path(sys.argv[2])
target = pathlib.Path(sys.argv[3])
result = inspect(source)
payload = source.read_bytes()
addresses = (0x07FFFE, 0x07FFFF, 0x080000, 0x080001,
             0x0FFFFE, 0x0FFFFF, 0x100000, 0x100001,
             0x710300, 0x71030F, 0x717AF0, 0x717AFF,
             0x080002, 0x700000, 0x717B00)
rows = []
for address in addresses:
    mapped = map_rom(result.descriptors, "B", address)
    rows.append((1, address, int(mapped is not None), mapped or 0,
                 payload[mapped] if mapped is not None else 0))
target.write_text("".join(
    f"{space} {logical:06x} {hit} {file:06x} {byte:02x}\n"
    for space, logical, hit, file, byte in rows))
PY
vvp "$build_dir/scanner.vvp" \
  "+VGM=$build_dir/fixtures/wide_b_24bit.vgm" \
  "+MAP=$build_dir/wide-b.map" \
  +EXPECT_ACCEPTED=1 +EXPECT_REJECT=00 +EXPECT_DESC_A=0 +EXPECT_DESC_B=4
vvp "$build_dir/scanner.vvp" \
  "+VGM=$build_dir/fixtures/b_exact_end.vgm" \
  +EXPECT_ACCEPTED=1 +EXPECT_REJECT=00 +EXPECT_DESC_A=0 +EXPECT_DESC_B=1
for fixture in b_declared_over_24 b_space_overflow; do
  vvp "$build_dir/scanner.vvp" \
    "+VGM=$build_dir/fixtures/$fixture.vgm" \
    +EXPECT_ACCEPTED=0 +EXPECT_REJECT=07 +EXPECT_DESC_A=0 +EXPECT_DESC_B=0
done
echo "YM2610_B_DECLARED_SIZE_POLICY declared_512k=PASS declared_1m=PASS declared_8m=PASS declared_end=PASS logical_24bit=PASS start_above_old_window=PASS overflow=PASS empty=PASS result=PASS"

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
for space, limit, tag in (("A", 0x100000, 0), ("B", 0x1000000, 1)):
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
