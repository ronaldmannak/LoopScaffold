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
- Workflows → `.github/workflows/`: copy each codex-*.yml file only when its destination is absent. On update, never overwrite an existing workflow: show the diff against the payload template and ask the user to merge scaffold changes while preserving local configuration. In particular, preserve the configured CI workflow name in codex-converge-trigger.yml, any Xcode Cloud removal of its workflow_run trigger, and local customizations to the `@codex` task prompt in codex-build-trigger.yml.
- Stacked PRs are opt-in per issue with `Stacks-on: #N`. For an updated
  repository that will use them, explicitly require the user to merge the
  template changes for all three Codex workflows: stack-ready dispatch in the
  build trigger, `pull_request.synchronize` head-update wakes in the converge
  trigger, and stack-child unparking in the sweeper. The task installs the
  official `github/gh-stack` extension on demand and only links numeric PRs;
  stack merge and cascading rebase remain human actions.

## 4. Seeds & GitHub
- Swift repo without `.swift-version`: write `6.3.3`; Xcode projects must configure checks.sh BUILD/TEST arrays.
- CI is developer-provided; never install or overwrite a CI workflow. Before declaring setup complete, confirm one working PR check producer: either an existing GitHub Actions workflow that runs the repository's checks on `pull_request`, or an Xcode Cloud/external-CI workflow the developer confirms is enabled for PRs. Verify that the configured `workflow_run` name or external check context matches what the loop watches. If neither provider can be confirmed, say the loop is not enabled and stop before the smoke test; do not tell the user to apply `codex-build` to an issue.
- Detect support for CI context listing with `grep -q -- '--list-ci-checks)' .codex/scripts/checks.sh`. Older preserved scripts use the safe single-provider fallback. Repositories with more than one CI provider must port the current checks.sh interface, configure every exact required context name in `EXPECTED_CI_CHECKS`, and then verify with `bash .codex/scripts/checks.sh --list-ci-checks`.
- Run `bash .codex/scripts/checks.sh --quick`; report honestly.
- Labels: inspect each of the four state labels (`codex-build`, `codex-running`, `codex-ready`, `codex-blocked`) and the two event ownership labels (`codex-event-active`, `codex-event-pending`); create only missing labels. Report authorization/repository failures distinctly—never treat every failed create as proof that a label exists.

## 5. Commit
Show `git status --short -- AGENTS.md .agents .codex .github/workflows/codex-build-trigger.yml .github/workflows/codex-converge-trigger.yml .github/workflows/codex-sweep.yml .swift-version`. Stage only paths the user reviews, commit "Codex loop scaffolding (plugin v<version>)", and ask before pushing.

## 6. Manual steps — print VERBATIM as the final message
1. Set up Codex cloud for this repository and confirm its GitHub App connection. The build and convergence workflows use repository-connected `@codex` issue comments; no repository API secret is required.
2. Trust the hooks: run `/hooks` in Codex CLI in this repo once, review, and trust `.codex/hooks.json` entries (re-trust after any scaffold update — Codex pins trust to the hook hash).
3. CI is a developer-configured precondition; this scaffold does not create it. Confirm either GitHub Actions runs the repository's checks for PRs, or Xcode Cloud/external CI is enabled for PRs and reports the expected check context. Then inspect existing branch/ruleset protection without mutating it. If no merge gate exists, configure PR + passing-check requirements manually. When more than one CI provider is required, list every exact context name in `EXPECTED_CI_CHECKS` inside `.codex/scripts/checks.sh` so the converger waits for all providers to register. Do not continue to the smoke test until a CI producer is confirmed.
4. After CI is confirmed, smoke test: `gh issue create --label codex-build --title "..." --body "<plan-to-issue format>"` with something trivial, then watch `Codex build trigger` in GitHub Actions. Confirm the GitHub App reacts to the workflow's bot-authored `@codex` comment and starts a cloud task; in the cloud task, verify that hooks fired and checks.sh evidence was pasted. During convergence, verify that at most one issue carries `codex-event-active` and that the task removes it before exiting.
5. Enable Codex code review and automatic reviews for this repository. The external-review gate waits 20 minutes after each push before requesting `@codex review` once, accepts a Codex-bot 👍 as a no-findings pass, and escalates for human intervention if neither 👍 nor a submitted review arrives within 60 minutes of that request.
6. Coexistence note: this loop uses codex-* labels and codex/ branches; it can run beside the claude-loop plugin (claude-* labels, claude/ branches) in the same repo for A/B comparison — same issue format, same checks.sh oracle.
7. Optional stacked PRs: use a full-line `Stacks-on: #N` only when both issues
   use this Codex loop and may merge together. Use `Depends-on: #N` when the
   lower change must merge or deploy separately. Confirm updated projects
   merged all three workflow migrations before labeling a stack child.
