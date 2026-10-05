#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
if [[ "${1:-}" == --use-built && $# == 1 ]]; then
    source scripts/env.sh
    if [[ -f .tools/emsdk/emsdk_env.sh ]]; then
        set +u
        source .tools/emsdk/emsdk_env.sh >/dev/null 2>&1
        set -u
    fi
    TOAD_BUILD_FLAVOR=web-speed
    source scripts/source-id.sh
    if [[ ! -f build/web/build-id.txt ]] || [[ "$(cat build/web/build-id.txt)" != "$SOURCE_ID" ]]; then
        echo 'The existing web build does not match current sources/compiler. Run scripts/build-web.sh first.' >&2
        exit 1
    fi
elif [[ $# == 0 ]]; then
    ./scripts/build-web.sh
else
    echo 'Usage: scripts/package-web.sh [--use-built]' >&2
    exit 1
fi
python3 - <<'PY'
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
root = Path('build/web')
files = [root / name for name in (
    'index.html', 'app.js', 'style.css', 'logo.svg', 'game.js', 'game.wasm', 'odin.js',
    'build-id.txt', 'README.txt', 'LICENSE', 'THIRD_PARTY.md')]
files += sorted((root / 'licenses').glob('*.txt'))
with ZipFile('build/the-princess-has-my-toad-web.zip', 'w', ZIP_DEFLATED, compresslevel=9) as archive:
    for path in files:
        archive.write(path, path.relative_to(root))
PY
(cd build && sha256sum the-princess-has-my-toad-web.zip > the-princess-has-my-toad-web.zip.sha256)
echo 'build/the-princess-has-my-toad-web.zip'
