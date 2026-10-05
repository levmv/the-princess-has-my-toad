#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "$0")/env.sh"
cd "$PROJECT_ROOT"
if [[ -f .tools/emsdk/emsdk_env.sh ]]; then
    set +u
    source .tools/emsdk/emsdk_env.sh >/dev/null 2>&1
    set -u
fi
if ! command -v emcc >/dev/null || [[ ! -f .tools/raylib-web/src/libraylib.web.a ]]; then
    echo 'Web tools are missing. Run ./scripts/bootstrap-web.sh first.' >&2
    exit 1
fi
mkdir -p build/web
TOAD_BUILD_FLAVOR=web-speed
source scripts/source-id.sh
"$ODIN" build src -target:js_wasm32 -build-mode:obj -o:speed -vet -strict-style \
    -define:RAYLIB_WASM_LIB=env.o "-define:TOAD_BUILD_ID=\"$SOURCE_ID\"" -out:build/web/game.o
emcc build/web/game.o .tools/raylib-web/src/libraylib.web.a -o build/web/game.js \
    -O1 -sUSE_GLFW=3 -sMIN_WEBGL_VERSION=2 -sMAX_WEBGL_VERSION=2 \
    -sALLOW_MEMORY_GROWTH=1 -sINITIAL_MEMORY=134217728 -sMAXIMUM_MEMORY=536870912 \
    -sSTACK_SIZE=16777216 -sWASM_BIGINT=1 -sASSERTIONS=1 \
    -sERROR_ON_UNDEFINED_SYMBOLS=0 --js-library web/library.js
cp "$(dirname "$ODIN")/core/sys/wasm/js/odin.js" build/web/odin.js
cp web/app.js web/style.css build/web/
cp assets/logo.svg build/web/
sed "s/__BUILD_ID__/$SOURCE_ID/g" web/index.html > build/web/index.html
cp web/README.txt build/web/README.txt
cp LICENSE THIRD_PARTY.md build/web/
mkdir -p build/web/licenses
cp licenses/*.txt build/web/licenses/
cp assets/fonts/LICENSE.txt build/web/licenses/fonts.txt
printf '%s\n' "$SOURCE_ID" > build/web/build-id.txt
rm build/web/game.o
printf 'Web build: %s/build/web\nRun: python3 -m http.server 18765 --directory build/web\n' "$PROJECT_ROOT"
