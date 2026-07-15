# LoopScaffold

LoopScaffold contains reviewable source and deterministic build artifacts for
autonomous issue-to-PR loops in Claude Code and Codex.

## Repository layout

- `ClaudeCode-script/` is the standalone Claude Code installer and runtime scaffold.
- `ClaudeCodePlugin/claude-loop/` is the Claude Code plugin source.
- `CodexPlugin/codex-loop/` is the Codex plugin source.
- The adjacent `.plugin` files are generated ZIP artifacts; do not edit them directly.

Both Claude distributions intentionally share the same `.claude` runtime files.
The test suite fails if those copies drift. Account-level routine prompt files
remain plugin-only for now; the standalone distribution presents its prompts in
its README.

## Validate and build

Run the complete local check before publishing an artifact:

```bash
scripts/test-scaffolds.sh
```

The command checks shell and JSON syntax, checks YAML syntax when PyYAML is
available, runs clean-room installer/merge tests, validates the Codex plugin
and skills when their validators are installed, validates the Claude plugin
when the Claude CLI is installed, rebuilds both archives deterministically,
and checks ZIP integrity.

To rebuild the archives without running the full suite:

```bash
scripts/build-plugins.sh
```

## Safety decisions

Installers merge only loop-owned hooks into existing settings and preserve
unrelated configuration. Invalid JSON stops the operation before the target is
changed. The scaffold never changes branch protection or repository rulesets;
it only asks the user to inspect and configure merge gates manually.
