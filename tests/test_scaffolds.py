from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
CLAUDE_HELPER = ROOT / "ClaudeCode-script/.claude/scripts/merge-settings.py"
PLUGIN_HELPER = ROOT / "ClaudeCodePlugin/claude-loop/payload/scripts/merge-settings.py"
CODEX_HELPER = ROOT / "CodexPlugin/codex-loop/payload/scripts/merge-hooks.py"
PROTECT_HOOKS = (
    ("claude-standalone", ROOT / "ClaudeCode-script/.claude/scripts/protect-files.sh"),
    ("claude-plugin", ROOT / "ClaudeCodePlugin/claude-loop/payload/scripts/protect-files.sh"),
    ("codex", ROOT / "CodexPlugin/codex-loop/payload/scripts/protect-files.sh"),
)
GUARD_HOOKS = (
    ("claude-standalone", ROOT / "ClaudeCode-script/.claude/scripts/guard-bash.sh"),
    ("claude-plugin", ROOT / "ClaudeCodePlugin/claude-loop/payload/scripts/guard-bash.sh"),
    ("codex", ROOT / "CodexPlugin/codex-loop/payload/scripts/guard-bash.sh"),
)


def run(*arguments: str | Path, cwd: Path | None = None, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [str(argument) for argument in arguments],
        cwd=cwd,
        env=env,
        text=True,
        capture_output=True,
        check=True,
    )


def invoke_hook(
    hook: Path,
    payload: object | str,
    *,
    cwd: Path | None = None,
    env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    hook_input = payload if isinstance(payload, str) else json.dumps(payload)
    return subprocess.run(
        ["/bin/bash", str(hook)],
        input=hook_input,
        cwd=cwd,
        env=env,
        text=True,
        capture_output=True,
    )


def codex_update_payload(path: str, old: str, new: str) -> dict[str, object]:
    lines = ["*** Begin Patch", f"*** Update File: {path}", "@@"]
    lines.extend(f"-{line}" for line in old.splitlines())
    lines.extend(f"+{line}" for line in new.splitlines())
    lines.append("*** End Patch")
    return {
        "tool_name": "apply_patch",
        "tool_input": {"command": "\n".join(lines) + "\n"},
    }


class SettingsMergeTests(unittest.TestCase):
    def test_helpers_do_not_drift(self) -> None:
        self.assertEqual(CLAUDE_HELPER.read_bytes(), PLUGIN_HELPER.read_bytes())

    def test_merge_preserves_unrelated_values_and_is_idempotent(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "settings.json"
            target.write_text(json.dumps({
                "permissions": {"deny": ["WebFetch"]},
                "hooks": {"PreToolUse": [{
                    "matcher": "Read",
                    "hooks": [{"type": "command", "command": "check-read"}],
                }]},
                "custom": True,
            }))
            template = ROOT / "ClaudeCode-script/.claude/settings.json"
            run("python3", CLAUDE_HELPER, target, template)
            first = target.read_bytes()
            run("python3", CLAUDE_HELPER, target, template)
            self.assertEqual(first, target.read_bytes())
            merged = json.loads(first)
            self.assertTrue(merged["custom"])
            self.assertEqual(["WebFetch"], merged["permissions"]["deny"])
            commands = [
                hook["command"]
                for entry in merged["hooks"]["PreToolUse"]
                for hook in entry.get("hooks", [])
            ]
            self.assertEqual(1, commands.count("check-read"))
            self.assertEqual(1, sum(command.endswith("protect-files.sh") for command in commands))
            self.assertEqual(1, sum(command.endswith("guard-bash.sh") for command in commands))

    def test_invalid_target_is_untouched(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "settings.json"
            target.write_text("{invalid")
            before = target.read_bytes()
            result = subprocess.run(
                ["python3", str(CLAUDE_HELPER), str(target), str(ROOT / "ClaudeCode-script/.claude/settings.json")],
                text=True,
                capture_output=True,
            )
            self.assertNotEqual(0, result.returncode)
            self.assertEqual(before, target.read_bytes())


class CodexHookMergeTests(unittest.TestCase):
    def test_merge_preserves_unrelated_hook(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "hooks.json"
            target.write_text(json.dumps({"hooks": {"PostToolUse": [{"custom": True}], "PreToolUse": [{
                "matcher": "Read",
                "hooks": [{"type": "command", "command": "check-read"}],
            }]}}))
            template = ROOT / "CodexPlugin/codex-loop/payload/hooks/hooks.json"
            run("python3", CODEX_HELPER, target, template)
            first = target.read_bytes()
            run("python3", CODEX_HELPER, target, template)
            self.assertEqual(first, target.read_bytes())
            merged = json.loads(first)
            self.assertEqual([{"custom": True}], merged["hooks"]["PostToolUse"])
            commands = [
                hook["command"]
                for entry in merged["hooks"]["PreToolUse"]
                for hook in entry.get("hooks", [])
            ]
            self.assertEqual(["check-read", "bash .codex/scripts/protect-files.sh", "bash .codex/scripts/guard-bash.sh"], commands)

    def test_invalid_target_is_untouched(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "hooks.json"
            target.write_text("{invalid")
            before = target.read_bytes()
            result = subprocess.run(
                ["python3", str(CODEX_HELPER), str(target), str(ROOT / "CodexPlugin/codex-loop/payload/hooks/hooks.json")],
                text=True,
                capture_output=True,
            )
            self.assertNotEqual(0, result.returncode)
            self.assertEqual(before, target.read_bytes())


class ChecksScriptTests(unittest.TestCase):
    def test_empty_build_and_lint_arrays_work_under_system_bash(self) -> None:
        for product, source, log_directory in (
            ("claude", ROOT / "ClaudeCode-script/.claude/scripts/checks.sh", ".claude/.checks"),
            ("codex", ROOT / "CodexPlugin/codex-loop/payload/scripts/checks.sh", ".codex/.checks"),
        ):
            with self.subTest(product=product), tempfile.TemporaryDirectory() as directory:
                repo = Path(directory)
                run("git", "init", "-q", repo)
                (repo / "package.json").write_text('{"scripts":{"test":"ignored by fake npm"}}')
                binary = repo / "bin"
                binary.mkdir()
                npm = binary / "npm"
                npm.write_text("#!/usr/bin/env bash\nexit 0\n")
                npm.chmod(0o755)
                python = binary / "python3"
                python.write_text("#!/usr/bin/env bash\nexit 99\n")
                python.chmod(0o755)
                env = dict(os.environ)
                env["PATH"] = f"{binary}:{env['PATH']}"
                quick = run("/bin/bash", source, "--quick", cwd=repo, env=env)
                full = run("/bin/bash", source, cwd=repo, env=env)
                self.assertIn("test: PASS", quick.stdout)
                self.assertIn("build: SKIPPED", full.stdout)
                self.assertIn("test: PASS", full.stdout)
                self.assertTrue((repo / log_directory).is_dir())

    def test_expected_ci_checks_can_be_listed_without_running_project_checks(self) -> None:
        for product, source in (
            ("claude-standalone", ROOT / "ClaudeCode-script/.claude/scripts/checks.sh"),
            ("claude-plugin", ROOT / "ClaudeCodePlugin/claude-loop/payload/scripts/checks.sh"),
            ("codex", ROOT / "CodexPlugin/codex-loop/payload/scripts/checks.sh"),
        ):
            with self.subTest(product=product), tempfile.TemporaryDirectory() as directory:
                repo = Path(directory)
                run("git", "init", "-q", repo)
                script = repo / "checks.sh"
                script.write_text(source.read_text().replace(
                    "EXPECTED_CI_CHECKS=()",
                    'EXPECTED_CI_CHECKS=("CI / verify" "Xcode Cloud")',
                    1,
                ))
                result = run("/bin/bash", script, "--list-ci-checks", cwd=repo)
                self.assertEqual(["CI / verify", "Xcode Cloud"], result.stdout.splitlines())
                self.assertFalse((repo / ".claude/.checks").exists())
                self.assertFalse((repo / ".codex/.checks").exists())

    def test_xcode_projects_take_priority_over_root_swift_packages(self) -> None:
        for product, source in (
            ("claude-standalone", ROOT / "ClaudeCode-script/.claude/scripts/checks.sh"),
            ("claude-plugin", ROOT / "ClaudeCodePlugin/claude-loop/payload/scripts/checks.sh"),
            ("codex", ROOT / "CodexPlugin/codex-loop/payload/scripts/checks.sh"),
        ):
            with self.subTest(product=product), tempfile.TemporaryDirectory() as directory:
                repo = Path(directory)
                run("git", "init", "-q", repo)
                (repo / "Package.swift").write_text("// local package\n")
                (repo / "App.xcodeproj").mkdir()
                result = subprocess.run(
                    ["/bin/bash", str(source), "--quick"],
                    cwd=repo,
                    text=True,
                    capture_output=True,
                )
                self.assertNotEqual(0, result.returncode)
                self.assertIn("Xcode project detected", result.stderr)


class PolicyHookTests(unittest.TestCase):
    def test_protect_hooks_fail_closed_on_malformed_input(self) -> None:
        for product, hook in PROTECT_HOOKS + GUARD_HOOKS:
            with self.subTest(product=product):
                result = invoke_hook(hook, "{invalid")
                self.assertEqual(2, result.returncode)
                self.assertIn("BLOCKED", result.stderr)

    def test_hooks_fail_closed_without_python(self) -> None:
        env = dict(os.environ)
        env["PATH"] = ""
        for product, hook in PROTECT_HOOKS + GUARD_HOOKS:
            with self.subTest(product=product):
                result = invoke_hook(hook, {}, env=env)
                self.assertEqual(2, result.returncode)
                self.assertIn("requires python3", result.stderr)

    def test_entire_policy_trees_are_protected(self) -> None:
        cases = (
            (PROTECT_HOOKS[0], {"tool_input": {"file_path": ".claude/agents/reviewer.md", "new_string": "x"}}),
            (PROTECT_HOOKS[1], {"tool_input": {"file_path": ".claude/skills/verification/SKILL.md", "new_string": "x"}}),
            (PROTECT_HOOKS[2], codex_update_payload(".agents/skills/verification/SKILL.md", "old", "new")),
        )
        for (product, hook), payload in cases:
            with self.subTest(product=product):
                result = invoke_hook(hook, payload)
                self.assertEqual(2, result.returncode)

    def test_lowercase_tests_and_whole_file_writes_cannot_remove_assertions(self) -> None:
        for product, hook in PROTECT_HOOKS:
            with self.subTest(product=product), tempfile.TemporaryDirectory() as directory:
                repo = Path(directory)
                test = repo / "tests/test_feature.py"
                test.parent.mkdir()
                test.write_text("def test_feature():\n    assert feature()\n", encoding="utf-8")
                env = dict(os.environ)
                env["CLAUDE_PROJECT_DIR"] = str(repo)
                payload = (
                    codex_update_payload(
                        "tests/test_feature.py",
                        "    assert feature()",
                        "    pass",
                    )
                    if product == "codex"
                    else {"tool_input": {
                        "file_path": "tests/test_feature.py",
                        "content": "def test_feature():\n    pass\n",
                    }}
                )
                result = invoke_hook(
                    hook,
                    payload,
                    cwd=repo,
                    env=env,
                )
                self.assertEqual(2, result.returncode)
                self.assertIn("removes assertions", result.stderr)

    def test_unittest_assertion_methods_cannot_be_removed(self) -> None:
        for product, hook in PROTECT_HOOKS:
            with self.subTest(product=product), tempfile.TemporaryDirectory() as directory:
                repo = Path(directory)
                test = repo / "tests/test_feature.py"
                test.parent.mkdir()
                test.write_text(
                    "class FeatureTests(unittest.TestCase):\n"
                    "    def test_feature(self):\n"
                    "        self.assertEqual(actual, expected)\n",
                    encoding="utf-8",
                )
                env = dict(os.environ)
                env["CLAUDE_PROJECT_DIR"] = str(repo)
                payload = (
                    codex_update_payload(
                        "tests/test_feature.py",
                        "        self.assertEqual(actual, expected)",
                        "        pass",
                    )
                    if product == "codex"
                    else {"tool_input": {
                        "file_path": "tests/test_feature.py",
                        "content": (
                            "class FeatureTests(unittest.TestCase):\n"
                            "    def test_feature(self):\n"
                            "        pass\n"
                        ),
                    }}
                )
                result = invoke_hook(hook, payload, cwd=repo, env=env)
                self.assertEqual(2, result.returncode)
                self.assertIn("removes assertions", result.stderr)

    def test_codex_apply_patch_blocks_workflow_edits_and_test_deletions(self) -> None:
        product, hook = PROTECT_HOOKS[2]
        workflow = codex_update_payload(".github/workflows/ci.yml", "name: CI", "name: Bypass")
        with self.subTest(product=product, operation="workflow"):
            result = invoke_hook(hook, workflow)
            self.assertEqual(2, result.returncode)
            self.assertIn("policy/CI file", result.stderr)

        delete_test = {
            "tool_name": "apply_patch",
            "tool_input": {"command": (
                "*** Begin Patch\n"
                "*** Delete File: tests/test_feature.py\n"
                "*** End Patch\n"
            )},
        }
        with self.subTest(product=product, operation="delete-test"):
            result = invoke_hook(hook, delete_test)
            self.assertEqual(2, result.returncode)
            self.assertIn("deleting test files", result.stderr)

    def test_bash_guards_cover_git_options_refspecs_and_test_deletions(self) -> None:
        blocked = (
            "git -C elsewhere push --force origin main",
            "git push -uf origin feature",
            "git push --all",
            "git push origin +main",
            "git push origin feature:main",
            "git push origin HEAD:refs/heads/master",
            "gh --repo owner/repo pr merge 42",
            "rm -rf Tests",
            "rm -rf tests/",
        )
        for product, hook in GUARD_HOOKS:
            for command in blocked:
                with self.subTest(product=product, command=command):
                    result = invoke_hook(hook, {"tool_input": {"command": command}})
                    self.assertEqual(2, result.returncode)
            safe = invoke_hook(hook, {"tool_input": {"command": "git push origin main-thread-fix"}})
            self.assertEqual(0, safe.returncode)
            push_option = invoke_hook(hook, {"tool_input": {"command": "git push -o force-color origin feature"}})
            self.assertEqual(0, push_option.returncode)
            non_test = invoke_hook(hook, {"tool_input": {"command": "rm Sources/Contest.swift"}})
            self.assertEqual(0, non_test.returncode)

    def test_bash_guards_block_implicit_pushes_from_protected_branches(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory)
            run("git", "init", "-q", "-b", "main", repo)
            implicit = ("git push", "git push origin", "git push origin HEAD")
            for product, hook in GUARD_HOOKS:
                for command in implicit:
                    with self.subTest(product=product, branch="main", command=command):
                        result = invoke_hook(hook, {"tool_input": {"command": command}}, cwd=repo)
                        self.assertEqual(2, result.returncode)

            run("git", "switch", "-q", "-c", "feature", cwd=repo)
            for product, hook in GUARD_HOOKS:
                for command in implicit:
                    with self.subTest(product=product, branch="feature", command=command):
                        result = invoke_hook(hook, {"tool_input": {"command": command}}, cwd=repo)
                        self.assertEqual(0, result.returncode)

            run("git", "-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "--allow-empty", "-qm", "test", cwd=repo)
            run("git", "remote", "add", "origin", "https://example.invalid/repo.git", cwd=repo)
            run("git", "update-ref", "refs/remotes/origin/main", "HEAD", cwd=repo)
            run("git", "branch", "--set-upstream-to=origin/main", "feature", cwd=repo)
            run("git", "config", "push.default", "upstream", cwd=repo)
            for product, hook in GUARD_HOOKS:
                with self.subTest(product=product, branch="feature-to-main-upstream"):
                    result = invoke_hook(hook, {"tool_input": {"command": "git push"}}, cwd=repo)
                    self.assertEqual(2, result.returncode)


class CloudSetupTests(unittest.TestCase):
    def test_invalid_user_settings_stop_before_toolchain_setup(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory) / "home"
            settings = home / ".claude/settings.json"
            settings.parent.mkdir(parents=True)
            settings.write_text("{invalid")
            env = dict(os.environ)
            env["HOME"] = str(home)
            result = subprocess.run(
                ["/bin/bash", str(ROOT / "ClaudeCode-script/.claude/templates/cloud-setup-swift.sh")],
                cwd=directory,
                env=env,
                text=True,
                capture_output=True,
            )
            self.assertNotEqual(0, result.returncode)
            self.assertIn("FATAL: could not merge sandbox permissions", result.stderr)
            self.assertNotIn("Sandbox permissions merged", result.stdout)


class ReviewRegressionTests(unittest.TestCase):
    def test_yaml_validation_is_optional_without_pyyaml(self) -> None:
        script = (ROOT / "scripts/test-scaffolds.sh").read_text()
        self.assertIn("if python3 -c 'import yaml'", script)
        self.assertIn("PyYAML unavailable; skipped YAML syntax validation", script)
        self.assertIn('"$HAVE_PYYAML" == true', script)
        self.assertIn("Codex plugin/skill validators require PyYAML", script)

    def test_codex_converger_wakes_on_every_completed_ci_run(self) -> None:
        workflow = (ROOT / "CodexPlugin/codex-loop/payload/workflows/codex-converge-trigger.yml").read_text()
        self.assertIn("types: [completed]", workflow)
        self.assertNotIn("conclusion == 'failure'", workflow)

    def test_codex_uses_repository_connected_cloud_tasks_without_an_api_key(self) -> None:
        trigger = (ROOT / "CodexPlugin/codex-loop/payload/workflows/codex-build-trigger.yml").read_text()
        converge = (ROOT / "CodexPlugin/codex-loop/payload/workflows/codex-converge-trigger.yml").read_text()
        self.assertIn("@codex Implement or converge issue", trigger)
        self.assertNotIn("openai/codex-action", trigger)
        self.assertNotIn("OPENAI_API_KEY", trigger)
        self.assertNotIn("openai-api-key", trigger)
        self.assertIn("issues: write", trigger)
        self.assertNotIn("contents: write", trigger)
        self.assertNotIn("pull-requests: write", trigger)
        self.assertIn("expected_label:", trigger)
        self.assertIn("mode:", trigger)
        self.assertIn("reason:", trigger)
        self.assertIn("gh workflow run codex-build-trigger.yml", converge)
        self.assertNotIn("@codex", converge)
        self.assertNotIn("CODEX_RUNNER_LOGIN", converge)

    def test_sweeper_uses_explicit_dispatch_instead_of_trigger_labels(self) -> None:
        trigger = (ROOT / "CodexPlugin/codex-loop/payload/workflows/codex-build-trigger.yml").read_text()
        sweep = (ROOT / "CodexPlugin/codex-loop/payload/workflows/codex-sweep.yml").read_text()
        self.assertIn("workflow_dispatch:", trigger)
        self.assertIn("issue_number:", trigger)
        self.assertIn("expected_label:", trigger)
        self.assertIn("actions: write", sweep)
        self.assertEqual(5, sweep.count("gh workflow run codex-build-trigger.yml"))
        self.assertEqual(5, sweep.count("-f expected_label="))
        self.assertEqual(5, sweep.count("-f mode="))
        self.assertEqual(5, sweep.count("-f reason="))
        self.assertEqual(4, sweep.count("--limit 1000"))
        self.assertNotIn("--add-label codex-build", sweep)

    def test_codex_build_and_convergence_tasks_use_distinct_modes(self) -> None:
        trigger = (ROOT / "CodexPlugin/codex-loop/payload/workflows/codex-build-trigger.yml").read_text()
        converge = (ROOT / "CodexPlugin/codex-loop/payload/workflows/codex-converge-trigger.yml").read_text()
        agents = (ROOT / "CodexPlugin/codex-loop/payload/AGENTS_LOOP.md").read_text()
        self.assertIn("options: [build, event]", trigger)
        self.assertIn("Use $pr-iteration in BUILD MODE", trigger)
        self.assertIn("Use $pr-iteration in EVENT MODE", trigger)
        self.assertIn("-f mode=event", converge)
        self.assertIn("ci-completed", converge)
        self.assertIn("review-submitted", converge)
        self.assertIn("Split-architecture handoffs intentionally keep only\n  codex-running", agents)

    def test_all_expected_ci_providers_must_register(self) -> None:
        paths = (
            "ClaudeCode-script/.claude/skills/pr-iteration/SKILL.md",
            "ClaudeCodePlugin/claude-loop/payload/skills/pr-iteration/SKILL.md",
            "CodexPlugin/codex-loop/payload/skills/pr-iteration/SKILL.md",
        )
        for path in paths:
            with self.subTest(path=path):
                skill = (ROOT / path).read_text()
                self.assertIn("--list-ci-checks", skill)
                self.assertIn("grep -q -- '--list-ci-checks)'", skill)
                self.assertIn("older scaffold", skill)
                self.assertIn("until EVERY configured name is present", skill)

    def test_codex_event_tasks_are_leased_and_overlaps_are_coalesced(self) -> None:
        trigger = (ROOT / "CodexPlugin/codex-loop/payload/workflows/codex-build-trigger.yml").read_text()
        sweep = (ROOT / "CodexPlugin/codex-loop/payload/workflows/codex-sweep.yml").read_text()
        iteration = (ROOT / "CodexPlugin/codex-loop/payload/skills/pr-iteration/SKILL.md").read_text()
        self.assertIn("codex-event-active", trigger)
        self.assertIn("codex-event-pending", trigger)
        self.assertIn("already has an event owner; coalesced this wake", trigger)
        self.assertIn("reason=coalesced-event", sweep)
        self.assertIn("types: [unlabeled]", sweep)
        self.assertIn("remove `codex-event-active`", iteration)
        self.assertIn("Never remove `codex-event-pending`", iteration)

    def test_codex_claim_adds_recoverable_state_before_removing_old_state(self) -> None:
        trigger = (ROOT / "CodexPlugin/codex-loop/payload/workflows/codex-build-trigger.yml").read_text()
        add = trigger.index('--add-label codex-running')
        remove = trigger.index('--remove-label "$LABEL"')
        self.assertLess(add, remove)
        self.assertIn("restored the original state", trigger)
        self.assertIn("original state was preserved", trigger)

    def test_codex_converger_wakes_for_pr_conversation_comments(self) -> None:
        converge = (ROOT / "CodexPlugin/codex-loop/payload/workflows/codex-converge-trigger.yml").read_text()
        trigger = (ROOT / "CodexPlugin/codex-loop/payload/workflows/codex-build-trigger.yml").read_text()
        self.assertIn("issue_comment:\n    types: [created]", converge)
        self.assertIn("github.event.issue.pull_request", converge)
        self.assertIn("REASON=conversation-comment", converge)
        self.assertIn("event:conversation-comment", trigger)

    def test_sweeper_uses_current_loop_activity_before_recovery(self) -> None:
        sweep = (ROOT / "CodexPlugin/codex-loop/payload/workflows/codex-sweep.yml").read_text()
        self.assertIn("checks: read", sweep)
        self.assertIn("statuses: read", sweep)
        self.assertIn("--json updatedAt", sweep)
        self.assertIn(".reviews[]?.submittedAt", sweep)
        self.assertIn("/check-runs?per_page=100", sweep)
        self.assertIn('.status != "completed"', sweep)
        self.assertIn('.state == "pending"', sweep)

    def test_sweeper_dispatches_each_external_ci_completion_once(self) -> None:
        sweep = (ROOT / "CodexPlugin/codex-loop/payload/workflows/codex-sweep.yml").read_text()
        self.assertIn("check_run:\n    types: [completed]", sweep)
        self.assertIn("status:\nconcurrency:", sweep)
        self.assertIn('select((.app.slug // "") != "github-actions"', sweep)
        self.assertIn("CI_SIGNAL_COUNT=$(( EXTERNAL_CHECK_COUNT + STATUS_COUNT ))", sweep)
        self.assertIn('[ "$CI_SIGNAL_COUNT" -gt 0 ]', sweep)
        self.assertIn('CI_MARKER="codex-ci-dispatched $HEAD_SHA $CI_COMPLETED_AT"', sweep)
        self.assertIn('grep -Fq "$CI_MARKER"', sweep)
        self.assertIn('-f issue_number="$N" -f expected_label=codex-running', sweep)

    def test_codex_success_replaces_running_with_ready(self) -> None:
        iteration = (ROOT / "CodexPlugin/codex-loop/payload/skills/pr-iteration/SKILL.md").read_text()
        sweep = (ROOT / "CodexPlugin/codex-loop/payload/workflows/codex-sweep.yml").read_text()
        self.assertIn("replace `codex-running`\n   with `codex-ready`", iteration)
        self.assertIn("--remove-label codex-running", sweep)

    def test_dependency_resume_markers_prevent_stale_unparking(self) -> None:
        codex = (ROOT / "CodexPlugin/codex-loop/payload/workflows/codex-sweep.yml").read_text()
        claude = (ROOT / "ClaudeCodePlugin/claude-loop/payload/SWEEP_ROUTINE_PROMPT.md").read_text()
        self.assertIn("codex-dependency-resumed #$DEP", codex)
        self.assertIn('"$RESUMED_LINE" -gt "$WAIT_LINE"', codex)
        self.assertIn("most recent", claude)
        self.assertIn("claude-dependency-resumed #<x>", claude)

    def test_policy_issues_are_created_without_build_labels(self) -> None:
        paths = (
            "CodexPlugin/codex-loop/payload/skills/plan-to-issue/SKILL.md",
            "ClaudeCodePlugin/claude-loop/payload/skills/plan-to-issue/SKILL.md",
            "ClaudeCode-script/.claude/skills/plan-to-issue/SKILL.md",
        )
        for path in paths:
            with self.subTest(path=path):
                skill = (ROOT / path).read_text()
                self.assertIn("Choose exactly one creation path", skill)
                self.assertIn('gh issue create --title "..." --body "..."` with\n     no build label', skill)

    def test_claude_has_one_subscribing_routine_and_no_split_converger(self) -> None:
        routine = (ROOT / "ClaudeCodePlugin/claude-loop/payload/ROUTINE_PROMPT.md").read_text()
        init_skill = (ROOT / "ClaudeCodePlugin/claude-loop/skills/loop-init/SKILL.md").read_text()
        standalone_readme = (ROOT / "ClaudeCode-script/README.md").read_text()
        plugin_payload = ROOT / "ClaudeCodePlugin/claude-loop/payload"
        self.assertIn("no dispatch comment is required for an empty backlog", routine)
        self.assertIn(routine, standalone_readme)
        self.assertFalse((plugin_payload / "CONVERGE_ROUTINE_PROMPT.md").exists())
        self.assertFalse((plugin_payload / "templates/claude-build-routine-prompt.md").exists())
        self.assertFalse((plugin_payload / "templates/claude-converge-trigger.yml").exists())
        self.assertNotIn("EVENT MODE", (plugin_payload / "skills/pr-iteration/SKILL.md").read_text())
        self.assertIn("FULL single-routine prompt", init_skill)
        self.assertNotIn("--with-converger", standalone_readme)
        self.assertIn("STEP 0 — DEPENDENCIES, CLAIM & IDEMPOTENCY.", standalone_readme)
        self.assertIn("7. DISPATCH SUGGESTION", standalone_readme)

    def test_install_guidance_covers_managed_workflow_state(self) -> None:
        claude_skill = (ROOT / "ClaudeCodePlugin/claude-loop/skills/loop-init/SKILL.md").read_text()
        codex_skill = (ROOT / "CodexPlugin/codex-loop/skills/loop-init/SKILL.md").read_text()
        installer = (ROOT / "ClaudeCode-script/install.sh").read_text()
        self.assertIn("Routine B was removed", claude_skill)
        self.assertIn("never overwrite an existing workflow", codex_skill)
        self.assertNotIn("CLAUDE_RUNNER_LOGIN", installer)
        self.assertNotIn("--with-converger", installer)
        self.assertIn("Set up Codex cloud", codex_skill)
        self.assertIn("@codex", codex_skill)
        self.assertIn("codex-event-active", codex_skill)
        self.assertIn("codex-event-pending", codex_skill)
        self.assertNotIn("OPENAI_API_KEY", codex_skill)
        self.assertNotIn("CODEX_RUNNER_LOGIN", codex_skill)

    def test_codex_escalation_blocks_the_linked_issue(self) -> None:
        skill = (ROOT / "CodexPlugin/codex-loop/payload/skills/pr-iteration/SKILL.md").read_text()
        self.assertIn("replace `codex-running` with `codex-blocked`", skill)
        self.assertIn("Verify the issue has exactly the blocked terminal state label", skill)

    def test_claude_completion_and_escalation_set_terminal_labels(self) -> None:
        for path in (
            "ClaudeCode-script/.claude/skills/pr-iteration/SKILL.md",
            "ClaudeCodePlugin/claude-loop/payload/skills/pr-iteration/SKILL.md",
        ):
            with self.subTest(path=path):
                skill = (ROOT / path).read_text()
                self.assertIn("replace `claude-running`\n   with `claude-ready`", skill)
                self.assertIn("replace `claude-running` with `claude-blocked`", skill)

    def test_archive_verification_is_read_only_and_modes_are_normalized(self) -> None:
        build = (ROOT / "scripts/build-plugins.sh").read_text()
        test = (ROOT / "scripts/test-scaffolds.sh").read_text()
        self.assertIn("--check", build)
        self.assertIn("0o755 if", build)
        self.assertIn('"$ROOT/scripts/build-plugins.sh" --check', test)
        self.assertNotIn("if rg -n", test)

    def test_claude_docs_name_the_current_issue_trigger(self) -> None:
        readme = (ROOT / "ClaudeCode-script/README.md").read_text()
        fallback = (ROOT / "ClaudeCodePlugin/claude-loop/payload/fallback/claude-build-trigger.yml").read_text()
        plan = (ROOT / "ClaudeCodePlugin/claude-loop/payload/skills/plan-to-issue/SKILL.md").read_text()
        self.assertIn('native GitHub trigger "Issue: Labeled"', readme)
        self.assertIn("Issue: Labeled + Labels", fallback)
        self.assertIn("fires the Issue: Labeled routine", plan)


class InstallerTests(unittest.TestCase):
    def test_install_is_idempotent_and_preserves_settings_and_checks(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory) / "repo"
            repo.mkdir()
            run("git", "init", "-q", repo)
            settings = repo / ".claude/settings.json"
            settings.parent.mkdir()
            settings.write_text(json.dumps({"custom": "keep", "hooks": {"PreToolUse": []}}))
            checks = repo / ".claude/scripts/checks.sh"
            checks.parent.mkdir()
            checks.write_text("#!/usr/bin/env bash\nexit 0\n")
            checks.chmod(0o755)
            legacy_build = repo / ".claude/templates/claude-build-routine-prompt.md"
            legacy_build.parent.mkdir(parents=True)
            legacy_build.write_text("legacy\n")
            legacy_trigger = repo / ".claude/templates/claude-converge-trigger.yml"
            legacy_trigger.write_text("legacy\n")
            configured_workflow = repo / ".github/workflows/claude-converge-trigger.yml"
            configured_workflow.parent.mkdir(parents=True)
            configured_workflow.write_text("configured by user\n")

            binary = repo / "bin"
            binary.mkdir()
            gh = binary / "gh"
            gh.write_text("#!/usr/bin/env bash\nexit 1\n")
            gh.chmod(0o755)
            env = dict(os.environ)
            env["PATH"] = f"{binary}:{env['PATH']}"
            installer = ROOT / "ClaudeCode-script/install.sh"
            first_install = run("/bin/bash", installer, repo, cwd=ROOT, env=env)
            first = settings.read_bytes()
            run("/bin/bash", installer, repo, cwd=ROOT, env=env)
            self.assertEqual(first, settings.read_bytes())
            self.assertEqual("#!/usr/bin/env bash\nexit 0\n", checks.read_text())
            self.assertEqual("keep", json.loads(first)["custom"])
            self.assertFalse(legacy_build.exists())
            self.assertFalse(legacy_trigger.exists())
            self.assertEqual("configured by user\n", configured_workflow.read_text())
            self.assertIn("Routine B was removed", first_install.stderr)

    def test_invalid_settings_stop_before_installation_changes(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory) / "repo"
            repo.mkdir()
            run("git", "init", "-q", repo)
            settings = repo / ".claude/settings.json"
            settings.parent.mkdir()
            settings.write_text("{invalid")
            before = settings.read_bytes()
            result = subprocess.run(
                ["/bin/bash", str(ROOT / "ClaudeCode-script/install.sh"), str(repo)],
                cwd=ROOT,
                text=True,
                capture_output=True,
            )
            self.assertNotEqual(0, result.returncode)
            self.assertEqual(before, settings.read_bytes())
            self.assertEqual([settings], [path for path in (repo / ".claude").rglob("*") if path.is_file()])

    def test_existing_labels_are_listed_without_attempting_creation(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory) / "repo"
            repo.mkdir()
            run("git", "init", "-q", repo)
            binary = repo / "bin"
            binary.mkdir()
            log = repo / "label-create.log"
            gh = binary / "gh"
            gh.write_text(
                "#!/usr/bin/env bash\n"
                "if [[ \"$1 $2\" == \"auth status\" ]]; then exit 0; fi\n"
                "if [[ \"$1 $2\" == \"label list\" ]]; then printf '%s\\n' claude-build claude-running claude-ready claude-blocked; exit 0; fi\n"
                "if [[ \"$1 $2\" == \"label create\" ]]; then printf '%s\\n' \"$*\" >> \"$GH_LOG\"; exit 99; fi\n"
                "exit 1\n",
                encoding="utf-8",
            )
            gh.chmod(0o755)
            env = dict(os.environ)
            env["PATH"] = f"{binary}:{env['PATH']}"
            env["GH_LOG"] = str(log)
            result = run("/bin/bash", ROOT / "ClaudeCode-script/install.sh", repo, cwd=ROOT, env=env)
            self.assertIn("claude-build exists", result.stdout)
            self.assertFalse(log.exists())

    def test_label_inspection_failure_does_not_attempt_creation(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory) / "repo"
            repo.mkdir()
            run("git", "init", "-q", repo)
            binary = repo / "bin"
            binary.mkdir()
            log = repo / "label-create.log"
            gh = binary / "gh"
            gh.write_text(
                "#!/usr/bin/env bash\n"
                "if [[ \"$1 $2\" == \"auth status\" ]]; then exit 0; fi\n"
                "if [[ \"$1 $2\" == \"label list\" ]]; then exit 77; fi\n"
                "if [[ \"$1 $2\" == \"label create\" ]]; then printf '%s\\n' \"$*\" >> \"$GH_LOG\"; exit 0; fi\n"
                "exit 1\n",
                encoding="utf-8",
            )
            gh.chmod(0o755)
            env = dict(os.environ)
            env["PATH"] = f"{binary}:{env['PATH']}"
            env["GH_LOG"] = str(log)
            result = run("/bin/bash", ROOT / "ClaudeCode-script/install.sh", repo, cwd=ROOT, env=env)
            self.assertIn("could not inspect repository labels", result.stderr)
            self.assertFalse(log.exists())


if __name__ == "__main__":
    unittest.main()
