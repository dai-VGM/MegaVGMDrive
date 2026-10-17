#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
build_dir="${MEGAVGM_SID_BUILD_DIR:-$script_dir/.build-native}"
archive="${MEGAVGM_LIBSIDPLAYFP_ARCHIVE:-$build_dir/downloads/libsidplayfp-3.1.1.tar.gz}"
source_dir="$build_dir/source/libsidplayfp-3.1.1"
install_dir="$build_dir/install"
expected=12b79190593bf480b2d11481b5c2de62bac07f344437a66cd8d887329875c626
mkdir -p "$build_dir/downloads" "$build_dir/source" "$install_dir" "$build_dir/bin"
if [ ! -f "$archive" ]; then
  curl --fail --location --output "$archive" https://github.com/libsidplayfp/libsidplayfp/releases/download/v3.1.1/libsidplayfp-3.1.1.tar.gz
fi
[ "$(shasum -a 256 "$archive" | awk '{print $1}')" = "$expected" ] || { echo 'libsidplayfp archive SHA mismatch' >&2; exit 2; }
if [ ! -f "$source_dir/.megavgm-observer-patched" ]; then
  [ ! -e "$source_dir" ] || { echo "refusing incomplete source: $source_dir" >&2; exit 2; }
  tar -xzf "$archive" -C "$build_dir/source"
  (cd "$source_dir" && patch -p1 < "$script_dir/patches/libsidplayfp-3.1.1-write-observer.patch" && touch .megavgm-observer-patched)
fi
if [ ! -f "$install_dir/lib/libsidplayfp.a" ]; then
  (cd "$source_dir" && ./configure --prefix="$install_dir" --enable-static --disable-shared --with-pic --without-usbsid --without-exsid --disable-testsuite --disable-tests && make -j"${MEGAVGM_SID_JOBS:-4}" && make install)
fi
cp "$source_dir/src/sidplayfp/SidWriteObserver.h" "$install_dir/include/sidplayfp/SidWriteObserver.h"
commit="$(git -C "$script_dir" rev-parse HEAD 2>/dev/null || echo unknown)"
"${CXX:-c++}" -std=c++17 -O2 -Wall -Wextra -Wpedantic -Werror \
  -DMEGAVGM_SID_PREPARE_COMMIT="\"$commit\"" \
  -DMVGMSID_LIBSIDPLAYFP_COMMIT='"732fa8ec8131fc75aafc2eaea583ddcdeea2a3cc"' \
  -I"$install_dir/include" "$script_dir/native/megavgm_sid_prepare.cpp" \
  "$script_dir/native/packed_v2.cpp" "$script_dir/native/sha256.cpp" \
  "$install_dir/lib/libsidplayfp.a" -lpthread -lm -o "$build_dir/bin/megavgm_sid_prepare"
"${CXX:-c++}" -std=c++17 -O2 -Wall -Wextra -Wpedantic -Werror \
  -DMEGAVGM_SID_PREPARE_TESTING \
  -DMEGAVGM_SID_PREPARE_COMMIT="\"$commit\"" \
  -DMVGMSID_LIBSIDPLAYFP_COMMIT='"732fa8ec8131fc75aafc2eaea583ddcdeea2a3cc"' \
  -I"$install_dir/include" "$script_dir/native/megavgm_sid_prepare.cpp" \
  "$script_dir/native/packed_v2.cpp" "$script_dir/native/sha256.cpp" \
  "$install_dir/lib/libsidplayfp.a" -lpthread -lm -o "$build_dir/bin/megavgm_sid_prepare_test"
"${CXX:-c++}" -std=c++17 -O2 -Wall -Wextra -Wpedantic -Werror \
  "$script_dir/native/test_packed_v2_capacity.cpp" "$script_dir/native/packed_v2.cpp" \
  -o "$build_dir/bin/test_packed_v2_capacity"
echo "$build_dir/bin/megavgm_sid_prepare"
