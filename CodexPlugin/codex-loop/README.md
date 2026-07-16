# codex-loop

Port of the claude-loop autonomous issue-to-PR workflow to OpenAI Codex.
Same architecture, translated to Codex's primitives: rules live in a
marker-managed AGENTS.md block; the reviewer/diagnostician/researcher
subagents became $code-review, $ci-diagnosis, and $prior-art skills
(SKILL.md is the shared open standard); the PreToolUse hooks port
unchanged (same JSON schema; note Codex's trust-review step); and the
trigger/converge/sweep orchestration is three GitHub Actions. Build and
convergence delegate to repository-connected Codex cloud tasks through the
documented [`@codex` issue mention](https://learn.chatgpt.com/docs/changelog#codex-2025-10-22).
This scaffold does not require a repository API secret or invoke the separately
billed API action. The optional external-review fallback uses the documented
[`@codex review`](https://learn.chatgpt.com/docs/third-party/github) PR comment.
The sweeper is pure bash — label mechanics need no model. External CI wakes it
through GitHub's `check_run` or `status` events; a head-SHA/completion-time
marker makes each completed result dispatch exactly once, and the hourly run
remains a missed-event fallback.

The initial cloud task runs in BUILD MODE and exits after pushing its PR;
CI/review/comment wakes run separately in EVENT MODE and act once. Persistent
issue-label leases allow one event owner per issue while coalescing overlapping
wakes into a single follow-up, so independent cloud tasks cannot write the same
branch concurrently. Repositories with multiple CI providers list every exact
required context in `EXPECTED_CI_CHECKS` inside checks.sh.

Install the plugin, run $loop-init in a repo, follow the printed steps.
Labels codex-* and branches codex/* — designed to coexist with
claude-loop in the same repository for side-by-side agent comparison.

VERIFY ON FIRST RUN: the GitHub App reacts to the workflow's bot-authored
`@codex` issue comment, repo-skill discovery from `.agents/skills/`, hook firing
inside the cloud task, and the requested `codex/` branch naming. Keep branch and
ruleset protection as the final enforcement layer; the local hooks are defense
in depth.
