# claude-loop

Autonomous issue-to-PR loop for Claude Code. Plan in chat → labeled GitHub
issue → cloud routine implements, converges CI + reviews → claude-ready →
human merges.

## Install

From a terminal, add the LoopScaffold marketplace and install the plugin:

```bash
claude plugin marketplace add ronaldmannak/LoopScaffold --scope user
claude plugin install claude-loop@loop-scaffold --scope user
```

Then start a new Claude Code session at the root of a target repository and run
**`/claude-loop:loop-init`**. It copies the
runtime scaffolding into the repo (the sandbox only guarantees
repo-committed content), seeds per-repo config, creates labels, and prints
the two things you must paste by hand: the routine config and the cloud
environment setup script (both live in your Anthropic account, no API).

Plugin installation alone does not install that account-level routine. The
initializer prints a compact `/goal` below the 4,000-character limit; the full
implementation procedure is committed separately as
`.claude/skills/issue-to-pr/SKILL.md` for the routine to read.

Rerun `/claude-loop:loop-init` to update; it preserves your customized
`checks.sh` and tells you when the routine prompt changed and needs re-pasting.
During setup it identifies Xcode, SwiftPM, or npm, prints the exact active
commands or a copyable Xcode configuration, runs the quick check when ready,
and reports `chmod +x .claude/scripts/*.sh`.

## Update an existing repository

Update the plugin, restart Claude Code, and rerun the initializer from the
repository root:

```bash
claude plugin update claude-loop@loop-scaffold --scope user
```

```text
/claude-loop:loop-init
```

Do not delete `.claude/` first. The updater preserves an existing
`.claude/scripts/checks.sh`, merges loop hooks into `.claude/settings.json`
without removing unrelated settings, and keeps an existing `.swift-version` or
CI workflow. It refreshes the loop-owned rules, skills, agents, templates, and
non-config scripts, so review local edits to those managed paths before
updating.

The updater cannot modify the routine prompt or cloud environment stored in
your Anthropic account. Re-paste either one when the initializer reports that
its source changed. It also leaves branch protection and repository rulesets
untouched. Older Routine B workflows require the explicit migration described
by the initializer; they are not silently deleted.

One routine owns implementation and PR convergence through its subscription or
blocking watch. When multiple CI providers are required, configure every exact
context name in `EXPECTED_CI_CHECKS` inside checks.sh.

Design docs and version history: see the repo this plugin lives in.
