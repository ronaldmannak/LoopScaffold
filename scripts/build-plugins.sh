#!/usr/bin/env bash
# Build deterministic .plugin archives from the reviewable source trees.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

build_plugin() {
  local source="$1" output="$2"
  python3 - "$source" "$output" <<'PY'
from pathlib import Path
import os
import stat
import sys
import tempfile
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo

source = Path(sys.argv[1]).resolve()
output = Path(sys.argv[2]).resolve()
excluded_names = {".DS_Store", "__pycache__"}
files = sorted(
    path for path in source.rglob("*")
    if path.is_file()
    and not any(part in excluded_names for part in path.parts)
    and path.suffix != ".pyc"
)
output.parent.mkdir(parents=True, exist_ok=True)
fd, temporary = tempfile.mkstemp(prefix=f".{output.name}.", dir=output.parent)
os.close(fd)
try:
    with ZipFile(temporary, "w", compression=ZIP_DEFLATED, compresslevel=9) as archive:
        for path in files:
            relative = path.relative_to(source).as_posix()
            info = ZipInfo(relative, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = ZIP_DEFLATED
            info.create_system = 3
            mode = stat.S_IMODE(path.stat().st_mode)
            info.external_attr = (stat.S_IFREG | mode) << 16
            archive.writestr(info, path.read_bytes())
    os.replace(temporary, output)
finally:
    if os.path.exists(temporary):
        os.unlink(temporary)
PY
  echo "built ${output#$ROOT/}"
}

build_plugin "$ROOT/ClaudeCodePlugin/claude-loop" "$ROOT/ClaudeCodePlugin/claude-loop.plugin"
build_plugin "$ROOT/CodexPlugin/codex-loop" "$ROOT/CodexPlugin/codex-loop.plugin"
