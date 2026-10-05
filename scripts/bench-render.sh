#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "$0")/env.sh"
cd "$PROJECT_ROOT"
mkdir -p build
output=build/bench-render
extra=()
if [[ "${1:-}" == --headless ]]; then
    shift
    source scripts/headless-link.sh
    output=build/bench-render-headless
    extra=(-define:TOAD_HEADLESS_TEST=true)
fi
"$ODIN" build bench/render "-out:$output" -o:speed -vet -strict-style "${extra[@]}" "-extra-linker-flags:$LINK_FLAGS"
exec "$output" "$@"
