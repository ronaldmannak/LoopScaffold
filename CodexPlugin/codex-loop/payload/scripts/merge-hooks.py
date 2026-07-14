#!/usr/bin/env python3
"""Merge loop-owned Codex hooks while preserving unrelated hook config."""

from __future__ import annotations

import json
import os
from pathlib import Path
import stat
import sys
import tempfile
from typing import Any


OWNED_COMMANDS = {
    "bash .codex/scripts/guard-bash.sh",
    "bash .codex/scripts/protect-files.sh",
}


def load_object(path: Path, *, missing_ok: bool = False) -> dict[str, Any]:
    if missing_ok and not path.exists():
        return {}
    try:
        value = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as error:
        raise SystemExit(f"merge-hooks: cannot read valid JSON from {path}: {error}")
    if not isinstance(value, dict):
        raise SystemExit(f"merge-hooks: expected a JSON object in {path}")
    return value


def merge(existing: dict[str, Any], template: dict[str, Any]) -> dict[str, Any]:
    hooks = existing.setdefault("hooks", {})
    if not isinstance(hooks, dict):
        raise SystemExit("merge-hooks: existing 'hooks' value must be an object")
    current = hooks.get("PreToolUse", [])
    if not isinstance(current, list):
        raise SystemExit("merge-hooks: existing 'hooks.PreToolUse' value must be an array")
    incoming = template.get("hooks")
    if not isinstance(incoming, dict) or not isinstance(incoming.get("PreToolUse"), list):
        raise SystemExit("merge-hooks: template must contain a hooks.PreToolUse array")

    preserved: list[Any] = []
    for entry in current:
        if not isinstance(entry, dict) or not isinstance(entry.get("hooks"), list):
            preserved.append(entry)
            continue
        remaining = [
            hook for hook in entry["hooks"]
            if not isinstance(hook, dict) or hook.get("command") not in OWNED_COMMANDS
        ]
        if remaining:
            copied = dict(entry)
            copied["hooks"] = remaining
            preserved.append(copied)
    hooks["PreToolUse"] = preserved + incoming["PreToolUse"]
    return existing


def atomic_write(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    mode = stat.S_IMODE(path.stat().st_mode) if path.exists() else 0o644
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump(value, stream, indent=2)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, mode)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("usage: merge-hooks.py TARGET TEMPLATE")
    target, template = map(Path, sys.argv[1:])
    atomic_write(target, merge(load_object(target, missing_ok=True), load_object(template)))


if __name__ == "__main__":
    main()
