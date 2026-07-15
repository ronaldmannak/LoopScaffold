#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

while IFS= read -r script; do bash -n "$script"; done < <(find . -type f -name '*.sh' ! -path './.git/*' | sort)
while IFS= read -r json; do python3 -m json.tool "$json" >/dev/null; done < <(find . -type f -name '*.json' ! -path './.git/*' | sort)
HAVE_PYYAML=false
if python3 -c 'import yaml' >/dev/null 2>&1; then
  HAVE_PYYAML=true
  python3 - <<'PY'
from pathlib import Path
import subprocess
import yaml

def validate_runs(node, path, trail=()):
    if isinstance(node, dict):
        for key, child in node.items():
            if key == "run" and isinstance(child, str):
                result = subprocess.run(
                    ["bash", "-n"], input=child, text=True, capture_output=True
                )
                if result.returncode:
                    location = ".".join((*trail, str(key)))
                    raise SystemExit(f"{path}:{location}: {result.stderr.strip()}")
            else:
                validate_runs(child, path, (*trail, str(key)))
    elif isinstance(node, list):
        for index, child in enumerate(node):
            validate_runs(child, path, (*trail, str(index)))

for pattern in ("*.yml", "*.yaml"):
    for path in Path(".").rglob(pattern):
        if ".git" not in path.parts:
            source = path.read_text(encoding="utf-8")
            yaml.compose(source)
            validate_runs(yaml.load(source, Loader=yaml.BaseLoader), path)
PY
else
  echo "note: PyYAML unavailable; skipped YAML syntax validation" >&2
fi

python3 -m unittest discover -s tests -v

diff -qr \
  --exclude .DS_Store \
  --exclude CONVERGE_ROUTINE_PROMPT.md \
  --exclude ROUTINE_PROMPT.md \
  --exclude SWEEP_ROUTINE_PROMPT.md \
  ClaudeCode-script/.claude ClaudeCodePlugin/claude-loop/payload

cmp ClaudeCode-script/.claude/scripts/guard-bash.sh \
  CodexPlugin/codex-loop/payload/scripts/guard-bash.sh
python3 - <<'PY'
from pathlib import Path
import re

claude_checks = Path("ClaudeCode-script/.claude/scripts/checks.sh").read_text(encoding="utf-8")
codex_checks = Path("CodexPlugin/codex-loop/payload/scripts/checks.sh").read_text(encoding="utf-8")
if claude_checks != codex_checks.replace(".codex", ".claude"):
    raise SystemExit("Claude and Codex checks.sh implementations drifted")

forbidden = re.compile(
    r"\.claude|claude-(?:build|running|ready|blocked)|claude/|"
    r"CLAUDE_PLUGIN_ROOT|PLUGIN_ROOT|\.codex/rules|disable-model-invocation"
)
root = Path("CodexPlugin/codex-loop/payload")
matches: list[str] = []
for path in sorted(candidate for candidate in root.rglob("*") if candidate.is_file()):
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except UnicodeDecodeError:
        continue
    for number, line in enumerate(lines, 1):
        if forbidden.search(line):
            matches.append(f"{path}:{number}:{line}")
if matches:
    print("\n".join(matches))
    raise SystemExit("Codex payload contains Claude-only or stale Codex references")
PY

CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
PLUGIN_VALIDATOR="$CODEX_HOME/skills/.system/plugin-creator/scripts/validate_plugin.py"
SKILL_VALIDATOR="$CODEX_HOME/skills/.system/skill-creator/scripts/quick_validate.py"
if [[ -f "$PLUGIN_VALIDATOR" && -f "$SKILL_VALIDATOR" && "$HAVE_PYYAML" == true ]]; then
  python3 "$PLUGIN_VALIDATOR" CodexPlugin/codex-loop
  while IFS= read -r skill; do
    python3 "$SKILL_VALIDATOR" "$(dirname "$skill")"
  done < <(find CodexPlugin/codex-loop -type f -name SKILL.md | sort)
elif [[ -f "$PLUGIN_VALIDATOR" && -f "$SKILL_VALIDATOR" ]]; then
  echo "note: Codex plugin/skill validators require PyYAML; skipped because it is unavailable" >&2
else
  echo "note: Codex plugin/skill validators unavailable under $CODEX_HOME" >&2
fi

if command -v claude >/dev/null 2>&1; then
  claude plugin validate ClaudeCodePlugin/claude-loop
else
  echo "note: claude CLI unavailable; skipped Claude plugin validator" >&2
fi

"$ROOT/scripts/build-plugins.sh" --check
unzip -t ClaudeCodePlugin/claude-loop.plugin >/dev/null
unzip -t CodexPlugin/codex-loop.plugin >/dev/null
echo "all scaffold checks passed"
