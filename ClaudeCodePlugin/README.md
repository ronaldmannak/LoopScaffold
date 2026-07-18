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

Run `/claude-loop:loop-init` again after a plugin update. It refreshes managed
files while preserving the project's customized `.claude/scripts/checks.sh`.

## Continue with the packaged guide

See the [plugin guide](claude-loop/README.md) for the installed components,
routine behavior, CI requirements, and first-run checks.
