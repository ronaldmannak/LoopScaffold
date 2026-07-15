---
name: loop-init
description: Install or update the autonomous issue-to-PR loop for Codex in the current repository. Use when the user says $loop-init, "set up the codex loop", or asks how to make Codex implement GitHub issues autonomously here. Copies skills, hooks, scripts, and GitHub Actions into the repo, merges loop rules into AGENTS.md, seeds config, creates labels, and prints the remaining manual steps.
---

# Codex loop init / update

Idempotent installer. Resolve this plugin root from the absolute path of this `SKILL.md`: the root is two directories above `skills/loop-init/`, and `PAYLOAD` is its `payload/` directory. Verify that `PAYLOAD/AGENTS_LOOP.md` exists before copying anything. Do not rely on Claude-specific or undocumented plugin-root environment variables.

## 1. Preconditions
Confirm cwd is a git repo root; stop otherwise.
Before changing repo files, copy the existing `.codex/hooks.json` (or `{}` when absent) to a temporary file and run `python3 "$PAYLOAD/scripts/merge-hooks.py" <temporary-file> "$PAYLOAD/hooks/hooks.json"`. Stop with the repo untouched if this fails, and retain the merged temporary file for step 3.

## 2. AGENTS.md (marker-managed block)
If AGENTS.md contains `<!-- codex-loop:start`, replace the complete marker-delimited block (including both old markers) with the complete content of `"$PAYLOAD"/AGENTS_LOOP.md`. Reject an unmatched or duplicated marker instead of guessing. Otherwise append the whole payload file to AGENTS.md (create it if absent).

## 3. Repo files
- Skills → `.agents/skills/`: copy each directory under `"$PAYLOAD"/skills/`.
- Scripts → `.codex/scripts/`: copy all EXCEPT checks.sh, which is copied only if absent (per-repo config; never overwrite). `chmod +x .codex/scripts/*.sh`
- Hooks → move the preflighted temporary file from step 1 to `.codex/hooks.json`. It contains the two current loop-owned `PreToolUse` hooks while preserving unrelated hook events/entries.
- Workflows → `.github/workflows/`: copy each codex-*.yml file only when its destination is absent. On update, never overwrite an existing workflow: show the diff against the payload template and ask the user to merge scaffold changes while preserving local configuration. In particular, preserve the configured CI workflow name in codex-converge-trigger.yml and any Xcode Cloud removal of its workflow_run trigger.

## 4. Seeds & GitHub
- Swift repo without `.swift-version`: write `6.3.3`; Xcode projects must configure checks.sh BUILD/TEST arrays.
- Run `bash .codex/scripts/checks.sh --quick`; report honestly.
- Labels: inspect each of `codex-build`, `codex-running`, `codex-ready`, and `codex-blocked`; create only missing labels. Report authorization/repository failures distinctly—never treat every failed create as proof that a label exists.
- Set repo variable `CODEX_RUNNER_LOGIN` to the exact GitHub login shown as the author of Codex-generated reviews/comments. Do not assume it is the user's login. If it is not yet known, leave review-event convergence disabled by the workflow's nonempty-variable guard, run the smoke test, inspect the author, then set it with `gh variable set CODEX_RUNNER_LOGIN --body "<observed-login>"`.

## 5. Commit
Show `git status --short -- AGENTS.md .agents .codex .github/workflows/codex-build-trigger.yml .github/workflows/codex-converge-trigger.yml .github/workflows/codex-sweep.yml .swift-version`. Stage only paths the user reviews, commit "Codex loop scaffolding (plugin v<version>)", and ask before pushing.

## 6. Manual steps — print VERBATIM as the final message
1. Install the Codex GitHub app / connect this repo to Codex cloud so @codex mentions start tasks.
2. Trust the hooks: run `/hooks` in Codex CLI in this repo once, review, and trust `.codex/hooks.json` entries (re-trust after any scaffold update — Codex pins trust to the hook hash).
3. Inspect existing branch/ruleset protection without mutating it. If no merge gate exists, configure PR + passing-check requirements manually.
4. Smoke test: `gh issue create --label codex-build --title "..." --body "<plan-to-issue format>"` with something trivial, then watch the task Codex starts from the trigger comment. Verify in the transcript that hooks fired and checks.sh evidence was pasted.
5. Coexistence note: this loop uses codex-* labels and codex/ branches; it can run beside the claude-loop plugin (claude-* labels, claude/ branches) in the same repo for A/B comparison — same issue format, same checks.sh oracle.
