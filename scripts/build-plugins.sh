#!/usr/bin/env bash
# Build or verify deterministic .plugin archives from the reviewable source trees.
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
            mode = 0o755 if stat.S_IMODE(path.stat().st_mode) & 0o111 else 0o644
            info.external_attr = (stat.S_IFREG | mode) << 16
            archive.writestr(info, path.read_bytes())
    os.replace(temporary, output)
finally:
    if os.path.exists(temporary):
        os.unlink(temporary)
PY
}

verify_plugin() {
  local source="$1" output="$2" temporary
  temporary="$(mktemp "${output}.check.XXXXXX")"
  if ! build_plugin "$source" "$temporary"; then
    rm -f "$temporary"
    return 1
  fi
  if ! cmp -s "$temporary" "$output"; then
    rm -f "$temporary"
    echo "stale ${output#$ROOT/}; run scripts/build-plugins.sh" >&2
    return 1
  fi
  rm -f "$temporary"
  echo "verified ${output#$ROOT/}"
}

case "${1:-}" in
  "")
    build_plugin "$ROOT/ClaudeCodePlugin/claude-loop" "$ROOT/ClaudeCodePlugin/claude-loop.plugin"
    echo "built ClaudeCodePlugin/claude-loop.plugin"
    build_plugin "$ROOT/CodexPlugin/codex-loop" "$ROOT/CodexPlugin/codex-loop.plugin"
    echo "built CodexPlugin/codex-loop.plugin"
    ;;
  --check)
    [[ $# -eq 1 ]] || { echo "usage: scripts/build-plugins.sh [--check]" >&2; exit 2; }
    verify_plugin "$ROOT/ClaudeCodePlugin/claude-loop" "$ROOT/ClaudeCodePlugin/claude-loop.plugin"
    verify_plugin "$ROOT/CodexPlugin/codex-loop" "$ROOT/CodexPlugin/codex-loop.plugin"
    ;;
  *)
    echo "usage: scripts/build-plugins.sh [--check]" >&2
    exit 2
    ;;
esac
