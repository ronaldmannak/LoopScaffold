---
name: loop-init
description: Install or update the autonomous issue-to-PR loop scaffolding in the current repository. Use when the user says /loop-init, "set up the loop", "install the loop scaffold", "update the loop scaffold", or asks how to make Claude implement GitHub issues autonomously in this repo. Copies rules, skills, agents, hooks, and templates into .claude/, seeds per-repo config, creates GitHub labels, then walks the user through the two manual steps (routine + environment).
disable-model-invocation: false
---

# Loop init / update

Install (or refresh) the loop scaffolding from this plugin's payload into the current repo, then guide the user through the steps that cannot be automated. Idempotent: safe to rerun for updates.

## 1. Preconditions
- Confirm cwd is a git repo root. If not, stop and say so.
- `PAYLOAD="${CLAUDE_PLUGIN_ROOT}/payload"` — all copies come from there.

## 2. Copy runtime files (refresh on update)
- Before copying any repo files, copy the existing `.claude/settings.json` (or `{}` when absent) to a temporary file and run `python3 "$PAYLOAD/scripts/merge-settings.py" <temporary-file> "$PAYLOAD/settings.json"`. Only continue after this preflight succeeds. After copying the other runtime files, move the merged temporary file into `.claude/settings.json`. This preserves unrelated settings and hooks, replaces only prior loop-owned hook commands, and leaves the repo untouched if existing JSON is invalid. Never overwrite the whole settings file from the template.
- `mkdir -p .claude && cp -r "$PAYLOAD"/rules "$PAYLOAD"/skills "$PAYLOAD"/agents "$PAYLOAD"/templates "$PAYLOAD"/fallback .claude/`
- Scripts: copy `"$PAYLOAD"/scripts/*` EXCEPT checks.sh into `.claude/scripts/`. Copy checks.sh ONLY if `.claude/scripts/checks.sh` does not exist (it holds per-repo config; never overwrite). `chmod +x .claude/scripts/*.sh`

## 3. Seed per-repo config (create-only, never overwrite)
- Swift repo (Package.swift or *.xcodeproj present) and no `.swift-version`: write `6.3.3` to `.swift-version`, tell the user to adjust if needed.
- If checks.sh was just created and an .xcodeproj exists: tell the user they MUST configure the BUILD/TEST arrays before the loop is trustworthy.
- Run `bash .claude/scripts/checks.sh --quick` and report the result honestly (a failure here is a setup task for the user, not something to fix by editing their project).

## 4. GitHub side (needs gh auth; skip with a note if unavailable)
- Labels, idempotent: inspect each of `claude-build`, `claude-running`, `claude-ready`, and `claude-blocked`; create only missing labels. Report authorization/repository failures distinctly—never treat every failed create as proof that a label exists.
- Ask the user (do not assume) whether to copy `.claude/templates/ci-github-actions.yml` to `.github/workflows/ci.yml` — only for repos using GitHub Actions CI (Xcode Cloud repos skip it).
- For slow CI only, offer `.claude/templates/claude-converge-trigger.yml` as the optional split-loop bridge. Copy it to `.github/workflows/` only with confirmation, then require the user to configure the CI workflow name, Routine B API secrets, and `CLAUDE_RUNNER_LOGIN`. Configure Routine B with the full prompt from `"$PAYLOAD"/CONVERGE_ROUTINE_PROMPT.md`; do not summarize or reconstruct it. The default single-routine loop does not need this workflow.
- Inspect existing branch/ruleset protection without mutating it. If the repo has no merge gate, remind the user to configure PR + passing-check requirements manually; checks appear in the dropdown only after reporting once.

## 5. Commit
Show `git status --short -- .claude .swift-version .github/workflows/ci.yml .github/workflows/claude-converge-trigger.yml`. Stage only paths the user reviews, commit as "Claude loop scaffolding (plugin v<version from plugin.json>)", and ask before pushing.

## 6. The manual steps — print this walkthrough VERBATIM as the final message
Print the routine name (`Implement claude-build issues`), trigger (**Issue: Labeled**, filter **Labels is one of `claude-build`**), repo, and then the FULL routine prompt (it opens with a /goal line: if the platform supports goal evaluation in routines it enforces terminal states mechanically, and it reads as a plain goal statement if not — tell the user to check the first run's transcript for goal registration) from `"$PAYLOAD"/ROUTINE_PROMPT.md` in a single copyable code block. If the user accepted the optional split converger, also print the Routine B name (`Converge claude PRs`) and API-trigger configuration plus the FULL prompt from `"$PAYLOAD"/CONVERGE_ROUTINE_PROMPT.md` in its own copyable block. Then the environment instructions: custom allowed domains (`download.swift.org`, `archive.ubuntu.com`, `security.ubuntu.com` for Swift repos) and the setup script from `.claude/templates/cloud-setup-swift.sh` in a copyable block. Then print the OPTIONAL overnight batch section: labeling multiple issues runs them in parallel (one session/branch/PR each); use "Depends-on: #N" in an issue body to serialize dependent work; and for unattended nights, offer the queue-sweeper as a second routine — SCHEDULED trigger (e.g. hourly), prompt from `"$PAYLOAD"/SWEEP_ROUTINE_PROMPT.md` in a copyable block. (The implementer itself posts a next-up dispatch suggestion on each PR at claude-ready — no separate dispatcher routine; the sweeper handles dependency auto-resume within the hour.) Close with: "Routine config lives in your Anthropic account — re-paste prompts whenever /loop-init reports they changed. Smoke-test with one trivial labeled issue and read the whole transcript."

## Update mode notes
When `.claude/rules` already existed before this run, this is an update: after copying, `git diff --stat .claude` and summarize what changed; explicitly tell the user whether ROUTINE_PROMPT.md, CONVERGE_ROUTINE_PROMPT.md (when Routine B is configured), or cloud-setup-swift.sh changed, because prompt or setup changes require manual re-pasting.
