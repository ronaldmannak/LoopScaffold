# Install the Claude Code plugin

Use this distribution for the normal Claude Code setup. You install the plugin
once, then run its initializer in every GitHub repository that should use the
issue-to-PR loop.

If your environment does not support plugins, use the
[standalone Claude Code script](../ClaudeCode-script/README.md) instead. Do not
use both Claude installation methods in the same target repository because they
manage the same `.claude/` files.

## Prerequisites

- Claude Code with plugin support
- Git and the GitHub CLI (`gh`)
- A target GitHub repository with a CI provider, or a plan to configure one

Authenticate `gh` before initialization if you want the plugin to create the
loop's labels:

```bash
gh auth status
```

## Install the plugin

Add this repository as a Claude Code marketplace, then install `claude-loop` at
user scope:

```bash
claude plugin marketplace add ronaldmannak/LoopScaffold --scope user
claude plugin install claude-loop@loop-scaffold --scope user
```

Confirm that Claude Code sees the plugin:

```bash
claude plugin list
```

Claude Code caches installed marketplace plugins. Start a new Claude Code
session after installation so it loads the plugin.

## Initialize a repository

Start Claude Code from the root of the target repository:

```bash
cd /path/to/your/repository
claude
```

Run the plugin's namespaced skill in that session:

```text
/claude-loop:loop-init
```

Review the files it proposes and follow the printed routine and
cloud-environment steps. The initializer detects Xcode, SwiftPM, and npm
projects. It either reports that `checks.sh` needs no edit or shows the exact
scheme/destination discovery commands and a copyable configuration; when a new
Xcode configuration is unambiguous, it asks before writing it. It also runs and
reports `chmod +x .claude/scripts/*.sh`. The initializer does not alter branch
protection or repository rulesets.

Installing the plugin and running the initializer do not create the routine in
your Anthropic account. `/claude-loop:loop-init` prints the compact `/goal`, the
**Issue: Labeled** trigger, and the environment setup for you to enter in the
Claude routine UI. The longer implementation procedure is installed in
`.claude/skills/issue-to-pr/SKILL.md` and is read by each cloud run.

## Update an existing repository

You normally update in place; do not remove `.claude/` first. Deleting it would
discard the project-specific checks and any unrelated Claude settings that the
initializer is designed to preserve.

1. Commit or stash unrelated repository changes so the scaffold diff is easy
   to review.
2. Update the installed plugin and restart Claude Code:

   ```bash
   claude plugin update claude-loop@loop-scaffold --scope user
   ```

3. Start a new Claude Code session at the repository root and run:

   ```text
   /claude-loop:loop-init
   ```

4. Review the reported changes and follow any routine, environment, checks, or
   migration instructions before committing them.

The initializer applies these preservation rules:

| Area | Update behavior |
| --- | --- |
| `.claude/scripts/checks.sh` | Preserved when it already exists. New defaults and interfaces are not forced into a project-specific script; compare with the current template and port changes deliberately. |
| `.claude/settings.json` | Merged. Current loop-owned hooks replace older loop-owned hooks; unrelated settings and hooks remain. Invalid JSON stops the update before repository files change. |
| Rules, skills, agents, templates, fallback files, and other scripts | Refreshed from the plugin. Local edits at managed paths may be overwritten; unrelated extra files are not a supported customization mechanism. |
| `.swift-version` | Created only when missing, then preserved on later runs. |
| `.github/workflows/ci.yml` | Never overwritten. The initializer asks before creating it when absent. |
| Labels | Only missing loop labels are created. Existing labels are left in place. |
| Branch protection and repository rulesets | Inspected only; never changed by the initializer. |

Older releases included Routine B. The initializer removes its obsolete
scaffold-owned templates, but it does not delete an existing
`.github/workflows/claude-converge-trigger.yml` or alter routines stored in your
Anthropic account without approval. Review the migration warning and remove or
update those manually.

Repository updates also cannot change the routine prompt or cloud environment
already stored in your Anthropic account. When `/loop-init` reports that
`ROUTINE_PROMPT.md` or `cloud-setup-swift.sh` changed, paste the new content in
the routine UI. Finish by reviewing:

```bash
git status --short -- .claude .swift-version .github/workflows/ci.yml
git diff -- .claude .swift-version .github/workflows/ci.yml
```

## Continue with the packaged guide

See the [plugin guide](claude-loop/README.md) for the installed components,
routine behavior, CI requirements, and first-run checks.
