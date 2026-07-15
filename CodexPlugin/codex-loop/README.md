# codex-loop

Port of the claude-loop autonomous issue-to-PR workflow to OpenAI Codex.
Same architecture, translated to Codex's primitives: rules live in a
marker-managed AGENTS.md block; the reviewer/diagnostician/researcher
subagents became $code-review, $ci-diagnosis, and $prior-art skills
(SKILL.md is the shared open standard); the PreToolUse hooks port
unchanged (same JSON schema; note Codex's trust-review step); and the
trigger/converge/sweep orchestration is three GitHub Actions. Build and
convergence run through the documented
[`openai/codex-action@v1`](https://learn.chatgpt.com/docs/github-action); the
repository must provide an `OPENAI_API_KEY` Actions secret, and those runs use
API billing. The optional external-review fallback still uses the documented
[`@codex review`](https://learn.chatgpt.com/docs/third-party/github) PR comment.
The sweeper is pure bash — label mechanics need no model.

Install the plugin, run $loop-init in a repo, follow the printed steps.
Labels codex-* and branches codex/* — designed to coexist with
claude-loop in the same repository for side-by-side agent comparison.

VERIFY ON FIRST RUN: repo-skill discovery from `.agents/skills/`, hook firing
inside the action, the `OPENAI_API_KEY` secret, and the requested `codex/`
branch naming. Keep branch and ruleset protection as the final enforcement
layer; the local hooks are defense in depth.
