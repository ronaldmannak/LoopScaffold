# Standalone Claude Code loop

Reusable scaffold: **plan in chat → issue as contract → one routine
implements, opens a PR, and converges it using blocking watches (token-free
waiting, instant wake on CI completion) → claude-ready → human merges.**

## Choose this distribution

Use this standalone script when you cannot or do not want to install the
[Claude Code plugin](../ClaudeCodePlugin/README.md). The script installs the
repository runtime directly from a LoopScaffold checkout. Routine configuration
still happens manually because Anthropic stores it in your account rather than
the repository.

Do not use the standalone script and Claude plugin in the same target
repository. They manage the same `.claude/` files; choose one method and use it
for subsequent updates.

## Install the scaffold

Prerequisites are Git, Bash, Python 3, and a target GitHub repository. Install
and authenticate the GitHub CLI if you want the script to create labels:

```bash
gh auth status
```

From a LoopScaffold checkout, run:

```bash
cd ClaudeCode-script
./install.sh /absolute/path/to/your/repository
```

For a repository that should use the included GitHub Actions CI template, add
`--with-actions-ci`:

```bash
./install.sh /absolute/path/to/your/repository --with-actions-ci
```

Do not use that flag when the project already has `.github/workflows/ci.yml` or
uses Xcode Cloud or another external CI provider. The installer never
overwrites an existing workflow.

The command merges the loop-owned Claude hooks into existing settings, copies
the managed `.claude/` files, preserves an existing customized
`.claude/scripts/checks.sh`, creates missing labels when `gh` is authenticated,
and prints the remaining manual steps. It detects Xcode, SwiftPM, and npm,
prints the exact checks that apply, reports the executable-bit command, and
shows a copyable Xcode configuration when scheme or destination choices remain.
Review its output and the resulting repository diff before committing.

Run the same command again to update the scaffold. The installer is idempotent
and continues to preserve the project-owned checks configuration.

## Finish setup

After installation, continue with [Setup per project](#setup-per-project). Edit
checks only when the installer's project-specific report says an edit is
needed, create the Claude routine, choose a CI provider, verify merge gates,
and smoke-test one trivial issue.

## Installed files

The current scaffold uses Claude Code's native **Issue: Labeled** trigger. One
routine owns implementation and convergence until the issue reaches
`claude-ready` or `claude-blocked`; the fallback GitHub Action remains inert
unless you choose to enable it.

```text
.claude/
├── settings.json                  # two loop-owned PreToolUse guards; merged on install
├── rules/
│   ├── simplicity.md              # concrete-by-default; abstractions need justification
│   ├── testing.md                 # tests welcome; weakening blocked; test diffs called out
│   └── git.md                     # ready-for-review PRs, never merge, circuit breaker
├── skills/
│   ├── issue-to-pr/SKILL.md       # full implementation routine procedure
│   ├── plan-to-issue/SKILL.md     # /plan-to-issue — plan → labeled issue (skills format)
│   ├── pr-iteration/SKILL.md      # PR loop, 8-iteration cap, 3-strikes breaker
│   └── verification/SKILL.md      # evidence-not-assertions, UI rule
├── agents/
│   ├── code-reviewer.md           # read-only, leashed; reads diff from a file
│   ├── ci-diagnostician.md        # digests failed CI runs into a 250-word verdict
│   └── prior-art-researcher.md    # read-only + web
├── templates/
│   └── ci-github-actions.yml      # inert CI template — copy in only if you choose Actions
├── scripts/
│   ├── checks.sh                  # build/test/lint, timeouts, summary + logs
│   ├── protect-files.sh           # tripwire: policy files + obvious test weakening
│   └── guard-bash.sh              # blocks force-push, push-to-main, merge, common test-deletion commands
└── fallback/
    └── claude-build-trigger.yml   # INERT Action bridge, only if native trigger breaks
```

## Setup per project

The installer handles the repository files and labels it can create safely.
Complete these project-specific steps after it finishes:

1. Review the installed `.claude/` files and `.swift-version`, if created, then
   commit the scaffold.
2. Follow the installer's `checks.sh configuration` report:
   - SwiftPM without an Xcode container needs no edit; it runs `swift build`
     and `swift test`.
   - npm needs no edit when `package.json` declares at least one of `build`,
     `test`, or `lint`.
   - Xcode projects must select their real workspace/project, shared scheme,
     and destination. The installer prints `xcodebuild -list -json`,
     `-showdestinations`, and the exact `BUILD`, `TEST`, and `CLEANCMD` lines to
     paste. Do not guess an iOS simulator or macOS destination.
   Then run:

   ```bash
   chmod +x .claude/scripts/*.sh
   bash .claude/scripts/checks.sh --quick
   ```

   Setup is incomplete until the quick check passes. The same instructions
   remain in the comment at the top of `checks.sh`.
3. Verify the state labels. If the installer reported that `gh` was unavailable,
   create them after authenticating:
   `for l in claude-build claude-running claude-ready claude-blocked; do gh label create $l; done`
   State machine: `claude-build` (approved, will trigger) → `claude-running` (claimed
   by a run) → `claude-ready` (PR open + CI green + reviews triaged, awaiting human) or
   `claude-blocked` (escalated, awaiting human). Humans resume a blocked issue by
   replying, then swapping `claude-blocked` → `claude-build` — the relabel itself
   fires the Issue: Labeled trigger, so resume is automatic.
4. Create the routine (web or Desktop — config is stored server-side in your
   Anthropic account, which is why it can't be scripted or committed):
   - Prompt: see below. Repo: this repo.
   - Environment — SwiftPM repos need a CUSTOM environment (the default image
     has no Swift and download.swift.org is egress-blocked): create/edit an
     environment with (a) Network access: Trusted + custom allowed domain
     `download.swift.org`, and (b) the setup script from
     .claude/templates/cloud-setup-swift.sh (toolchain install is cached
     across sessions; first run pays ~2-4 min). VERIFY on the first run that
     the custom environment actually applied (`swift --version` early in the
     transcript) — there are known bugs where custom env allowlists/setup are
     silently ignored; the routine escalates cleanly if so, and the no-local-
     build fallback (CI as sole oracle, checks.sh lint-only) always works.
   - Trigger: **GitHub event → Issue: Labeled**, Filter: **Labels is one of `claude-build`**.
     One trigger covers BOTH flows: GitHub fires a `labeled` event even for labels applied at issue
     creation, so plan-to-issue's born-labeled issues fire it, and so does
     labeling an older issue by hand — including swapping `claude-blocked` back
     to `claude-build` after answering an escalation, which makes resume
     automatic. Run now remains as a manual fallback (the prompt handles it).
   - The Claude GitHub App must be installed on the repo (the trigger setup prompts you).
5. CHOOSE YOUR CI — the loop needs at least one external check on PRs:
   | | GitHub Actions | Xcode Cloud | Both |
   |---|---|---|---|
   | Fits | SwiftPM / Linux-buildable repos | Xcode apps (signing, device tests) | Apple apps wanting fast lint + full fidelity |
   | Setup | copy .claude/templates/ci-github-actions.yml → .github/workflows/ci.yml, pick variant | workflow start condition = "Pull Request Changes" targeting main | both of the left |
   | Oracle parity | CI runs the SAME checks.sh the routine runs locally — zero drift | sandbox can't run xcodebuild: configure checks.sh for lint/partial, evidence cites the check | Actions job = checks.sh, Xcode Cloud = build oracle |
   | Gotchas | macOS runners are slow/expensive | check appears in branch-protection dropdown only after reporting once; logs live in App Store Connect (diagnostician falls back to annotations) | put both exact context names in `EXPECTED_CI_CHECKS` inside checks.sh so an early Actions check cannot hide the later Xcode Cloud check |
   Then protect `main` (require PR + the chosen check(s) passing).
   Note: routines can only push `claude/`-prefixed branches by default — leave that as is.
6. Enable Codex code review and automatic reviews for the repository. The
   external-review gate requests `@codex review` after 20 minutes and blocks
   for human intervention if neither 👍 nor a submitted review arrives within
   60 minutes of that request.
7. Verify empirically once: open a throwaway issue with the label and watch
   the run at claude.ai/code end-to-end.

## The kickoff prompt (interactive session)

```text
Plan, don't build: <one-paragraph feature description>.

Use plan mode. Before drafting, dispatch the prior-art-researcher agent
on <the core mechanism> and fold its findings in. The plan must respect
.claude/rules/simplicity.md — smallest design that satisfies the feature.

Show me the plan. After I approve it, use the plan-to-issue skill. Do not
implement anything in this session.
```

## The routine prompt (paste at claude.ai/code/routines)

The routine keeps `/goal` for both goal tracking and a transcript-verifiable
terminal condition. It stays below Claude's 4,000-character goal limit by
pointing at the detailed procedure installed in
`.claude/skills/issue-to-pr/SKILL.md`. Both files are required: the routine is
configured manually in your Anthropic account, while the skill is committed in
the repository for each cloud run to read.

```text
/goal Process the GitHub issue that triggered this routine by reading and following `.claude/skills/issue-to-pr/SKILL.md`. Keep working until the transcript proves exactly one terminal state for that issue. READY means: the issue has only the `claude-ready` loop-state label; a `claude/issue-<n>-*` branch and ready-for-review PR containing `Closes #<n>` implement the accepted plan; `.claude/scripts/checks.sh` evidence and an internal code-reviewer PASS are visible; every required CI check is green for the PR's current head SHA; every review comment is triaged; a submitted external review or Codex-bot 👍 completes the external-review gate; and a next-up suggestion was posted when the backlog was nonempty. BLOCKED means: the issue has only the `claude-blocked` loop-state label and one escalation comment records the diagnosis, attempts with commit references, best hypothesis, and specific questions. Hitting a cap, an ambiguous requirement, a policy-only change, an external-review timeout, or another unresolvable blocker must end BLOCKED and satisfies this goal. Never end with `claude-running`, exceed three internal review cycles, eight CI iterations, twenty commits, or one escalation comment. Never merge, push to the default branch, modify loop policy files, or delete, skip, or weaken tests. Before each turn ends, surface the issue number, state label, branch, PR, current head SHA, checks and review evidence, or blocking evidence so the evaluator can judge this condition.
```

## The human's two touchpoints

1. Approve the plan (kickoff session).
2. When the issue turns `claude-ready`: review the PR against the issue and merge.

## Notes & tuning

- **Why ready-for-review (not draft) PRs:** external reviewers like Codex
  skip drafts, and this workflow wants their findings INSIDE the
  convergence loop, so PRs open ready immediately. Consequences to accept:
  Codex may review red/mid-repair code (its early comments can be triaged
  as outdated), and nothing on the PR itself marks work-in-progress — the
  merge gate is the `claude-ready` label on the ISSUE plus branch
  protection plus the hook-blocked `gh pr merge`. Don't merge a PR whose
  issue isn't `claude-ready`.
- **Permissions vs sandbox:** independent layers. The broad allow
  (Bash/Edit/Write) lives in ~/.claude/settings.json INSIDE the VM, merged
  by the environment setup script — so unattended runs never stall on an
  approval prompt, while your LOCAL sessions keep prompting (the committed
  repo settings contain only the deny-hooks). Defense stays on the deny
  side: hooks, disposable sandbox, egress allowlist, branch protection.
  Additionally, rules/commands.md steers all sessions toward tool-native
  operations (swift package clean, checks.sh --clean) instead of
  prompt-triggering patterns like rm -rf — fewer flagged commands means
  less reliance on permission config in the first place.
- **Who can trigger a run:** applying labels on GitHub requires triage
  permission, so on a public repo random users CANNOT get issues built —
  the label filter doubles as the authorization boundary. The residual
  risk is a collaborator labeling a hostile issue; the prompt's trust-
  boundary clause plus hooks/branch protection bound the damage.
- **Interactive fast path** for small tasks: "Fix <thing>, follow the
  pr-iteration and verification skills, review with code-reviewer before
  opening the PR." Same guarantees, one session, no routine run consumed.
- **Run budget:** the single routine costs one run per issue and keeps PR
  ownership in one session instead of rehydrating context across events.
- **External CI (Xcode Cloud etc.):** no GitHub workflow needed — Xcode Cloud
  reports status checks to the PR that `gh pr checks --watch` and branch
  protection consume directly. Requirements: the Xcode Cloud workflow's start
  condition must be "Pull Request Changes" targeting your default branch (so
  claude/* PRs build), the check must be marked required in branch protection
  (it only appears in the dropdown after it has reported at least once), and
  checks.sh should be configured for what the Linux sandbox CAN run (lint /
  swift build), with the verification skill stating that build+test evidence
  comes from the CI check. The zero-checks registration window is handled by
  the pr-iteration skill: no checks ≠ green, ever.
- **Why blocking beats both sleeps and event fan-out:** a blocked
  `gh pr checks --watch` generates no tokens, wakes instantly on
  completion, and keeps all context in one session (no rehydration or
  concurrent-owner race).
- **Deletion of test files:** the Bash hook blocks common `rm` and `git rm`
  forms, while branch protection, CI, and review remain the final enforcement
  layer for variants a command tripwire cannot prove safe.
- Run status green means the session ran, not that the task succeeded —
  read the transcript or trust only the PR + CI state.
- Routines act under **your GitHub identity**; runs count against your
  daily routine cap; one issue = one run keeps budgeting simple.
