# LoopScaffold

LoopScaffold turns an approved GitHub issue into a reviewed pull request. It
ships the same issue-to-PR workflow for Claude Code and Codex, plus a standalone
Claude Code installer for environments where plugins are not an option.

## Choose a distribution

Start with the agent you want to run the loop:

| Your situation | Use | Why |
| --- | --- | --- |
| You use Claude Code | [Claude Code plugin](ClaudeCodePlugin/README.md) | Recommended Claude setup. Install it once, then run `/claude-loop:loop-init` in each repository. |
| You use Codex | [Codex plugin](CodexPlugin/README.md) | Recommended Codex setup. Install it once, then invoke `$codex-loop:loop-init` in each repository. No OpenAI API key is required. |
| You use Claude Code but cannot or do not want to install a plugin | [Standalone Claude Code script](ClaudeCode-script/README.md) | Runs directly from a checkout and installs the repository files with a shell script. Account-level routine setup remains manual. |

The Claude and Codex plugins can coexist in one repository. They use separate
labels (`claude-*` and `codex-*`), branch prefixes (`claude/` and `codex/`), and
runtime directories.

Do not install both Claude distributions in the same repository. The Claude
plugin and standalone script manage the same `.claude/` runtime files; choose
one installation method and use it for updates.

## Understand the two installation layers

Installing a plugin makes its `loop-init` skill available to your agent. Running
that skill in a project then installs the repository-specific rules, hooks,
scripts, labels, and workflow templates.

The standalone distribution skips the first layer: its `install.sh` writes the
Claude repository scaffold directly.

For either Claude distribution, repository installation does not create the
Anthropic account routine. The initializer or standalone installer prints the
compact `/goal`, trigger, and environment setup for you to enter in Claude's
routine UI. The committed `issue-to-pr` skill contains the longer procedure.

All three options preserve project-owned settings when they install their
hooks. They do not merge pull requests or change branch protection or repository
rulesets. Configure CI and merge gates for each target repository before relying
on an unattended loop.

## Repository layout

- `ClaudeCodePlugin/claude-loop/` is the reviewable Claude Code plugin source.
- `CodexPlugin/codex-loop/` is the reviewable Codex plugin source.
- `ClaudeCode-script/` is the standalone Claude Code installer and scaffold.
- The adjacent `.plugin` files are deterministic ZIP artifacts built from the
  plugin source trees. Do not edit them directly.

Both Claude distributions intentionally share the same `.claude` runtime files.
The test suite fails if those copies drift. Account-level routine prompt files
remain plugin-only; the standalone distribution presents the same compact
routine prompt in its README.

## Validate and build

Run the complete local check before publishing an artifact:

```bash
scripts/test-scaffolds.sh
```

The command checks shell and JSON syntax, clean-room installation and settings
merges, plugin manifests and skills when the corresponding validators are
available, archive integrity, and byte-for-byte agreement between each archive
and its source tree.

Rebuild the generated plugin archives with:

```bash
scripts/build-plugins.sh
```
