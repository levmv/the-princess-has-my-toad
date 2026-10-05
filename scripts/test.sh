#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "$0")/env.sh"
cd "$PROJECT_ROOT"
mkdir -p build
TOAD_BUILD_FLAVOR=test
source scripts/source-id.sh
"$ODIN" test tests -out:build/game-tests -debug -vet -strict-style "-define:TOAD_BUILD_ID=\"$SOURCE_ID\"" "-extra-linker-flags:$LINK_FLAGS"
"$ODIN" check src/game -target:js_wasm32 -no-entry-point -vet -strict-style
"$ODIN" check src/music -target:js_wasm32 -no-entry-point -vet -strict-style
