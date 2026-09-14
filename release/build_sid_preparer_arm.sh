#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: $0 EXPECTED_FULL_SOURCE_COMMIT CLEAN_SOURCE_CHECKOUT" >&2
  exit 2
fi

expected_commit="$1"
source_checkout="$(CDPATH= cd -- "$2" && pwd -P)"

case "$expected_commit" in
  *[!0-9a-f]*|'')
    echo "expected source commit must be a lowercase full 40-character SHA-1" >&2
    exit 2
    ;;
esac
[ "${#expected_commit}" -eq 40 ] || {
  echo "expected source commit must be a lowercase full 40-character SHA-1" >&2
  exit 2
}

[ "$(git -C "$source_checkout" rev-parse --is-inside-work-tree 2>/dev/null)" = true ] || {
  echo "source checkout is not a Git worktree: $source_checkout" >&2
  exit 2
}

checkout_root="$(CDPATH= cd -- "$(git -C "$source_checkout" rev-parse --show-toplevel)" && pwd -P)"
[ "$checkout_root" = "$source_checkout" ] || {
  echo "source checkout must name its Git top level: $source_checkout" >&2
  exit 2
}

actual_commit="$(git -C "$source_checkout" rev-parse --verify 'HEAD^{commit}')"
[ "$actual_commit" = "$expected_commit" ] || {
  echo "source commit mismatch: expected $expected_commit, got $actual_commit" >&2
  exit 2
}

[ -z "$(git -C "$source_checkout" status --porcelain=v1 --untracked-files=normal)" ] || {
  echo "source checkout is dirty: $source_checkout" >&2
  exit 2
}

build_script="$source_checkout/tools/engine_c_c6/build_arm.sh"
[ -f "$build_script" ] || {
  echo "missing authority build script: $build_script" >&2
  exit 2
}

# build_arm.sh derives the embedded commit from this verified checkout. The
# expected value is also exported for build logs and future compatible guards;
# it is never used as an unchecked replacement for the checkout's real HEAD.
export MEGAVGM_EXPECTED_SOURCE_COMMIT="$expected_commit"
exec "$build_script"
