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
billed API action. The external-review gate uses the documented
[`@codex review`](https://learn.chatgpt.com/docs/third-party/github) PR comment.
The sweeper is pure bash — label mechanics need no model. External CI wakes it
through GitHub's `check_run` or `status` events; a head-SHA/completion-time
marker makes each completed result dispatch exactly once, and the scheduled run
remains a missed-event fallback. The same sweeper checks review state every
30 minutes: after 20 minutes without a result it wakes a one-time manual
review request, and 60 minutes without a Codex-bot 👍 or submitted review
blocks the issue for human intervention. A 👀 reaction means only that Codex
accepted the request; 👍 means it completed with no findings.

The initial cloud task runs in BUILD MODE and exits after pushing its PR;
CI/review/comment wakes run separately in EVENT MODE and act once. Persistent
issue-label leases allow one event owner per issue while coalescing overlapping
wakes into a single follow-up, so independent cloud tasks cannot write the same
branch concurrently. Repositories with multiple CI providers list every exact
required context in `EXPECTED_CI_CHECKS` inside checks.sh.

CI is a developer-configured precondition, not part of this scaffold. Confirm
that GitHub Actions or Xcode Cloud/external CI runs for pull requests and
reports the context the loop watches before labeling the first issue. The
initializer verifies or asks for that confirmation; it does not create or
overwrite the project's CI workflow.

## Optional stacked PRs

Add `Stacks-on: #N` as a full line in a Codex issue when it may safely build on
and merge with #N. The lower issue must have a `codex-ready` same-repository PR.
The task creates an ordinary child PR against that lower branch and links the
numeric PRs through GitHub's official `gh-stack` extension. Use `Depends-on:`
when the lower change must merge or deploy separately.

Stack merges and cascading rebases are human-only. If a lower layer changes,
use GitHub's **Rebase Stack** action; the resulting child-head update wakes
Codex to reconverge CI and reviews.

## Install

From a terminal, add the LoopScaffold marketplace and install the plugin:

```bash
codex plugin marketplace add ronaldmannak/LoopScaffold
codex plugin add codex-loop@loop-scaffold
```

Then start a new Codex session at the root of a target repository and invoke
**`$codex-loop:loop-init`**. Review its proposed changes and follow the printed
steps. Run the initializer again after plugin updates.

## Update an existing repository

Refresh the marketplace, reinstall the plugin, restart Codex, and rerun the
initializer:

```bash
codex plugin marketplace upgrade loop-scaffold
codex plugin add codex-loop@loop-scaffold
```

```text
$codex-loop:loop-init
```

Do not delete `.codex/`, `.agents/`, or the managed `AGENTS.md` block first.
The updater preserves `checks.sh`, merges hooks without removing unrelated
entries, replaces only the marker-managed `AGENTS.md` block, and keeps an
existing `.swift-version`. Loop-managed skills and other scripts are refreshed,
so local edits to those paths may be overwritten.

Existing `codex-*.yml` workflows are never overwritten because they contain
repository-specific CI names and task prompts. The initializer shows their
differences for you to merge manually. Run `/hooks` and re-trust the hook hash
after every scaffold update. Project CI, branch protection, and repository
rulesets remain developer-managed.

To use `Stacks-on:` in an updated repository, merge the initializer's changes
for all three Codex workflows: the build trigger accepts stack-ready and
head-update wakes, the converge trigger observes PR head synchronization, and
the sweeper unparks children whose lower PR becomes ready.

Labels codex-* and branches codex/* — designed to coexist with
claude-loop in the same repository for side-by-side agent comparison.

VERIFY ON FIRST RUN: the GitHub App reacts to the workflow's bot-authored
`@codex` issue comment, repo-skill discovery from `.agents/skills/`, hook firing
inside the cloud task, and the requested `codex/` branch naming. Keep branch and
ruleset protection as the final enforcement layer; the local hooks are defense
in depth.
