#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "$0")/env.sh"
cd "$PROJECT_ROOT"
mkdir -p build
"$ODIN" build bench/persistence -out:build/persistence-test -debug -vet -strict-style "-extra-linker-flags:$LINK_FLAGS"
test_directory="$(mktemp -d -t the-princess-has-my-toad-persistence.XXXXXXXX)"
trap 'rm -rf -- "$test_directory"' EXIT
build/persistence-test write "$test_directory"
build/persistence-test read "$test_directory"
