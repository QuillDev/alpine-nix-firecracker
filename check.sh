#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")"
shellcheck ./*.sh alpine/*.sh
python3 - <<'PY'
import ast
import json
from pathlib import Path
ast.parse(Path('guest-agent.py').read_text())
for path in ('devtools/flake.lock', 'examples/plan.json'):
    json.loads(Path(path).read_text())
PY
# Generated VM images and downloaded archives must never enter Git history.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  python3 - <<'PY'
from pathlib import Path
import subprocess
paths = subprocess.check_output(['git', 'ls-files', '-z']).decode().split('\0')
for name in filter(None, paths):
    path = Path(name)
    assert path.suffix not in {'.ext4', '.img', '.iso', '.qcow2', '.squashfs', '.tgz', '.zip', '.gz'}, name
    assert path.stat().st_size < 1024 * 1024, f'Unexpected large tracked file: {name}'
PY
fi
