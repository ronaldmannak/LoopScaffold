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
  echo "    installed checks.sh"
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
echo "    set executable bits: chmod +x .claude/scripts/*.sh"

echo "==> checks.sh configuration"
shopt -s nullglob
WORKSPACES=(*.xcworkspace)
PROJECTS=(*.xcodeproj)
shopt -u nullglob
if [[ ${#WORKSPACES[@]} -gt 0 || ${#PROJECTS[@]} -gt 0 ]]; then
  echo "    detected Xcode containers (Xcode takes precedence over Package.swift)"
  if [[ ${#WORKSPACES[@]} -gt 0 ]]; then
    for workspace in "${WORKSPACES[@]}"; do
      echo "      workspace: $workspace"
    done
  fi
  if [[ ${#PROJECTS[@]} -gt 0 ]]; then
    for project in "${PROJECTS[@]}"; do
      echo "      project: $project"
    done
  fi

  if [[ ${#WORKSPACES[@]} -eq 1 ]]; then
    XCODE_FLAG="-workspace"
    XCODE_CONTAINER="${WORKSPACES[0]}"
  elif [[ ${#WORKSPACES[@]} -eq 0 && ${#PROJECTS[@]} -eq 1 ]]; then
    XCODE_FLAG="-project"
    XCODE_CONTAINER="${PROJECTS[0]}"
  else
    echo "    choose the workspace/project that CI builds before using the commands below"
    echo "    discover schemes with the valid command for each candidate:"
    if [[ ${#WORKSPACES[@]} -gt 0 ]]; then
      for workspace in "${WORKSPACES[@]}"; do
        echo "      xcodebuild -workspace \"$workspace\" -list -json"
      done
    fi
    if [[ ${#PROJECTS[@]} -gt 0 ]]; then
      for project in "${PROJECTS[@]}"; do
        echo "      xcodebuild -project \"$project\" -list -json"
      done
    fi
    echo "    after choosing one container and a shared scheme, use the matching command:"
    echo "      xcodebuild -workspace \"<chosen>.xcworkspace\" -scheme \"<scheme>\" -showdestinations"
    echo "      xcodebuild -project \"<chosen>.xcodeproj\" -scheme \"<scheme>\" -showdestinations"
    echo "    then use either the workspace OR project form shown under PROJECT CHECKS in .claude/scripts/checks.sh"
    XCODE_FLAG=""
  fi

  if [[ -n "$XCODE_FLAG" ]]; then
    echo "    discover schemes:"
    echo "      xcodebuild $XCODE_FLAG \"$XCODE_CONTAINER\" -list -json"
    echo "    after choosing a shared scheme, discover valid destinations:"
    echo "      xcodebuild $XCODE_FLAG \"$XCODE_CONTAINER\" -scheme \"<scheme>\" -showdestinations"
    echo "    then replace the empty BUILD/TEST/LINT/CLEANCMD/EXPECTED_CI_CHECKS line near the top of .claude/scripts/checks.sh with:"
    echo "      BUILD=(xcodebuild $XCODE_FLAG \"$XCODE_CONTAINER\" -scheme \"<scheme>\" -destination \"<destination>\" build)"
    echo "      TEST=(xcodebuild $XCODE_FLAG \"$XCODE_CONTAINER\" -scheme \"<scheme>\" -destination \"<destination>\" test)"
    echo "      LINT=()"
    echo "      CLEANCMD=(xcodebuild $XCODE_FLAG \"$XCODE_CONTAINER\" -scheme \"<scheme>\" clean)"
    echo "      EXPECTED_CI_CHECKS=()"
    echo "    replace <scheme> and <destination> with values from those commands; do not guess a platform"
  fi
elif [[ -f Package.swift ]]; then
  echo "    detected SwiftPM without an Xcode container — no checks.sh edit is required"
  echo "      BUILD=(swift build)"
  echo "      TEST=(swift test)"
  echo "      CLEANCMD=(swift package clean)"
elif [[ -f package.json ]]; then
  echo "    detected package.json — checks.sh auto-runs declared build, test, and lint scripts"
  if command -v node >/dev/null 2>&1; then
    NPM_SCRIPTS=$(node -e 'const p=JSON.parse(require("fs").readFileSync("package.json", "utf8")); for (const n of ["build", "test", "lint"]) if (p.scripts && Object.prototype.hasOwnProperty.call(p.scripts, n)) console.log(n + ": " + p.scripts[n])' 2>/dev/null || true)
    if [[ -n "$NPM_SCRIPTS" ]]; then
      while IFS= read -r npm_script; do
        echo "      $npm_script"
      done <<< "$NPM_SCRIPTS"
      echo "    no checks.sh edit is required"
    else
      echo "    no build, test, or lint script was found; set at least one exact command, for example:"
      echo "      BUILD=(npm run <script>)"
      echo "      TEST=(env CI=true npm run <script>)"
      echo "      LINT=(npm run <script>)"
    fi
  else
    echo "    node is unavailable, so inspect package.json and verify at least one of build/test/lint exists"
  fi
else
  echo "    project type was not recognized; replace the empty array line with the real commands, for example:"
  echo "      BUILD=(<build-command> <arguments>)"
  echo "      TEST=(<test-command> <arguments>)"
  echo "      LINT=(<lint-command> <arguments>)"
  echo "      CLEANCMD=(<clean-command> <arguments>)"
  echo "      EXPECTED_CI_CHECKS=()"
fi
echo "    add every required CI context to EXPECTED_CI_CHECKS when more than one provider must report,"
echo "    or when this host cannot verify the project (checks.sh exit 42): a deferring project must"
echo "    name its platform check (e.g. Xcode Cloud) there — that check is the only verifier"
echo "    verify configured contexts: bash .claude/scripts/checks.sh --list-ci-checks"

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
    echo "    installed .github/workflows/ci.yml — pick a variant and edit swift:6.3 if the project uses another toolchain"
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
CHECKS_RC=0
# A preserved per-repo checks.sh may predate the exit-42 contract, so a bare 42 is
# not trusted as a deferral unless the script also prints the deferral banner.
CHECKS_OUT="$(.claude/scripts/checks.sh --quick 2>/dev/null)" || CHECKS_RC=$?
if [[ $CHECKS_RC -eq 0 ]]; then
  echo "    checks.sh --quick: PASS"
elif [[ $CHECKS_RC -eq 42 && "$CHECKS_OUT" == *"VERIFICATION DEFERRED"* ]]; then
  echo "    checks.sh --quick: DEFERRED — this host cannot verify this project"
  echo "    (PLATFORM_CAN_VERIFY reported the platform unusable). That is neither a"
  echo "    pass nor a failure: the scaffold is installed, and CI is the verifier."
else
  echo "    checks.sh --quick: FAILED or unconfigured"
  echo "    use the exact project-specific commands printed above, then rerun:"
  echo "      bash .claude/scripts/checks.sh --quick"
fi

cat << 'EOD'

==> Done. Remaining MANUAL steps (cannot be scripted):
  1. Checks: review the project-specific configuration printed above. The
     installer already ran `chmod +x .claude/scripts/*.sh`; rerun that exact
     command if executable bits are ever lost. Setup is incomplete until:
       bash .claude/scripts/checks.sh --quick
     passes, or defers with exit 42 on a host that cannot verify this project.
  2. Review: git status --short -- .claude .swift-version .github/workflows/ci.yml
     Stage only the paths shown, then commit "Claude loop scaffold". Push after review.
  3. Routine (UI-only: config lives in your Anthropic account, no API):
     claude.ai/code/routines or Desktop → New → paste the routine prompt
     from README.md → trigger: Issue: Labeled, Labels is one of:
     claude-build → repo: this one.
     The compact /goal stays below the 4,000-character limit; the full
     procedure lives in committed .claude/skills/issue-to-pr/SKILL.md.
     (Re-paste the prompt after every scaffold update!)
  4. CI choice (see README table):
     - Actions: done if you passed --with-actions-ci
     - Xcode Cloud: App Store Connect → workflow start condition =
       "Pull Request Changes" targeting main and claude/* (stacked child
       PRs target the parent's claude/ branch), and put the exact check
       name in EXPECTED_CI_CHECKS when this host cannot verify the
       project (checks.sh exit 42)
     - Multiple CI providers: put every exact required context name in
       EXPECTED_CI_CHECKS inside .claude/scripts/checks.sh
  5. Inspect existing branch/ruleset protection without changing it. If this
     repo has no merge gate, configure one manually in GitHub. Required checks
     appear only after reporting once, so a throwaway PR may be needed.
  6. Enable Codex code review and automatic reviews for this repository. The
     routine requests @codex review after 20 minutes and blocks for human
     intervention if neither a Codex-bot thumbs-up nor a submitted review
     arrives within 60 minutes of that request.
  7. Swift repos: paste .claude/templates/cloud-setup-swift.sh into the
     routine environment's setup script (once). Toolchain version updates
     afterwards happen by editing .swift-version in the repo — NOT the
     pasted script. Verify on the first run that the transcript shows
     "Required Swift >= X (from ./.swift-version)".
  8. Smoke test: one trivial labeled issue, read the whole transcript and
     confirm that the /goal condition registers successfully.
EOD
