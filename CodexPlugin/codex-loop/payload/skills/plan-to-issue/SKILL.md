---
name: plan-to-issue
description: Convert the plan approved in this session into a self-contained GitHub issue that an unattended routine can implement. Use when the human approves a plan, says "make this an issue", "file it", or invokes /plan-to-issue. NEVER implement the plan in the current session.
---

# Plan → Issue

Turn the approved plan into ONE GitHub issue. Do not write implementation code in this session. The issue is the complete contract for an unattended run — the implementer will have NO access to this chat, so it must stand alone.

## Issue format

**Title:** imperative, ≤ 70 chars.

**Body:**

```
## Context
Why this change; links to related code/files/issues.

## Plan
The approved plan, step by step. Exact file paths where known.

## Acceptance criteria
- [ ] Deterministic, checkable criteria only (tests that must pass,
      observable behaviors, commands whose output must contain X)
- [ ] All checks in .codex/scripts/checks.sh pass

## Dependencies
If this plan requires another codex-build issue to merge first, add a line
"Depends-on: #<n>" to the body — the routine parks dependent issues until
the dependency merges, so you can safely file and label a whole batch at once.

## Out of scope
Explicit non-goals, so the implementer doesn't expand scope.

## Constraints
- Follow the AGENTS.md loop rules
- Open the PR ready for review; never merge
```

## Policy-change plans are NOT routine-buildable

If the approved plan requires changes under `.codex/`, `.agents/skills/`, `AGENTS.md`, or `.github/workflows/` (rules, hooks, checks.sh, skills, CI definitions), do NOT apply the `codex-build` label — the implementation routine is deterministically blocked from editing those paths. Create the issue WITHOUT the label, note "requires human-supervised implementation" in the body, and tell the human to implement it in an interactive session where they approve each change.

## Procedure

1. Draft the issue body; show the human for a quick confirm.
2. `gh issue create --title "..." --body "..." --label codex-build`
3. Report the issue URL. The `codex-build` label fires the GitHub Action
   bridge that triggers the implementation routine — never apply it to an
   issue that isn't ready to build.
