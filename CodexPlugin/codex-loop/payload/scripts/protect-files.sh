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
path = tool_input.get("file_path", "") or ""
if not path:
    sys.exit(0)

normalized_path = path.replace("\\", "/")
if re.search(r"(^|/)\.codex/|(^|/)\.agents/|(^|/)AGENTS\.md$|(^|/)\.github/workflows/", normalized_path):
    sys.stderr.write(
        f"BLOCKED: '{path}' is a policy/CI file. Changes here require a human.\n"
    )
    sys.exit(2)

test_path = re.compile(
    r"(^|/)(tests?|__tests__)(/|$)"
    r"|(^|/)(test_[^/]+|[^/]+_(test|tests))\.(py|go)$"
    r"|(^|/)[^/]+\.(test|spec)\.[jt]sx?$"
    r"|(^|/)(test[^/]*|[^/]+tests)\.swift$"
    r"|\.xctestplan$",
    re.IGNORECASE,
)
if not test_path.search(normalized_path):
    sys.exit(0)

edits = tool_input.get("edits") or [{
    "old_string": tool_input.get("old_str") or tool_input.get("old_string") or "",
    "new_string": tool_input.get("new_str") or tool_input.get("new_string") or tool_input.get("content", ""),
}]

if "content" in tool_input and edits[0].get("old_string", "") == "":
    candidate = Path(path)
    if not candidate.is_absolute():
        candidate = Path(os.getcwd()) / candidate
    if candidate.exists():
        edits[0]["old_string"] = candidate.read_text(encoding="utf-8")

skip_pattern = re.compile(
    r"XCTSkip|\bxit\s*\(|\bxdescribe\s*\(|\.skip\s*\(|@Disabled|@Ignore\b|it\.todo|continue-on-error"
)
assert_pattern = re.compile(r"XCTAssert|#expect|XCTFail|\bexpect\s*\(|\bassert\b")

for edit in edits:
    old = edit.get("old_string", "") or ""
    new = edit.get("new_string", "") or ""
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
sys.exit(0)
PY
status=$?
if [[ $status -ne 0 ]]; then
  if [[ $status -ne 2 ]]; then
    echo "BLOCKED: policy hook failed unexpectedly; refusing to fail open." >&2
  fi
  exit 2
fi
