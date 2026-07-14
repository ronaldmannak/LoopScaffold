#!/usr/bin/env bash
# Single source of truth for "does this project pass".
# Skills, routines, and CI all call THIS script so verification can't drift.
#
# Usage: checks.sh [--quick] [--clean]   (--quick = build only; --clean = tool-native clean first)
# Output: one summary line per step; full logs in .claude/.checks/.
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

QUICK=false; CLEAN=false
for a in "$@"; do
  case "$a" in --quick) QUICK=true ;; --clean) CLEAN=true ;; esac
done
LOG_DIR=".claude/.checks"; mkdir -p "$LOG_DIR"
[[ -f "$LOG_DIR/.gitignore" ]] || echo "*" > "$LOG_DIR/.gitignore"   # never commit logs
STEP_TIMEOUT="${STEP_TIMEOUT:-1200}"   # seconds per step

# ---------------------------------------------------------------
# CONFIGURE PER PROJECT (preferred over auto-detection). Examples:
#   BUILD=(xcodebuild -scheme Pico -destination 'platform=macOS' build)
#   TEST=(xcodebuild -scheme Pico -destination 'platform=macOS' test)
#   LINT=(swiftlint --strict)
# ---------------------------------------------------------------
BUILD=(); TEST=(); LINT=(); CLEANCMD=()

if [[ ${#BUILD[@]} -eq 0 ]]; then
  if [[ -f Package.swift ]]; then
    BUILD=(swift build); TEST=(swift test); CLEANCMD=(swift package clean)
  elif compgen -G "*.xcodeproj" >/dev/null || compgen -G "*.xcworkspace" >/dev/null; then
    echo "checks.sh: Xcode project detected — configure BUILD/TEST arrays in this script." >&2
    exit 1
  elif [[ -f package.json ]]; then
    BUILD=(npm run build --if-present)
    if python3 -c "import json,sys; sys.exit(0 if 'test' in json.load(open('package.json')).get('scripts',{}) else 1)" 2>/dev/null; then
      TEST=(env CI=true npm test)      # CI=true prevents watch mode
    fi
  else
    echo "checks.sh: unknown project type — configure BUILD/TEST arrays." >&2
    exit 1
  fi
fi

TIMEOUT_BIN="$(command -v timeout || command -v gtimeout || true)"
[[ -z "$TIMEOUT_BIN" ]] && echo "note: no timeout binary found — steps run without a time limit" >&2

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
  run clean "${CLEANCMD[@]}"
fi
run build "${BUILD[@]}"
if ! $QUICK; then
  run test "${TEST[@]}"
  run lint "${LINT[@]}"
fi
echo "VERIFICATION COMPLETE: all configured checks passed$($QUICK && echo ' (quick: build only)')"
printf '%s\n' "${SUMMARY[@]}"
echo "Full logs: $LOG_DIR/"
