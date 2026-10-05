#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "$0")/env.sh"
cd "$PROJECT_ROOT"
mkdir -p build
flags=(-o:speed)
TOAD_BUILD_FLAVOR=speed
if [[ "${1:-}" == debug ]]; then flags=(-debug -o:minimal); TOAD_BUILD_FLAVOR=debug; fi
source scripts/source-id.sh
"$ODIN" build src -out:build/the-princess-has-my-toad.next "${flags[@]}" -vet -strict-style "-define:TOAD_BUILD_ID=\"$SOURCE_ID\"" "-extra-linker-flags:$LINK_FLAGS"
if [[ "${1:-}" != debug ]] && command -v strip >/dev/null; then
    strip --strip-unneeded build/the-princess-has-my-toad.next
fi
if [[ "$(build/the-princess-has-my-toad.next --version)" != *" / $SOURCE_ID" ]]; then
    echo 'Embedded build identity does not match the source fingerprint.' >&2
    exit 1
fi
mv -f build/the-princess-has-my-toad.next build/the-princess-has-my-toad
