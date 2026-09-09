#!/bin/sh
set -eu
# Same transactional install; pre-v2.1 files are backed up, never migrate JSON.
exec sh "$(dirname -- "$0")/install.sh" "$@"
