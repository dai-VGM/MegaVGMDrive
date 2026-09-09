#!/bin/sh
# Existing remote3-arm-gate Lima only. No new VM/toolchain installation.
set -eu
cd "$(dirname "$0")/.."
test -f cmd/megavgm_remote/web/build/megavgm.html
mkdir -p artifacts
env GOOS=linux GOARCH=arm GOARM=7 CGO_ENABLED=1 \
  CC=arm-linux-gnueabihf-gcc GOPROXY=off \
  /opt/go1.21.9/bin/go build -trimpath \
  -ldflags='-s -w -linkmode external -extldflags -static' \
  -o artifacts/megavgm_remote.phase1 ./cmd/megavgm_remote
file artifacts/megavgm_remote.phase1
arm-linux-gnueabihf-readelf -h -A -l -d artifacts/megavgm_remote.phase1
sha256sum artifacts/megavgm_remote.phase1
