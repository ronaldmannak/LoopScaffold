# codex-loop

Port of the claude-loop autonomous issue-to-PR workflow to OpenAI Codex.
Same architecture, translated to Codex's primitives: rules live in a
marker-managed AGENTS.md block; the reviewer/diagnostician/researcher
subagents became $code-review, $ci-diagnosis, and $prior-art skills
(SKILL.md is the shared open standard); the PreToolUse hooks port
unchanged (same JSON schema; note Codex's trust-review step); and the
trigger/converge/sweep orchestration is three GitHub Actions, since
Codex's native trigger is the @codex mention rather than label-fired
routines. The sweeper is pure bash — label mechanics need no model.

Install the plugin, run $loop-init in a repo, follow the printed steps.
Labels codex-* and branches codex/* — designed to coexist with
claude-loop in the same repository for side-by-side agent comparison.

VERIFY ON FIRST RUN (platform behaviors that may differ from docs):
repo-skill discovery from .agents/skills/, hook firing in cloud tasks
(trust model), and the branch name Codex actually uses — if its cloud
tasks pick their own branch names, the trigger comment's naming
instruction is the control point; adjust filters if needed.
