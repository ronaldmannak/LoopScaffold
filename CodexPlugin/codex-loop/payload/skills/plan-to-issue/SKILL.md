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
Choose at most one immediate dependency directive:
- If this work must wait until another issue lands, is deployed, or is
  observed independently, add `Depends-on: #<n>`. The routine parks it until a
  merged PR closes that issue.
- If this work can safely build on another Codex PR and both may be merged
  together, add `Stacks-on: #<n>`. The routine starts after that issue has a
  converged `codex-ready` PR, branches from its head, and links the PRs into a
  native GitHub stack.

Never add both directives, more than one of either directive, or `Stacks-on:`
for cross-repository, cross-agent, deployment-ordered, or separately landed
work. Independent work needs no dependency directive.

## Out of scope
Explicit non-goals, so the implementer doesn't expand scope.

## Constraints
- Follow the AGENTS.md loop rules
- Open the PR ready for review; never merge
```

## Policy-change plans are NOT routine-buildable

If the approved plan requires changes under `.codex/`, `.agents/`, `AGENTS.md`, or `.github/workflows/` (rules, hooks, checks.sh, skills, CI definitions), do NOT apply the `codex-build` label — loop policy and hooks put those paths outside unattended scope. Create the issue WITHOUT the label, note "requires human-supervised implementation" in the body, and tell the human to implement it in an interactive session where they approve each change.

## Procedure

1. Draft the issue body; show the human for a quick confirm.
2. Choose exactly one creation path:
   - Routine-buildable plan: `gh issue create --title "..." --body "..." --label codex-build`
   - Policy-change plan: include "requires human-supervised implementation"
     in the body and run `gh issue create --title "..." --body "..."` with
     no build label.
3. Report the issue URL. Only the routine-buildable path applies
   `codex-build`, which fires the supported Codex build workflow — never apply it to an
   issue that isn't ready for unattended implementation.
