#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
release=dev-2026-09
case "$(uname -m)" in
    x86_64) arch=amd64 ;;
    aarch64) arch=arm64 ;;
    *) echo 'Supported bootstrap hosts: Linux x86_64 or aarch64.' >&2; exit 1 ;;
esac
mkdir -p .tools/odin .tools/bin .tools/lib downloads build
if [[ ! -x .tools/odin/odin ]]; then
    archive="odin-linux-$arch-$release.tar.gz"
    curl -fL --retry 2 "https://github.com/odin-lang/Odin/releases/download/$release/$archive" -o "downloads/$archive"
    tar -xzf "downloads/$archive" --strip-components=1 -C .tools/odin
fi
if ! command -v clang >/dev/null && [[ ! -x .tools/bin/clang ]]; then
    if ! command -v apt-get >/dev/null; then
        echo 'Install Clang using your package manager, then rerun this script.' >&2
        exit 1
    fi
    # Debian's installed LLVM runtime is reused. These packages are only unpacked locally.
    (cd downloads && apt-get download clang-19 libclang-cpp19)
    mkdir -p .tools/sysroot
    for package in downloads/clang-19_*.deb downloads/libclang-cpp19_*.deb; do
        dpkg-deb -x "$package" .tools/sysroot
    done
    ln -sf ../sysroot/usr/bin/clang-19 .tools/bin/clang
fi
# Odin's bundled raylib links X11. Reuse its installed runtime if the dev symlink is absent.
python3 - <<'PY'
import pathlib, subprocess
cache = subprocess.check_output(['/sbin/ldconfig', '-p'], text=True)
for line in cache.splitlines():
    if 'libX11.so.6 ' in line:
        target = pathlib.Path('.tools/lib/libX11.so')
        if not target.exists():
            target.symlink_to(line.split('=>', 1)[1].strip())
        break
PY
source scripts/env.sh
"$ODIN" version
clang --version | head -1
echo 'Ready. Run ./run.sh'
