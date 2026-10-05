#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "$0")/env.sh"
cd "$PROJECT_ROOT"
mkdir -p build
source scripts/source-id.sh
"$ODIN" build bench/replay -out:build/replay-check -o:speed -vet -strict-style "-define:TOAD_BUILD_ID=\"$SOURCE_ID\"" "-extra-linker-flags:$LINK_FLAGS"
exec ./build/replay-check "$@"
