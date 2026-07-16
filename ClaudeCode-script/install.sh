#!/usr/bin/env bash
# install.sh — install or update the Claude loop scaffold in a target repo.
#
# Usage:
#   ./install.sh /path/to/repo                     # fresh install or update
#   ./install.sh /path/to/repo --with-actions-ci   # also copy the CI template
#
# Idempotent and update-safe: never overwrites an existing checks.sh
# (your per-repo BUILD/TEST config), merges settings.json without removing
# unrelated settings/hooks, and refreshes the remaining managed files.
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
TARGET="${1:?usage: install.sh /path/to/repo [--with-actions-ci]}"
shift || true
WITH_CI=false
for a in "$@"; do
  case "$a" in
    --with-actions-ci) WITH_CI=true ;;
    *) echo "unknown flag: $a" >&2; exit 1 ;;
  esac
done

[[ -d "$TARGET" ]] || { echo "ERROR: target directory does not exist: $TARGET" >&2; exit 1; }
TARGET="$(cd "$TARGET" && pwd -P)"
ROOT="$(git -C "$TARGET" rev-parse --show-toplevel 2>/dev/null || true)"
[[ -n "$ROOT" && "$ROOT" = "$TARGET" ]] || {
  echo "ERROR: target must be a git repo root: $TARGET" >&2
  exit 1
}
cd "$ROOT"

SETTINGS_TMP="$(mktemp "${TMPDIR:-/tmp}/claude-loop-settings.XXXXXX")"
trap 'rm -f "$SETTINGS_TMP"' EXIT
SETTINGS_WAS_PRESENT=false
if [[ -f .claude/settings.json ]]; then
  cp .claude/settings.json "$SETTINGS_TMP"
  SETTINGS_WAS_PRESENT=true
else
  printf '{}\n' > "$SETTINGS_TMP"
fi
# Preflight the complete merge before changing any repository file. Rewrite the
# private temporary path in diagnostics so the user sees the actual bad file.
if ! MERGE_ERROR=$(python3 "$SRC/.claude/scripts/merge-settings.py" \
  "$SETTINGS_TMP" "$SRC/.claude/settings.json" 2>&1); then
  echo "${MERGE_ERROR//$SETTINGS_TMP/.claude/settings.json}" >&2
  exit 1
fi

echo "==> Installing scaffold files"
mkdir -p .claude
# settings.json is merged separately; checks.sh holds per-repo configuration.
# tar keeps this copy step portable across macOS and Linux.
(cd "$SRC/.claude" && tar cf - --exclude '.DS_Store' --exclude 'scripts/checks.sh' --exclude 'settings.json' .) | (cd .claude && tar xf -)
cp "$SETTINGS_TMP" .claude/settings.json
$SETTINGS_WAS_PRESENT || chmod 644 .claude/settings.json
rm -f "$SETTINGS_TMP"
trap - EXIT
echo "    merged loop hooks into .claude/settings.json (unrelated settings preserved)"
if [[ ! -f .claude/scripts/checks.sh ]]; then
  cp "$SRC/.claude/scripts/checks.sh" .claude/scripts/checks.sh
  echo "    installed checks.sh — CONFIGURE its BUILD/TEST arrays if this is an Xcode project"
else
  echo "    kept existing checks.sh (per-repo config preserved)"
fi

# Routine B was removed. Delete only its scaffold-owned repo templates; a
# configured GitHub workflow and Anthropic routine require an explicit human
# migration and are never removed behind the user's back.
rm -f .claude/templates/claude-build-routine-prompt.md \
  .claude/templates/claude-converge-trigger.yml
if [[ -f .github/workflows/claude-converge-trigger.yml ]]; then
  echo "    MIGRATION: Routine B was removed; review and delete .github/workflows/claude-converge-trigger.yml, then restore Routine A from README.md" >&2
fi
chmod +x .claude/scripts/*.sh

# Seed .swift-version for Swift repos (read at RUN TIME by the cloud
# environment's setup script — bumping this file in a commit changes what
# the sandbox installs on the next run; the pasted setup script only holds
# the fallback and never needs re-pasting for version changes).
if [[ -f Package.swift ]] || compgen -G "*.xcodeproj" >/dev/null 2>&1; then
  if [[ ! -f .swift-version ]]; then
    echo "6.3.3" > .swift-version
    echo "    seeded .swift-version = 6.3.3 — edit if this repo needs a different toolchain"
  else
    echo "    .swift-version exists ($(cat .swift-version)) — kept"
  fi
fi

if $WITH_CI; then
  mkdir -p .github/workflows
  if [[ -f .github/workflows/ci.yml ]]; then
    echo "    .github/workflows/ci.yml exists — not touching it"
  else
    cp .claude/templates/ci-github-actions.yml .github/workflows/ci.yml
    echo "    installed .github/workflows/ci.yml — pick variant A or B inside it"
  fi
fi

echo "==> GitHub labels (idempotent)"
if command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then
  LABEL_ERRORS=false
  if ! LABEL_NAMES=$(gh label list --limit 1000 --json name --jq '.[].name'); then
    echo "    ERROR: could not inspect repository labels; no label changes attempted" >&2
    LABEL_ERRORS=true
  else
    for l in claude-build claude-running claude-ready claude-blocked; do
      if printf '%s\n' "$LABEL_NAMES" | grep -Fxq "$l"; then
        echo "    $l exists"
      elif gh label create "$l" >/dev/null 2>&1; then
        echo "    created $l"
      else
        echo "    ERROR: inspected labels but could not create missing label $l" >&2
        LABEL_ERRORS=true
      fi
    done
  fi
  $LABEL_ERRORS && echo "    label setup incomplete — fix the reported GitHub access/repository error before relying on the loop" >&2
else
  echo "    gh not available/authed — create labels manually: claude-build claude-running claude-ready claude-blocked"
fi

echo "==> Sanity check"
if .claude/scripts/checks.sh --quick >/dev/null 2>&1; then
  echo "    checks.sh --quick: PASS"
else
  echo "    checks.sh --quick: FAILED or unconfigured — fix before relying on the loop"
fi

cat << 'EOD'

==> Done. Remaining MANUAL steps (cannot be scripted):
  1. Review: git status --short -- .claude .swift-version .github/workflows/ci.yml
     Stage only the paths shown, then commit "Claude loop scaffold". Push after review.
  2. Routine (UI-only: config lives in your Anthropic account, no API):
     claude.ai/code/routines or Desktop → New → paste the routine prompt
     from README.md → trigger: Issue: Labeled, Labels is one of:
     claude-build → repo: this one.
     (Re-paste the prompt after every scaffold update!)
  3. CI choice (see README table):
     - Actions: done if you passed --with-actions-ci
     - Xcode Cloud: App Store Connect → workflow start condition =
       "Pull Request Changes" targeting main
     - Multiple CI providers: put every exact required context name in
       EXPECTED_CI_CHECKS inside .claude/scripts/checks.sh
  4. Inspect existing branch/ruleset protection without changing it. If this
     repo has no merge gate, configure one manually in GitHub. Required checks
     appear only after reporting once, so a throwaway PR may be needed.
  5. Swift repos: paste .claude/templates/cloud-setup-swift.sh into the
     routine environment's setup script (once). Toolchain version updates
     afterwards happen by editing .swift-version in the repo — NOT the
     pasted script. Verify on the first run that the transcript shows
     "Required Swift >= X (from ./.swift-version)".
  6. Smoke test: one trivial labeled issue, read the whole transcript.
EOD
