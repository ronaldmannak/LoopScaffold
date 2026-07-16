# Install the Codex plugin

Use this distribution when Codex should implement labeled GitHub issues and
converge their pull requests. You install the plugin once, then run its
initializer in every repository that should use the loop.

The plugin uses repository-connected `@codex` mentions. It does not require an
OpenAI API key or the separately billed API action.

## Prerequisites

- A current Codex CLI or the ChatGPT desktop app with Codex plugin support
- Git and the GitHub CLI (`gh`)
- A target GitHub repository connected to Codex
- GitHub Actions, Xcode Cloud, or another CI provider configured for pull
  requests

Authenticate `gh` before initialization if you want the plugin to create the
loop's labels:

```bash
gh auth status
```

## Install the plugin

Add this repository as a Codex marketplace, then install `codex-loop`:

```bash
codex plugin marketplace add ronaldmannak/LoopScaffold
codex plugin add codex-loop@loop-scaffold
```

Confirm that Codex sees the marketplace entry:

```bash
codex plugin list --marketplace loop-scaffold
```

Start a new Codex session after installation. If the ChatGPT desktop app was
already open, restart it so it reloads the local plugin catalog.

## Initialize a repository

Start Codex from the root of the target repository:

```bash
cd /path/to/your/repository
codex
```

Invoke the plugin's namespaced skill in that session:

```text
$codex-loop:loop-init
```

Review the files it proposes and follow the printed setup steps. In particular,
confirm that CI runs for pull requests and reports the exact checks the loop
watches. The initializer does not create project CI, alter branch protection,
or change repository rulesets.

Run `$codex-loop:loop-init` again after updating the plugin. It refreshes managed
files while preserving local workflow decisions and the project's customized
`.codex/scripts/checks.sh`.

## Continue with the packaged guide

See the [plugin guide](codex-loop/README.md) for the workflow architecture,
required first-run verification, CI behavior, and coexistence with Claude Code.
