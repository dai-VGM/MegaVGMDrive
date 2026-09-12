#!/bin/sh
set -eu
# Same transactional install; v2.1 files are backed up and legacy RBFs are preserved.
exec sh "$(dirname -- "$0")/install.sh" "$@"
