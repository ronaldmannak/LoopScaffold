#!/usr/bin/env bash
# PreToolUse hook (Edit|Write|MultiEdit). Exit 2 = block; stderr goes to Codex.
set -u

if ! command -v python3 >/dev/null 2>&1; then
  echo "BLOCKED: policy hook requires python3 and cannot safely inspect this edit." >&2
  exit 2
fi

HOOK_INPUT="$(cat)"
HOOK_INPUT="$HOOK_INPUT" python3 <<'PY'
import json
import os
from pathlib import Path
import re
import sys

try:
    data = json.loads(os.environ["HOOK_INPUT"])
except (KeyError, json.JSONDecodeError) as error:
    sys.stderr.write(f"BLOCKED: invalid policy-hook input: {error}\n")
    sys.exit(2)

tool_input = data.get("tool_input", {}) or {}
workspace = Path(data.get("cwd") or os.getcwd())
policy_path = re.compile(
    r"(^|/)\.codex/|(^|/)\.agents/|(^|/)AGENTS\.md$|(^|/)\.github/workflows/"
)
test_path = re.compile(
    r"(^|/)(tests?|__tests__)(/|$)"
    r"|(^|/)(test_[^/]+|[^/]+_(test|tests))\.(py|go)$"
    r"|(^|/)[^/]+\.(test|spec)\.[jt]sx?$"
    r"|(^|/)(test[^/]*|[^/]+tests)\.swift$"
    r"|\.xctestplan$",
    re.IGNORECASE,
)
skip_pattern = re.compile(
    r"XCTSkip|\bxit\s*\(|\bxdescribe\s*\(|\.skip\s*\(|@Disabled|@Ignore\b|it\.todo|continue-on-error"
)
assert_pattern = re.compile(r"XCTAssert|#expect|XCTFail|\bexpect\s*\(|\bassert(?:\b|[A-Z_])")

def normalize(path: str) -> str:
    return path.replace("\\", "/")

def block_policy_file(path: str) -> None:
    if policy_path.search(normalize(path)):
        sys.stderr.write(
            f"BLOCKED: '{path}' is a policy/CI file. Changes here require a human.\n"
        )
        sys.exit(2)

def is_test_file(path: str) -> bool:
    return bool(test_path.search(normalize(path)))

def read_existing(path: str) -> str:
    candidate = Path(path)
    if not candidate.is_absolute():
        candidate = workspace / candidate
    if not candidate.exists():
        return ""
    try:
        return candidate.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as error:
        sys.stderr.write(f"BLOCKED: could not inspect existing test '{path}': {error}\n")
        sys.exit(2)

def check_test_change(paths: list[str], old: str, new: str) -> None:
    if not any(is_test_file(path) for path in paths):
        return
    if skip_pattern.search(new) and not skip_pattern.search(old):
        sys.stderr.write(
            "BLOCKED: this edit introduces a skip/disable marker into a test file.\n"
            "Fix the implementation; if the test is wrong, leave it for a human.\n"
        )
        sys.exit(2)
    if assert_pattern.search(old) and not assert_pattern.search(new):
        sys.stderr.write(
            "BLOCKED: this edit removes assertions from a test without replacing them.\n"
            "Weakening tests to get green is not allowed.\n"
        )
        sys.exit(2)

def inspect_apply_patch(command: str) -> None:
    sections = []
    current = None
    for line in command.splitlines():
        header = re.match(r"^\*\*\* (Add|Update|Delete) File: (.+)$", line)
        if header:
            path = header.group(2).strip()
            block_policy_file(path)
            current = {
                "kind": header.group(1),
                "path": path,
                "move_to": "",
                "old": [],
                "new": [],
            }
            sections.append(current)
            continue
        if line.startswith("*** Move to: ") and current is not None:
            move_to = line[len("*** Move to: "):].strip()
            block_policy_file(move_to)
            current["move_to"] = move_to
            continue
        if current is None:
            continue
        if line.startswith("+"):
            current["new"].append(line[1:])
        elif line.startswith("-"):
            current["old"].append(line[1:])

    if not sections:
        sys.stderr.write("BLOCKED: apply_patch input did not contain a recognizable file operation.\n")
        sys.exit(2)

    for section in sections:
        path = section["path"]
        move_to = section["move_to"]
        paths = [path] + ([move_to] if move_to else [])
        if section["kind"] == "Delete" and is_test_file(path):
            sys.stderr.write("BLOCKED: deleting test files is not allowed.\n")
            sys.exit(2)
        if move_to and is_test_file(path) and not is_test_file(move_to):
            sys.stderr.write("BLOCKED: moving a test outside the test tree is not allowed.\n")
            sys.exit(2)
        old = "\n".join(section["old"])
        new = "\n".join(section["new"])
        check_test_change(paths, old, new)

command = tool_input.get("command")
if data.get("tool_name") == "apply_patch" or command is not None:
    if not isinstance(command, str) or not command.strip():
        sys.stderr.write("BLOCKED: apply_patch hook input is missing tool_input.command.\n")
        sys.exit(2)
    inspect_apply_patch(command)
    sys.exit(0)

# Compatibility fallback for older Edit/Write-style hook payloads.
path = tool_input.get("file_path", "") or ""
if not path:
    sys.exit(0)
block_policy_file(path)
if not is_test_file(path):
    sys.exit(0)

edits = tool_input.get("edits") or [{
    "old_string": tool_input.get("old_str") or tool_input.get("old_string") or "",
    "new_string": tool_input.get("new_str") or tool_input.get("new_string") or tool_input.get("content", ""),
}]
if "content" in tool_input and edits[0].get("old_string", "") == "":
    edits[0]["old_string"] = read_existing(path)
for edit in edits:
    check_test_change(
        [path],
        edit.get("old_string", "") or "",
        edit.get("new_string", "") or "",
    )
sys.exit(0)
PY
status=$?
if [[ $status -ne 0 ]]; then
  if [[ $status -ne 2 ]]; then
    echo "BLOCKED: policy hook failed unexpectedly; refusing to fail open." >&2
  fi
  exit 2
fi
