#!/usr/bin/env bash
# PreToolUse hook (Bash). Tripwire against dangerous git/gh operations.
# Exit 2 = block. Branch protection on GitHub remains the real enforcement;
# this catches mistakes locally and deterministically.
set -u
HOOK_INPUT="$(cat)" python3 << 'PY'
import json, os, re, sys
d = json.loads(os.environ["HOOK_INPUT"])
cmd = (d.get("tool_input", {}) or {}).get("command", "") or ""
if not cmd:
    sys.exit(0)

RULES = [
    (r'\bgit\s+push\b[^\n|;&]*\s(--force\b|-f\b|--force-with-lease\b)', "force push"),
    (r'\bgit\s+push\b[^\n|;&]*\s(origin\s+)?(main|master)\b',           "push to main"),
    (r'\bgit\s+push\b[^\n|;&]*HEAD:(main|master)\b',                    "push to main"),
    (r'\bgit\s+reset\s+--hard\b',                                       "hard reset"),
    (r'\bgit\s+clean\b[^\n|;&]*-\w*[fd]',                               "git clean -f/-d"),
    (r'\bgh\s+pr\s+merge\b',                                            "PR merge (human-only)"),
    (r'\brm\b[^\n|;&]*\bTests?/',                                       "deleting test files"),
    (r'\bgit\s+rm\b[^\n|;&]*\bTests?/',                                 "deleting test files"),
]
for pattern, label in RULES:
    if re.search(pattern, cmd):
        sys.stderr.write(f"BLOCKED ({label}): {cmd.strip()[:200]}\n"
                         "Per the AGENTS.md git rules this operation is reserved for humans.\n"
                         "If genuinely needed, escalate in a PR/issue comment instead.\n")
        sys.exit(2)
sys.exit(0)
PY
