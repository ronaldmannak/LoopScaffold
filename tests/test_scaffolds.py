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
