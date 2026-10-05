#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "$0")/env.sh"
cd "$PROJECT_ROOT"
mkdir -p build
output=build/render-checks
if [[ "${1:-}" == --headless && $# == 1 ]]; then
    source scripts/headless-link.sh
    output=build/render-checks-headless
elif [[ $# != 0 ]]; then
    echo 'Usage: scripts/test-render.sh [--headless]' >&2
    exit 1
fi
"$ODIN" build bench/render_checks "-out:$output" -debug -vet -strict-style "-extra-linker-flags:$LINK_FLAGS"
exec "$output"
