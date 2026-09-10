#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
BUILD_DIR="${MVGMSID_C1_BUILD_DIR:-$SCRIPT_DIR/.build}"
ARCHIVE="$BUILD_DIR/downloads/libsidplayfp-3.1.1.tar.gz"
SOURCE_DIR="$BUILD_DIR/source/libsidplayfp-3.1.1"
INSTALL_DIR="$BUILD_DIR/install"
BIN_DIR="$BUILD_DIR/bin"
EXPECTED_SHA="12b79190593bf480b2d11481b5c2de62bac07f344437a66cd8d887329875c626"
URL="https://github.com/libsidplayfp/libsidplayfp/releases/download/v3.1.1/libsidplayfp-3.1.1.tar.gz"
PATCH_FILE="$SCRIPT_DIR/patches/libsidplayfp-3.1.1-write-observer.patch"

mkdir -p "$BUILD_DIR/downloads" "$BUILD_DIR/source" "$INSTALL_DIR" "$BIN_DIR"

if [[ ! -f "$ARCHIVE" ]]; then
  curl --fail --location --output "$ARCHIVE" "$URL"
fi

ACTUAL_SHA="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
if [[ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]]; then
  echo "libsidplayfp archive SHA-256 mismatch: $ACTUAL_SHA" >&2
  exit 2
fi

if [[ ! -f "$SOURCE_DIR/.mvgmsid-patched" ]]; then
  if [[ -e "$SOURCE_DIR" ]]; then
    echo "Refusing to reuse incomplete source directory: $SOURCE_DIR" >&2
    echo "Remove only that directory, then rerun." >&2
    exit 2
  fi
  tar -xzf "$ARCHIVE" -C "$BUILD_DIR/source"
  (
    cd "$SOURCE_DIR"
    patch -p1 < "$PATCH_FILE"
    touch .mvgmsid-patched
  )
fi

if [[ ! -f "$INSTALL_DIR/lib/libsidplayfp.a" ]]; then
  (
    cd "$SOURCE_DIR"
    ./configure \
      --prefix="$INSTALL_DIR" \
      --enable-static \
      --disable-shared \
      --with-pic \
      --without-usbsid \
      --without-exsid \
      --disable-testsuite \
      --disable-tests
    make -j"${MVGMSID_C1_JOBS:-4}"
    make install
  )
fi

# The observer is a C1-only public header. It is deliberately not added to
# upstream Makefile.am so the official release archive remains buildable
# without regenerating autotools files.
mkdir -p "$INSTALL_DIR/include/sidplayfp"
cp "$SOURCE_DIR/src/sidplayfp/SidWriteObserver.h" \
  "$INSTALL_DIR/include/sidplayfp/SidWriteObserver.h"

"${CXX:-c++}" \
  -std=c++17 -O2 -Wall -Wextra -Wpedantic \
  -DMVGMSID_LIBSIDPLAYFP_COMMIT='"732fa8ec8131fc75aafc2eaea583ddcdeea2a3cc"' \
  -I"$INSTALL_DIR/include" \
  "$SCRIPT_DIR/native/sid_capture.cpp" \
  "$INSTALL_DIR/lib/libsidplayfp.a" \
  -lpthread -lm \
  -o "$BIN_DIR/sid_capture"

echo "$BIN_DIR/sid_capture"
