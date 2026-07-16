#!/usr/bin/env bash
# PreToolUse hook (Bash). Tripwire against dangerous git/gh/test operations.
set -u

if ! command -v python3 >/dev/null 2>&1; then
  echo "BLOCKED: Bash policy hook requires python3 and cannot safely inspect this command." >&2
  exit 2
fi

HOOK_INPUT="$(cat)"
HOOK_INPUT="$HOOK_INPUT" python3 <<'PY'
import json
import os
from pathlib import PurePosixPath
import re
import shlex
import subprocess
import sys

try:
    data = json.loads(os.environ["HOOK_INPUT"])
    command = (data.get("tool_input", {}) or {}).get("command", "") or ""
except (KeyError, json.JSONDecodeError) as error:
    sys.stderr.write(f"BLOCKED: invalid Bash-hook input: {error}\n")
    sys.exit(2)

if not command:
    sys.exit(0)

try:
    lexer = shlex.shlex(command, posix=True, punctuation_chars="|&;<>")
    lexer.whitespace_split = True
    lexer.commenters = ""
    tokens = list(lexer)
except ValueError as error:
    sys.stderr.write(f"BLOCKED: cannot safely parse Bash command: {error}\n")
    sys.exit(2)

separators = {"|", "||", "&", "&&", ";"}

def command_end(start: int) -> int:
    index = start
    while index < len(tokens) and tokens[index] not in separators:
        index += 1
    return index

def executable(token: str) -> str:
    return PurePosixPath(token).name

def git_subcommand(start: int, end: int):
    takes_value = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--super-prefix", "--config-env"}
    index = start + 1
    while index < end:
        token = tokens[index]
        if token in takes_value:
            index += 2
        elif token.startswith(("--git-dir=", "--work-tree=", "--namespace=", "--super-prefix=", "--config-env=")):
            index += 1
        elif token.startswith("-"):
            index += 1
        else:
            return token, index
    return "", end

def protected_ref(argument: str) -> bool:
    ref = argument.lstrip("+")
    if ":" in ref:
        ref = ref.rsplit(":", 1)[1]
    if ref.startswith("refs/heads/"):
        ref = ref[len("refs/heads/"):]
    return ref in {"main", "master"}

def push_refspecs(arguments: list[str]) -> list[str]:
    takes_value = {"--receive-pack", "--exec", "-o", "--push-option"}
    repository_from_option = False
    positionals = []
    index = 0
    positional_only = False
    while index < len(arguments):
        token = arguments[index]
        if positional_only:
            positionals.append(token)
            index += 1
        elif token == "--":
            positional_only = True
            index += 1
        elif token == "--repo":
            repository_from_option = True
            index += 2
        elif token.startswith("--repo="):
            repository_from_option = True
            index += 1
        elif token in takes_value:
            index += 2
        elif token.startswith("-"):
            index += 1
        else:
            positionals.append(token)
            index += 1
    return positionals if repository_from_option else positionals[1:]

def git_output(prefix: list[str], *arguments: str) -> str:
    try:
        result = subprocess.run(
            [*prefix, *arguments],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            check=False,
        )
    except OSError:
        return ""
    return result.stdout.strip() if result.returncode == 0 else ""

def protected_tracking_ref(reference: str) -> bool:
    ref = reference.strip()
    if ref.startswith("refs/remotes/"):
        ref = ref[len("refs/remotes/"):]
        ref = ref.split("/", 1)[1] if "/" in ref else ref
    elif ref.startswith("refs/heads/"):
        ref = ref[len("refs/heads/"):]
    elif "/" in ref:
        ref = ref.split("/", 1)[1]
    return ref in {"main", "master"}

def implicit_push_targets_protected(prefix: list[str]) -> bool:
    branch = git_output(prefix, "symbolic-ref", "--quiet", "--short", "HEAD")
    if protected_ref(branch):
        return True
    return any(
        protected_tracking_ref(git_output(prefix, "rev-parse", "--abbrev-ref", "--symbolic-full-name", selector))
        for selector in ("@{push}", "@{upstream}")
    )

def test_path(argument: str) -> bool:
    if argument.startswith("-"):
        return False
    normalized = argument.replace("\\", "/").rstrip("/")
    parts = [part.lower().strip("*?[]") for part in PurePosixPath(normalized).parts]
    if any(part in {"test", "tests", "__tests__"} for part in parts):
        return True
    name = parts[-1] if parts else ""
    return (
        name.startswith("test_")
        or name.endswith(("_test.py", "_tests.py", "_test.go", "_tests.go"))
        or bool(re.search(r"\.(test|spec)\.[jt]sx?$", name, re.IGNORECASE))
        or (name.endswith(".swift") and (name.startswith("test") or name.endswith("tests.swift")))
    )

def positional_arguments(start: int, end: int, takes_value: set[str]) -> list[str]:
    values = []
    index = start
    while index < end:
        token = tokens[index]
        if token in takes_value:
            index += 2
        elif token.startswith("-"):
            index += 1
        else:
            values.append(token)
            index += 1
    return values

def block(label: str):
    sys.stderr.write(
        f"BLOCKED ({label}): {command.strip()[:200]}\n"
        "Repository loop policy reserves this operation for a human.\n"
    )
    sys.exit(2)

for index, token in enumerate(tokens):
    name = executable(token)
    end = command_end(index + 1)
    if name == "git":
        subcommand, sub_index = git_subcommand(index, end)
        arguments = tokens[sub_index + 1:end]
        if subcommand == "push":
            if any(arg in {"-f", "--force"} or arg.startswith("--force-with-lease") for arg in arguments):
                block("force push")
            if any(arg in {"--all", "--branches", "--mirror"} for arg in arguments):
                block("push to main")
            refspecs = push_refspecs(arguments)
            if any(protected_ref(arg) for arg in refspecs):
                block("push to main")
            needs_branch_context = (
                (not refspecs and "--tags" not in arguments)
                or any(arg.lstrip("+") in {"HEAD", "@"} for arg in refspecs)
            )
            if needs_branch_context and implicit_push_targets_protected(tokens[index:sub_index]):
                block("push to main")
        elif subcommand == "reset" and "--hard" in arguments:
            block("hard reset")
        elif subcommand == "clean" and any(arg.startswith("-") and ("f" in arg or "d" in arg) for arg in arguments):
            block("git clean -f/-d")
        elif subcommand == "rm" and any(test_path(arg) for arg in arguments):
            block("deleting test files")
    elif name == "gh":
        words = positional_arguments(
            index + 1,
            end,
            {"-R", "--repo", "--hostname", "--config", "--jq", "--template"},
        )
        if len(words) >= 2 and words[0:2] == ["pr", "merge"]:
            block("PR merge (human-only)")
    elif name == "rm" and any(test_path(arg) for arg in tokens[index + 1:end]):
        block("deleting test files")

sys.exit(0)
PY
status=$?
if [[ $status -ne 0 ]]; then
  if [[ $status -ne 2 ]]; then
    echo "BLOCKED: Bash policy hook failed unexpectedly; refusing to fail open." >&2
  fi
  exit 2
fi
