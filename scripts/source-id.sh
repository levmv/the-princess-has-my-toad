#!/usr/bin/env bash
# Sourced after env.sh. Include code, embedded resources and the compiler identity.
SOURCE_ID="$(python3 - "$ODIN" "${TOAD_BUILD_FLAVOR:-speed}" <<'PY'
from pathlib import Path
import hashlib, subprocess, sys
h = hashlib.sha256()
# Odin includes argv[0] in its version output. Moving an identical checkout
# must not change its source identity merely because .tools/ moved with it.
compiler_version = subprocess.check_output([sys.argv[1], 'version'])
h.update(compiler_version.removeprefix((sys.argv[1] + ' version ').encode()))
h.update(sys.argv[2].encode())
roots = ('src', 'assets', 'web') if sys.argv[2].startswith('web-') else ('src', 'assets')
if sys.argv[2].startswith('web-'):
    h.update(subprocess.check_output(['emcc', '--version']))
    for name in ('scripts/build-web.sh', 'scripts/bootstrap-web.sh'):
        h.update(Path(name).read_bytes())
for root in roots:
    for p in sorted(Path(root).rglob('*')):
        if p.is_file():
            h.update(str(p).encode()); h.update(b'\0'); h.update(p.read_bytes())
print(h.hexdigest())
PY
)"
