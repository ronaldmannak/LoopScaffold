#!/usr/bin/env bash
# install.sh — install or update the Claude loop scaffold in a target repo.
#
# Usage:
#   ./install.sh /path/to/repo                 # fresh install or update
#   ./install.sh /path/to/repo --with-actions-ci   # also copy the CI template
#   ./install.sh /path/to/repo --protect-main      # also set branch protection (needs gh admin)
#
# Idempotent and update-safe: never overwrites an existing checks.sh
# (your per-repo BUILD/TEST config), always refreshes everything else.
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
TARGET="${1:?usage: install.sh /path/to/repo [--with-actions-ci] [--protect-main]}"
shift || true
WITH_CI=false; PROTECT=false
for a in "$@"; do
  case "$a" in
    --with-actions-ci) WITH_CI=true ;;
    --protect-main)    PROTECT=true ;;
    *) echo "unknown flag: $a" >&2; exit 1 ;;
  esac
done

[[ -d "$TARGET/.git" ]] || { echo "ERROR: $TARGET is not a git repo" >&2; exit 1; }
cd "$TARGET"

echo "==> Installing scaffold files"
mkdir -p .claude
# Everything except checks.sh is safe to refresh in place (tar: portable on macOS + Linux)
(cd "$SRC/.claude" && tar cf - --exclude 'scripts/checks.sh' .) | (cd .claude && tar xf -)
if [[ ! -f .claude/scripts/checks.sh ]]; then
  cp "$SRC/.claude/scripts/checks.sh" .claude/scripts/checks.sh
  echo "    installed checks.sh — CONFIGURE its BUILD/TEST arrays if this is an Xcode project"
else
  echo "    kept existing checks.sh (per-repo config preserved)"
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
  for l in claude-build claude-running claude-ready claude-blocked; do
    gh label create "$l" 2>/dev/null && echo "    created $l" || echo "    $l exists"
  done
else
  echo "    gh not available/authed — create labels manually: claude-build claude-running claude-ready claude-blocked"
fi

if $PROTECT; then
  echo "==> Branch protection on main (PR required; add required checks in the UI once they've reported)"
  REPO_SLUG="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
  gh api -X PUT "repos/$REPO_SLUG/branches/main/protection" \
    -H "Accept: application/vnd.github+json" \
    --input - <<'JSON' >/dev/null && echo "    protection set" || echo "    FAILED (needs admin) — set manually in Settings → Branches"
{"required_status_checks":null,"enforce_admins":false,"required_pull_request_reviews":{"required_approving_review_count":0},"restrictions":null,"allow_force_pushes":false,"allow_deletions":false}
JSON
fi

echo "==> Sanity check"
if .claude/scripts/checks.sh --quick >/dev/null 2>&1; then
  echo "    checks.sh --quick: PASS"
else
  echo "    checks.sh --quick: FAILED or unconfigured — fix before relying on the loop"
fi

cat << 'EOD'

==> Done. Remaining MANUAL steps (cannot be scripted):
  1. git add .claude .github 2>/dev/null; git commit -m "Claude loop scaffold"; git push
  2. Routine (UI-only: config lives in your Anthropic account, no API):
     claude.ai/code/routines or Desktop → New → paste the routine prompt
     from README.md → trigger: Issue: Labeled, Labels is one of:
     claude-build → repo: this one.
     (Re-paste the prompt after every scaffold update!)
  3. CI choice (see README table):
     - Actions: done if you passed --with-actions-ci
     - Xcode Cloud: App Store Connect → workflow start condition =
       "Pull Request Changes" targeting main
  4. Branch protection: mark your CI check as REQUIRED (it appears in the
     dropdown only after reporting once — open one throwaway PR first).
  5. Swift repos: paste .claude/templates/cloud-setup-swift.sh into the
     routine environment's setup script (once). Toolchain version updates
     afterwards happen by editing .swift-version in the repo — NOT the
     pasted script. Verify on the first run that the transcript shows
     "Required Swift >= X (from ./.swift-version)".
  6. Smoke test: one trivial labeled issue, read the whole transcript.
EOD
