#!/usr/bin/env bash
# Local optional browser toolchain. Does not modify shell startup or system packages.
set -euo pipefail
source "$(dirname -- "$0")/env.sh"
cd "$PROJECT_ROOT"
mkdir -p downloads .tools/emsdk .tools/raylib-web
if [[ ! -x .tools/emsdk/upstream/emscripten/emcc ]]; then
    curl -fLsS https://codeload.github.com/emscripten-core/emsdk/tar.gz/refs/tags/4.0.16 -o downloads/emsdk-4.0.16.tar.gz
    echo 'e4eda3ce4222eed778d24e3b8f4564a0b502d2de827d276cc85450918adf53c6  downloads/emsdk-4.0.16.tar.gz' | sha256sum -c -
    tar -xf downloads/emsdk-4.0.16.tar.gz -C .tools/emsdk --strip-components=1
    .tools/emsdk/emsdk install 4.0.16
    .tools/emsdk/emsdk activate 4.0.16
fi
set +u
source .tools/emsdk/emsdk_env.sh >/dev/null 2>&1
set -u
if [[ ! -f .tools/raylib-web/src/libraylib.web.a ]]; then
    curl -fLsS https://codeload.github.com/raysan5/raylib/tar.gz/refs/tags/6.0 -o downloads/raylib-6.0.tar.gz
    echo '2b3ee1e2120c7a0796b33062c7e9a694dd8a8caa56a96319ac8c8ecf54a90d0b  downloads/raylib-6.0.tar.gz' | sha256sum -c -
    tar -xf downloads/raylib-6.0.tar.gz -C .tools/raylib-web --strip-components=1
    make -C .tools/raylib-web/src PLATFORM=PLATFORM_WEB GRAPHICS=GRAPHICS_API_OPENGL_ES3 -j4
fi
emcc --version | head -1
printf 'Ready. Run ./scripts/build-web.sh\n'
