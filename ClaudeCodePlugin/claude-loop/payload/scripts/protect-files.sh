#!/usr/bin/env bash
# PreToolUse hook (Edit|Write|MultiEdit). Exit 2 = block; stderr goes to Claude.
#
# Policy:
#   HARD BLOCK: .claude policy files, CI workflow definitions.
#   TESTS: creating/editing tests is ALLOWED (testing.md requires new tests
#          for behavior changes). This is a TRIPWIRE, not proof of test
#          integrity: it blocks common obvious weakening patterns
#          (skip/disable markers, assertion removal in the edited region).
#          Semantic test-integrity review by the code-reviewer against the
#          issue's acceptance criteria remains MANDATORY.
#          False positives (e.g. moving an assertion into a helper) are
#          resolved by a human committing that change manually.
set -u
HOOK_INPUT="$(cat)" python3 << 'PY'
import json, os, re, sys

d = json.loads(os.environ["HOOK_INPUT"])
ti = d.get("tool_input", {}) or {}
path = ti.get("file_path", "") or ""
if not path:
    sys.exit(0)

if re.search(r'(^|/)\.claude/(settings\.json|rules/|scripts/)|(^|/)\.github/workflows/', path):
    sys.stderr.write(f"BLOCKED: '{path}' is a policy/CI file. Changes here require a human.\n")
    sys.exit(2)

if not re.search(r'(^|/)Tests?/|[^/]*Tests/|Tests?\.swift$|\.test\.[jt]sx?$|_test\.(py|go)$|\.xctestplan$', path):
    sys.exit(0)

edits = ti.get("edits") or [{
    "old_string": ti.get("old_str") or ti.get("old_string") or "",
    "new_string": ti.get("new_str") or ti.get("new_string") or ti.get("content", ""),
}]
SKIP   = re.compile(r'XCTSkip|\bxit\s*\(|\bxdescribe\s*\(|\.skip\s*\(|@Disabled|@Ignore\b|it\.todo|continue-on-error')
ASSERT = re.compile(r'XCTAssert|#expect|XCTFail|\bexpect\s*\(|\bassert')

for e in edits:
    old, new = e.get("old_string", ""), e.get("new_string", "")
    if SKIP.search(new) and not SKIP.search(old):
        sys.stderr.write("BLOCKED: this edit introduces a skip/disable marker into a test file.\n"
                         "Per .claude/rules/testing.md: fix the implementation; if the test is wrong, comment for a human.\n")
        sys.exit(2)
    if old and ASSERT.search(old) and not ASSERT.search(new):
        sys.stderr.write("BLOCKED: this edit removes assertions from a test without replacing them.\n"
                         "Weakening tests to get green is not allowed. Flag the test in a PR comment instead.\n")
        sys.exit(2)
sys.exit(0)
PY
