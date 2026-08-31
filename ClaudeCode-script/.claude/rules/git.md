# Git & PR rules

- NEVER push directly to `main`. NEVER merge a PR — merging is a human decision. Open PRs as **ready for review** (NOT draft): external automated reviewers (Codex) skip drafts, and their findings are part of the convergence loop. The `claude-ready` label on the issue — not the PR's review state — is the signal that work is converged and awaiting the human.
- Branch naming: `claude/issue-<number>-<short-slug>`.
- One issue = one branch = one PR. Do not bundle unrelated changes.
- Stacked PRs are the default unless the issue contains the exact line
  `Stacking: disabled`. A stack must use a ready, green, review-triaged,
  conflict-free same-repository Claude PR as its base and identify it with
  `Stacked on #<parent-pr>` in the child PR body. Resolve the parent's feedback
  and conflicts before creating the child; never hide unresolved parent work
  inside a stack.
- Every PR description must contain:
  1. `Closes #<issue>` — the issue is the spec; link it.
  2. **What changed** — 3–6 bullets, plain language.
  3. **Evidence** — the actual commands run and their output (test results, build status). Paste output, don't assert success.
  4. **Not done on purpose** — anything in or near scope that was intentionally skipped, and why.
- A PR may be opened on a `checks.sh` exit 42 (this host cannot verify), but the **Evidence** section must then say plainly that the script verified nothing on this host and that CI is the verifier. Never present a 42 as passing checks.
- A banner-qualified exit 42 is not grounds to block a macOS issue merely
  because the development host is Linux. Continue to push and require the
  configured Xcode Cloud (or other platform CI) check on the current head.
- Circuit breaker: if the same CI check fails 3 consecutive times after your fixes, STOP. Comment your diagnosis and what you tried on the PR, and end the run. Do not keep pushing.
- Never force-push over commits you did not create in the current run.
