#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
: "${ARM_CXX:?set ARM_CXX to arm-none-linux-gnueabihf-g++}"
: "${ARM_CC:?set ARM_CC to arm-none-linux-gnueabihf-gcc}"
tool_prefix="${ARM_TOOL_PREFIX:-${ARM_CXX%g++}}"
export CC="$ARM_CC" CXX="$ARM_CXX" AR="${tool_prefix}ar" RANLIB="${tool_prefix}ranlib" STRIP="${tool_prefix}strip"
export MEGAVGM_SID_BUILD_DIR="${MEGAVGM_SID_BUILD_DIR:-$script_dir/.build-arm}"
export CFLAGS="${CFLAGS:--O2}"
export CXXFLAGS="${CXXFLAGS:--O2}"

# build_native's configure invocation is host-native; perform the cross build
# explicitly and then use the identical final compile inputs.
archive="${MEGAVGM_LIBSIDPLAYFP_ARCHIVE:-$MEGAVGM_SID_BUILD_DIR/downloads/libsidplayfp-3.1.1.tar.gz}"
expected=12b79190593bf480b2d11481b5c2de62bac07f344437a66cd8d887329875c626
source_dir="$MEGAVGM_SID_BUILD_DIR/source/libsidplayfp-3.1.1"
install_dir="$MEGAVGM_SID_BUILD_DIR/install"
mkdir -p "$MEGAVGM_SID_BUILD_DIR/downloads" "$MEGAVGM_SID_BUILD_DIR/source" "$install_dir" "$MEGAVGM_SID_BUILD_DIR/bin"
if [ ! -f "$archive" ]; then curl --fail --location --output "$archive" https://github.com/libsidplayfp/libsidplayfp/releases/download/v3.1.1/libsidplayfp-3.1.1.tar.gz; fi
[ "$(sha256sum "$archive" | awk '{print $1}')" = "$expected" ] || { echo 'libsidplayfp archive SHA mismatch' >&2; exit 2; }
if [ ! -f "$source_dir/.megavgm-observer-patched" ]; then
  [ ! -e "$source_dir" ] || { echo "refusing incomplete source: $source_dir" >&2; exit 2; }
  tar -xzf "$archive" -C "$MEGAVGM_SID_BUILD_DIR/source"
  (cd "$source_dir" && patch -p1 < "$script_dir/patches/libsidplayfp-3.1.1-write-observer.patch" && touch .megavgm-observer-patched)
fi
if [ ! -f "$install_dir/lib/libsidplayfp.a" ]; then
  (cd "$source_dir" && ./configure --build="${BUILD_TRIPLE:-x86_64-pc-linux-gnu}" --host=arm-none-linux-gnueabihf --prefix="$install_dir" --enable-static --disable-shared --with-pic --without-usbsid --without-exsid --disable-testsuite --disable-tests && make -j"${MEGAVGM_SID_JOBS:-4}" && make install)
fi
cp "$source_dir/src/sidplayfp/SidWriteObserver.h" "$install_dir/include/sidplayfp/SidWriteObserver.h"
commit="$(git -C "$script_dir" rev-parse HEAD 2>/dev/null || echo unknown)"
"$ARM_CXX" -std=c++17 -O2 -Wall -Wextra -Wpedantic -Werror -static \
  -DMEGAVGM_SID_PREPARE_COMMIT="\"$commit\"" \
  -DMVGMSID_LIBSIDPLAYFP_COMMIT='"732fa8ec8131fc75aafc2eaea583ddcdeea2a3cc"' \
  -I"$install_dir/include" "$script_dir/native/megavgm_sid_prepare.cpp" \
  "$script_dir/native/packed_v2.cpp" "$script_dir/native/sha256.cpp" \
  "$install_dir/lib/libsidplayfp.a" -lpthread -lm -o "$MEGAVGM_SID_BUILD_DIR/bin/megavgm_sid_prepare"
"$STRIP" "$MEGAVGM_SID_BUILD_DIR/bin/megavgm_sid_prepare"
file "$MEGAVGM_SID_BUILD_DIR/bin/megavgm_sid_prepare"
readelf -l -d -A "$MEGAVGM_SID_BUILD_DIR/bin/megavgm_sid_prepare"
sha256sum "$MEGAVGM_SID_BUILD_DIR/bin/megavgm_sid_prepare"
