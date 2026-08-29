#!/usr/bin/env bash
# Single source of truth for "does this project pass".
# Skills, routines, and CI all call THIS script so verification can't drift.
#
# Usage: checks.sh [--quick] [--clean] [--list-ci-checks]
#   --quick = build, or first configured check when no build
#   --clean = tool-native clean first
#   --list-ci-checks = print configured required CI context names and exit
# Output: one summary line per step; full logs in .codex/.checks/.
# Exit: 0 = all configured checks passed, 1 = a check failed or the script is
#   misconfigured, 42 = this host cannot verify (see PLATFORM_CAN_VERIFY below).
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# ---------------------------------------------------------------
# PROJECT CHECKS
#
# No edit is needed for these auto-detected cases:
# - Package.swift without an Xcode container: swift build, swift test, and
#   swift package clean.
# - package.json: declared build, test, and lint scripts (at least one required).
#
# Xcode containers are not guessed because scheme and destination are
# project-specific. Discover them first:
#   xcodebuild -workspace "App.xcworkspace" -list -json
#   xcodebuild -workspace "App.xcworkspace" -scheme "App" -showdestinations
# Use -project "App.xcodeproj" instead when the repo does not use a workspace.
# Then replace the empty arrays below, for example:
#   BUILD=(xcodebuild -workspace "App.xcworkspace" -scheme "App" -destination "platform=macOS" build)
#   TEST=(xcodebuild -workspace "App.xcworkspace" -scheme "App" -destination "platform=macOS" test)
#   LINT=(swiftlint --strict)
#   CLEANCMD=(xcodebuild -workspace "App.xcworkspace" -scheme "App" clean)
#
# PLATFORM_CAN_VERIFY stays empty unless this project can only be built on
# specific hosts (SDK, toolchain, or architecture). When set, it is a command
# that exits non-zero on a host that cannot build the project at all; checks.sh
# then exits 42 (UNVERIFIED) instead of reporting a host limitation as a project
# failure. Keep it cheap and local, for example:
#   PLATFORM_CAN_VERIFY=(bash -c '[[ "$(uname -s)" == Darwin ]] && xcodebuild -version')
#
# EXPECTED_CI_CHECKS may stay empty with one CI provider. When multiple
# providers are required, add every exact name returned by `gh pr checks`:
#   EXPECTED_CI_CHECKS=("CI / verify" "Xcode Cloud")
# Verify the list with: bash .codex/scripts/checks.sh --list-ci-checks
# If execution is denied: chmod +x .codex/scripts/*.sh
# ---------------------------------------------------------------
BUILD=(); TEST=(); LINT=(); CLEANCMD=(); EXPECTED_CI_CHECKS=()
PLATFORM_CAN_VERIFY=()

QUICK=false; CLEAN=false; LIST_CI_CHECKS=false
for a in "$@"; do
  case "$a" in
    --quick) QUICK=true ;;
    --clean) CLEAN=true ;;
    --list-ci-checks) LIST_CI_CHECKS=true ;;
    *) echo "checks.sh: unknown option: $a" >&2; exit 2 ;;
  esac
done
if $LIST_CI_CHECKS; then
  if [[ ${#EXPECTED_CI_CHECKS[@]} -gt 0 ]]; then
    printf '%s\n' "${EXPECTED_CI_CHECKS[@]}"
  fi
  exit 0
fi
TIMEOUT_BIN="$(command -v timeout || command -v gtimeout || true)"
[[ -z "$TIMEOUT_BIN" ]] && echo "note: no timeout binary found — steps run without a time limit" >&2
PLATFORM_CHECK_TIMEOUT="${PLATFORM_CHECK_TIMEOUT:-60}"   # seconds for the platform gate

# Platform gate: "this host cannot verify" is not the same answer as "the project
# failed", and reporting it as a failure leaves a correct change with no way to
# reach a terminal state. Exit 42 means UNVERIFIED — nothing was built, tested,
# or linted. It is never a pass and never justifies merging; CI is the verifier.
if [[ ${#PLATFORM_CAN_VERIFY[@]} -gt 0 ]]; then
  if ! command -v "${PLATFORM_CAN_VERIFY[0]}" >/dev/null 2>&1; then
    echo "checks.sh: PLATFORM_CAN_VERIFY is configured but '${PLATFORM_CAN_VERIFY[0]}' is not executable." >&2
    exit 1
  fi
  platform_rc=0
  if [[ -n "$TIMEOUT_BIN" ]]; then
    "$TIMEOUT_BIN" "$PLATFORM_CHECK_TIMEOUT" "${PLATFORM_CAN_VERIFY[@]}" >/dev/null || platform_rc=$?
  else
    "${PLATFORM_CAN_VERIFY[@]}" >/dev/null || platform_rc=$?
  fi
  if [[ $platform_rc -eq 124 && -n "$TIMEOUT_BIN" ]]; then
    echo "checks.sh: PLATFORM_CAN_VERIFY timed out after ${PLATFORM_CHECK_TIMEOUT}s — fix the predicate; a hanging check is not a deferral." >&2
    exit 1
  fi
  if [[ $platform_rc -ne 0 ]]; then
    echo "VERIFICATION DEFERRED: this host cannot verify this project (PLATFORM_CAN_VERIFY exit $platform_rc)."
    echo "Nothing was built, tested, or linted. This is NOT a pass — CI is the verifier for this change."
    exit 42
  fi
fi

LOG_DIR=".codex/.checks"; mkdir -p "$LOG_DIR"
[[ -f "$LOG_DIR/.gitignore" ]] || echo "*" > "$LOG_DIR/.gitignore"   # never commit logs
STEP_TIMEOUT="${STEP_TIMEOUT:-1200}"   # seconds per step

if [[ ${#BUILD[@]} -eq 0 && ${#TEST[@]} -eq 0 && ${#LINT[@]} -eq 0 ]]; then
  if compgen -G "*.xcodeproj" >/dev/null || compgen -G "*.xcworkspace" >/dev/null; then
    echo "checks.sh: Xcode project detected — BUILD/TEST are intentionally not guessed." >&2
    echo "checks.sh: use xcodebuild -list -json and -showdestinations, then copy the arrays shown under PROJECT CHECKS at the top of this file." >&2
    exit 1
  elif [[ -f Package.swift ]]; then
    BUILD=(swift build); TEST=(swift test); CLEANCMD=(swift package clean)
  elif [[ -f package.json ]]; then
    if ! command -v node >/dev/null 2>&1; then
      echo "checks.sh: package.json detected but node is unavailable." >&2
      exit 1
    fi
    if ! node -e "const p=JSON.parse(require('fs').readFileSync('package.json','utf8')); if (p.scripts != null && (typeof p.scripts !== 'object' || Array.isArray(p.scripts))) process.exit(1)" >/dev/null 2>&1; then
      echo "checks.sh: package.json is invalid or its scripts value is not an object." >&2
      exit 1
    fi
    has_npm_script() {
      node -e "const p=JSON.parse(require('fs').readFileSync('package.json','utf8')); process.exit(Object.prototype.hasOwnProperty.call(p.scripts || {}, process.argv[1]) ? 0 : 1)" "$1"
    }
    if has_npm_script build; then
      BUILD=(npm run build)
    fi
    if has_npm_script test; then
      TEST=(env CI=true npm test)      # CI=true prevents watch mode
    fi
    if has_npm_script lint; then
      LINT=(npm run lint)
    fi
  else
    echo "checks.sh: unknown project type — configure BUILD/TEST arrays." >&2
    exit 1
  fi
fi

if [[ ${#BUILD[@]} -eq 0 && ${#TEST[@]} -eq 0 && ${#LINT[@]} -eq 0 ]]; then
  echo "checks.sh: no build, test, or lint command is configured." >&2
  exit 1
fi

SUMMARY=()
run() {
  local label="$1"; shift
  [[ $# -eq 0 ]] && { SUMMARY+=("$label: SKIPPED (not configured)"); return 0; }
  local log="$LOG_DIR/$label.log" start end
  start=$(date +%s)
  if [[ -n "$TIMEOUT_BIN" ]]; then
    "$TIMEOUT_BIN" "$STEP_TIMEOUT" "$@" >"$log" 2>&1
  else
    "$@" >"$log" 2>&1
  fi
  local rc=$? ; end=$(date +%s)
  if [[ $rc -eq 0 ]]; then
    SUMMARY+=("$label: PASS ($((end-start))s)")
  else
    [[ $rc -eq 124 ]] && echo "$label: TIMEOUT after ${STEP_TIMEOUT}s" || echo "$label: FAIL (exit $rc, $((end-start))s)"
    echo "--- last 40 lines of $log ---"
    tail -40 "$log"
    exit 1
  fi
}

if $CLEAN; then
  if [[ ${#CLEANCMD[@]} -eq 0 ]]; then run clean; else run clean "${CLEANCMD[@]}"; fi
fi
if [[ ${#BUILD[@]} -eq 0 ]]; then run build; else run build "${BUILD[@]}"; fi
if ! $QUICK; then
  if [[ ${#TEST[@]} -eq 0 ]]; then run test; else run test "${TEST[@]}"; fi
  if [[ ${#LINT[@]} -eq 0 ]]; then run lint; else run lint "${LINT[@]}"; fi
elif [[ ${#BUILD[@]} -eq 0 ]]; then
  if [[ ${#TEST[@]} -gt 0 ]]; then run test "${TEST[@]}"; else run lint "${LINT[@]}"; fi
fi
QUICK_DETAIL=""
if $QUICK; then
  if [[ ${#BUILD[@]} -gt 0 ]]; then QUICK_DETAIL=" (quick: build only)"; else QUICK_DETAIL=" (quick: first configured check)"; fi
fi
echo "VERIFICATION COMPLETE: all configured checks passed$QUICK_DETAIL"
printf '%s\n' "${SUMMARY[@]}"
echo "Full logs: $LOG_DIR/"
