#!/usr/bin/env bash
# Sourced by project scripts. Nothing is installed into the system.
PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$PROJECT_ROOT/.tools/bin:$PATH"
project_multiarch="$(cc -dumpmachine)"
if [[ -d "$PROJECT_ROOT/.tools/sysroot/usr/lib/$project_multiarch" ]]; then
    export LD_LIBRARY_PATH="$PROJECT_ROOT/.tools/sysroot/usr/lib/$project_multiarch${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
if [[ -x "$PROJECT_ROOT/.tools/odin/odin" ]]; then
    ODIN="$PROJECT_ROOT/.tools/odin/odin"
else
    ODIN="$(command -v odin || true)"
fi
if [[ -z "$ODIN" ]]; then
    echo 'Odin is missing. Run ./scripts/bootstrap.sh first.' >&2
    exit 1
fi
LINK_FLAGS="-L$PROJECT_ROOT/.tools/lib"
