# claude-loop

Autonomous issue-to-PR loop for Claude Code. Plan in chat → labeled GitHub
issue → cloud routine implements, converges CI + reviews → claude-ready →
human merges.

Install the plugin, then in each repo run **/loop-init**. It copies the
runtime scaffolding into the repo (the sandbox only guarantees
repo-committed content), seeds per-repo config, creates labels, and prints
the two things you must paste by hand: the routine config and the cloud
environment setup script (both live in your Anthropic account, no API).

Rerun /loop-init to update; it preserves your customized checks.sh and
tells you when the routine prompt changed and needs re-pasting.

For the optional slow-CI split, /loop-init prints a branch-only Routine A and
an event-driven Routine B; do not combine the default watch-mode Routine A with
Routine B. When multiple CI providers are required, configure every exact
context name in `EXPECTED_CI_CHECKS` inside checks.sh.

Design docs and version history: see the repo this plugin lives in.
