#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "$0")/env.sh"
cd "$PROJECT_ROOT"
mkdir -p build
"$ODIN" build bench -out:build/bench -o:speed -vet -strict-style "-extra-linker-flags:$LINK_FLAGS"
./build/bench
