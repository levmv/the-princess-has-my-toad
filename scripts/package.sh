#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
if [[ "${1:-}" == --use-built && $# == 1 ]]; then
    source scripts/env.sh
    source scripts/source-id.sh
    if [[ ! -x build/the-princess-has-my-toad ]] || [[ "$(build/the-princess-has-my-toad --version)" != *" / $SOURCE_ID" ]]; then
        echo 'The existing release does not match current sources/compiler. Run scripts/build.sh first.' >&2
        exit 1
    fi
elif [[ $# == 0 ]]; then
    ./scripts/build.sh
else
    echo 'Usage: scripts/package.sh [--use-built]' >&2
    exit 1
fi
bundle="the-princess-has-my-toad-linux-$(uname -m)"
package_stage="$(mktemp -d build/package.XXXXXXXX)"
trap 'rm -rf -- "$package_stage"' EXIT
mkdir -p "$package_stage/$bundle/assets/fonts" "$package_stage/$bundle/licenses"
cp build/the-princess-has-my-toad README.md LICENSE THIRD_PARTY.md "$package_stage/$bundle/"
cp licenses/*.txt "$package_stage/$bundle/licenses/"
cp assets/fonts/LICENSE.txt "$package_stage/$bundle/assets/fonts/"
tar -czf "build/$bundle.tar.gz" -C "$package_stage" "$bundle"
(cd build && sha256sum "$bundle.tar.gz" > "$bundle.tar.gz.sha256")
echo "build/$bundle.tar.gz"
