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


def run(*arguments: str | Path, cwd: Path | None = None, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [str(argument) for argument in arguments],
        cwd=cwd,
        env=env,
        text=True,
        capture_output=True,
        check=True,
    )


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
                env = dict(os.environ)
                env["PATH"] = f"{binary}:{env['PATH']}"
                quick = run("/bin/bash", source, "--quick", cwd=repo, env=env)
                full = run("/bin/bash", source, cwd=repo, env=env)
                self.assertIn("test: PASS", quick.stdout)
                self.assertIn("build: SKIPPED", full.stdout)
                self.assertIn("test: PASS", full.stdout)
                self.assertTrue((repo / log_directory).is_dir())


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

    def test_sweeper_uses_explicit_dispatch_instead_of_trigger_labels(self) -> None:
        trigger = (ROOT / "CodexPlugin/codex-loop/payload/workflows/codex-build-trigger.yml").read_text()
        sweep = (ROOT / "CodexPlugin/codex-loop/payload/workflows/codex-sweep.yml").read_text()
        self.assertIn("workflow_dispatch:", trigger)
        self.assertIn("issue_number:", trigger)
        self.assertIn("actions: write", sweep)
        self.assertEqual(3, sweep.count("gh workflow run codex-build-trigger.yml"))
        self.assertNotIn("--add-label codex-build", sweep)

    def test_sweeper_uses_current_loop_activity_before_recovery(self) -> None:
        sweep = (ROOT / "CodexPlugin/codex-loop/payload/workflows/codex-sweep.yml").read_text()
        self.assertIn("checks: read", sweep)
        self.assertIn("statuses: read", sweep)
        self.assertIn("--json updatedAt", sweep)
        self.assertIn(".reviews[]?.submittedAt", sweep)
        self.assertIn("/check-runs?per_page=100", sweep)
        self.assertIn('.status != "completed"', sweep)
        self.assertIn('.state == "pending"', sweep)

    def test_codex_success_replaces_running_with_ready(self) -> None:
        converge = (ROOT / "CodexPlugin/codex-loop/payload/workflows/codex-converge-trigger.yml").read_text()
        sweep = (ROOT / "CodexPlugin/codex-loop/payload/workflows/codex-sweep.yml").read_text()
        self.assertIn("replace the linked issue's codex-running label with codex-ready", converge)
        self.assertIn("--remove-label codex-running", sweep)

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

    def test_claude_empty_backlog_and_split_converger_are_fully_specified(self) -> None:
        routine = (ROOT / "ClaudeCodePlugin/claude-loop/payload/ROUTINE_PROMPT.md").read_text()
        init_skill = (ROOT / "ClaudeCodePlugin/claude-loop/skills/loop-init/SKILL.md").read_text()
        standalone_readme = (ROOT / "ClaudeCode-script/README.md").read_text()
        prompt = ROOT / "ClaudeCodePlugin/claude-loop/payload/CONVERGE_ROUTINE_PROMPT.md"
        self.assertIn("no dispatch comment is required for an empty backlog", routine)
        self.assertTrue(prompt.is_file())
        self.assertIn("CONVERGE_ROUTINE_PROMPT.md", init_skill)
        self.assertIn("You were woken because something happened", prompt.read_text())
        self.assertIn("verify it has exactly one state", prompt.read_text())
        self.assertIn(prompt.read_text(), standalone_readme)

    def test_install_guidance_covers_managed_workflow_state(self) -> None:
        claude_skill = (ROOT / "ClaudeCodePlugin/claude-loop/skills/loop-init/SKILL.md").read_text()
        codex_skill = (ROOT / "CodexPlugin/codex-loop/skills/loop-init/SKILL.md").read_text()
        installer = (ROOT / "ClaudeCode-script/install.sh").read_text()
        self.assertIn(".github/workflows/claude-converge-trigger.yml", claude_skill)
        self.assertIn("never overwrite an existing workflow", codex_skill)
        self.assertIn("CLAUDE_RUNNER_LOGIN repo variable", installer)

    def test_codex_escalation_blocks_the_linked_issue(self) -> None:
        skill = (ROOT / "CodexPlugin/codex-loop/payload/skills/pr-iteration/SKILL.md").read_text()
        self.assertIn("replace `codex-running` with `codex-blocked`", skill)
        self.assertIn("Verify the issue has exactly the blocked terminal label", skill)


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

            binary = repo / "bin"
            binary.mkdir()
            gh = binary / "gh"
            gh.write_text("#!/usr/bin/env bash\nexit 1\n")
            gh.chmod(0o755)
            env = dict(os.environ)
            env["PATH"] = f"{binary}:{env['PATH']}"
            installer = ROOT / "ClaudeCode-script/install.sh"
            run("/bin/bash", installer, repo, cwd=ROOT, env=env)
            first = settings.read_bytes()
            run("/bin/bash", installer, repo, cwd=ROOT, env=env)
            self.assertEqual(first, settings.read_bytes())
            self.assertEqual("#!/usr/bin/env bash\nexit 0\n", checks.read_text())
            self.assertEqual("keep", json.loads(first)["custom"])

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


if __name__ == "__main__":
    unittest.main()
