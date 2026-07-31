---
name: loop-init
description: Install or update the autonomous issue-to-PR loop scaffolding in the current repository. Use when the user says /loop-init, "set up the loop", "install the loop scaffold", "update the loop scaffold", or asks how to make Claude implement GitHub issues autonomously in this repo. Copies rules, skills, agents, hooks, and templates into .claude/, configures or explains project checks, creates GitHub labels, then walks the user through the account-level routine and environment setup.
disable-model-invocation: false
---

# Loop init / update

Install or refresh the loop scaffold, then guide the user through the account
and repository steps that cannot be automated. Keep updates idempotent.

## 1. Preflight without changing the repository

- Confirm the current directory is a Git repository root.
- Set `PAYLOAD="${CLAUDE_PLUGIN_ROOT}/payload"`.
- Copy the existing `.claude/settings.json`, or `{}` when absent, to a
  temporary file. Run
  `python3 "$PAYLOAD/scripts/merge-settings.py" <temporary> "$PAYLOAD/settings.json"`.
  Stop with the repository untouched if it fails. Retain the merged temporary
  file; do not activate the new hooks yet.
- Record whether `.claude/scripts/checks.sh` already exists. It is project
  configuration and must never be overwritten on update.

## 2. Copy the runtime files

- Create `.claude/` and copy `rules`, `skills`, `agents`, `templates`, and
  `fallback` from the payload.
- Copy every payload script except `checks.sh`. Copy `checks.sh` only when it
  did not already exist, and remember that it is newly created.
- Run `chmod +x .claude/scripts/*.sh`, verify each script is executable with
  `test -x`, and report the exact command and result. This happens before the
  new guard is activated; after installation, policy-file permission changes
  are intentionally human-only.
- Remove obsolete scaffold-owned
  `.claude/templates/claude-build-routine-prompt.md` and
  `.claude/templates/claude-converge-trigger.yml`. If
  `.github/workflows/claude-converge-trigger.yml` exists, explain that Routine
  B was removed and ask before deleting that user-controlled workflow. Never
  alter the account routine silently.

## 3. Configure and explain checks

Inspect the project before running checks. Always report the detected project
type, whether an edit is needed, and the exact commands that will run.

### SwiftPM without an Xcode project or workspace

No `checks.sh` edit is required. Its built-in detection uses:

```bash
BUILD=(swift build)
TEST=(swift test)
CLEANCMD=(swift package clean)
```

Report those commands and run `bash .claude/scripts/checks.sh --quick`.

### npm

Inspect `package.json` and list which of `build`, `test`, and `lint` exist. No
edit is required when at least one exists; `checks.sh` runs the corresponding
`npm run` commands and sets `CI=true` for `npm test`. If none exists, ask for
the project's real commands and show exactly how to put them into the
`BUILD`, `TEST`, and `LINT` arrays.

### Xcode project or workspace

Xcode takes precedence over a root `Package.swift`. Do not merely say that the
arrays "MUST be configured."

1. Prefer the intended `.xcworkspace` when the repository has one; otherwise
   use the intended `.xcodeproj`. If more than one plausible container exists,
   list them and ask the user which one drives CI.
2. Run the applicable list command and show the discovered schemes:

   ```bash
   xcodebuild -workspace "<workspace>.xcworkspace" -list -json
   xcodebuild -project "<project>.xcodeproj" -list -json
   ```

3. For the selected scheme, run the applicable `-showdestinations` command.
   Ask the user to choose when multiple platforms or destinations are
   plausible. Never invent an iOS simulator or assume macOS for an iOS app.
4. Produce a copyable replacement for the configuration line near the top of
   `.claude/scripts/checks.sh`, using the detected container, scheme, and
   selected destination. For example:

   ```bash
   BUILD=(xcodebuild -workspace "App.xcworkspace" -scheme "App" -destination "platform=macOS" build)
   TEST=(xcodebuild -workspace "App.xcworkspace" -scheme "App" -destination "platform=macOS" test)
   LINT=()
   CLEANCMD=(xcodebuild -workspace "App.xcworkspace" -scheme "App" clean)
   EXPECTED_CI_CHECKS=()
   ```

5. When `checks.sh` is newly created and the container, scheme, and destination
   are unambiguous, show the proposed lines and ask permission to write them
   before activating the new hooks. Otherwise leave the file unchanged and
   print the exact snippet with each unresolved choice called out.
6. Run `bash .claude/scripts/checks.sh --quick` only after configuration. A
   failure or unresolved choice leaves setup incomplete; say so plainly.

### Unknown project type

Ask for the real build, test, lint, and clean commands. Show their exact Bash
array form instead of giving a generic instruction to edit the file.

For every project type, explain that `EXPECTED_CI_CHECKS` may remain empty for
one provider during initial setup. Repositories requiring multiple CI providers
must add every exact context returned by `gh pr checks` and verify with:

```bash
bash .claude/scripts/checks.sh --list-ci-checks
```

## 4. Activate hooks and seed the toolchain

- Move the preflighted settings file into `.claude/settings.json`. It preserves
  unrelated settings and hooks and replaces only prior loop-owned commands.
- For a Swift repository without `.swift-version`, write `6.3.3` and tell the
  user to change it when the project uses another toolchain.

## 5. Configure GitHub without changing protection

- When `gh` is authenticated, inspect the labels `claude-build`,
  `claude-running`, `claude-ready`, and `claude-blocked`; create only missing
  labels. Distinguish inspection, authorization, and creation failures.
- Ask whether to copy `.claude/templates/ci-github-actions.yml` to
  `.github/workflows/ci.yml`, and do so only for repositories choosing GitHub
  Actions CI. Never overwrite an existing workflow. Its editable default is
  `swift:6.3`.
- Inspect branch or ruleset protection without mutating it. Remind the user to
  configure PR and passing-check merge gates manually when absent.

## 6. Hand policy files to the human

Show:

```bash
git status --short -- .claude .swift-version .github/workflows/ci.yml
git diff -- .claude .swift-version .github/workflows/ci.yml
```

Do not run `git add` or `git commit` for these scaffold paths. The installed
guard intentionally reserves policy-file staging for a human and would block
that command. After the user reviews the diff, print the exact terminal command
for the paths that actually exist, followed by the suggested message
`Claude loop scaffolding (plugin v<version>)`. Ask before any push.

## 7. Print the remaining setup

End with one self-contained walkthrough containing:

1. **Checks summary:** detected project type, exact active commands, whether
   `checks.sh --quick` passed, and any unresolved edit. State that executable
   bits were set with `chmod +x .claude/scripts/*.sh`; include that command for
   manual recovery.
2. **Implementation routine:** name `Implement claude-build issues`, repository,
   trigger **Issue: Labeled**, filter **Labels is one of `claude-build`**, and
   the complete compact `/goal` from `"$PAYLOAD"/ROUTINE_PROMPT.md` in one
   copyable block. Explain that the detailed procedure lives in the committed
   `.claude/skills/issue-to-pr/SKILL.md`, while the compact condition remains
   below Claude's 4,000-character goal limit. Tell the user to confirm the
   first transcript shows goal registration.
3. **Environment:** for Swift repositories, print the allowed domains
   `download.swift.org`, `archive.ubuntu.com`, and `security.ubuntu.com`, plus
   `.claude/templates/cloud-setup-swift.sh` in a copyable block.
4. **Review gate:** enable Codex code review and automatic reviews. The routine
   uses the 20-minute request and 60-minute human-intervention fallback.
5. **Optional overnight sweep:** explain parallel labeling, wait-until-merged
   `Depends-on: #N`, and merge-together `Stacks-on: #N`. The latter requires a
   converged same-repository Claude PR and uses the official `github/gh-stack`
   extension only to link numeric PRs; stack merge and cascading rebase remain
   human actions. Offer a second scheduled routine using the complete
   `"$PAYLOAD"/SWEEP_ROUTINE_PROMPT.md`, and explain that this updated prompt is
   required to auto-resume parked stack children and reconverge heads changed
   by GitHub's Rebase Stack action.
6. **Smoke test:** routine configuration lives in the Anthropic account. Paste
   updated prompts whenever `/loop-init` reports a change, then test one trivial
   labeled issue and read the full transcript.

## Update notes

When `.claude/rules` existed before the run, show `git diff --stat .claude` and
summarize changes. Explicitly report changes to `ROUTINE_PROMPT.md`,
`issue-to-pr/SKILL.md`, or `cloud-setup-swift.sh`, because account prompts or
environment setup may require manual updates.
