#!/usr/bin/env python3
"""Unit tests for ARCHITECT_HEADLESS_PERMISSION_CONTRACT_V1."""
from __future__ import annotations

import importlib.util
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
MODULE = ROOT / "scripts" / "architect-headless-contract.py"


def load_module():
    spec = importlib.util.spec_from_file_location("architect_headless_contract", MODULE)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class HeadlessContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.m = load_module()

    def test_version(self) -> None:
        self.assertEqual(self.m.CONTRACT_VERSION, "ARCHITECT_HEADLESS_PERMISSION_CONTRACT_V1")

    def test_allow_readonly_git_and_fs(self) -> None:
        for command in (
            "git status",
            "git status --porcelain",
            "git diff --stat",
            "git log -1",
            "git show HEAD",
            "git grep foo",
            "git rev-parse HEAD",
            "git ls-files",
            "git submodule status",
            "git worktree list",
            "git branch --show-current",
            "git remote -v",
            "git -C /repo rev-parse HEAD",
            "git -C /repo status --porcelain",
            "git -C /repo branch --show-current",
            "git -C /repo remote -v",
            "git -C /repo rev-list --count HEAD",
            "git -C /repo ls-files",
            "ls -la",
            "pwd",
            "cat README.md",
            "rg pattern",
            "Test-Path -LiteralPath .ai",
            "Get-ChildItem -LiteralPath . -Force",
            "Get-Content -LiteralPath README.md",
            "Get-FileHash -LiteralPath .ai/STATUS.md",
        ):
            with self.subTest(command=command):
                self.assertEqual(self.m.evaluate_bash_permission(command), "allow")

    def test_deny_mutations_and_bypasses(self) -> None:
        for command in (
            "git push origin main",
            "git fetch origin",
            "git merge main",
            "git rebase main",
            "git checkout -b x",
            "git clean -fd",
            "git add .",
            "git commit -m x",
            "git -C /repo push origin main",
            "git -C /repo add .",
            "git -C /repo commit -m x",
            "Set-Content -Path a -Value b",
            "Add-Content a b",
            "Out-File out.txt",
            "Remove-Item secret.txt",
            "Invoke-Expression Get-ChildItem",
            "pwsh -Command Get-ChildItem",
            "powershell -EncodedCommand QQ==",
            "cmd /c dir",
            "bash -c ls",
            "sh -c ls",
            "python -c print(1)",
            "node -e console.log(1)",
            "npm install lodash",
            "composer update",
            "find . -delete",
            "sed -i s/a/b/ file",
            "curl https://example.com",
            "echo hi > file.txt",
            "ls && rm -rf /",
            "git status && git push",
            "Get-ChildItem | Remove-Item",
            "ls; git push",
            "echo $(rm -rf /)",
        ):
            with self.subTest(command=command):
                self.assertEqual(self.m.evaluate_bash_permission(command), "deny")

    def test_no_ask_in_bash_policy(self) -> None:
        rules = self.m.build_bash_permission()
        self.assertEqual(rules["*"], "deny")
        self.assertNotIn("ask", set(rules.values()))

    def test_config_deny_default_and_hash(self) -> None:
        cfg = self.m.build_headless_config(
            model="test/architect",
            variant="high",
            external_roots=["/tmp/opencode-config"],
        )
        self.assertEqual(cfg["permission"]["bash"]["*"], "deny")
        self.assertEqual(cfg["agent"]["architect"]["permission"]["bash"]["*"], "deny")
        self.assertEqual(cfg["agent"]["architect"]["model"], "test/architect")
        self.assertEqual(cfg["agent"]["architect"]["variant"], "high")
        self.assertEqual(cfg["agent"]["architect"]["permission"]["question"], "deny")
        self.assertEqual(cfg["agent"]["architect"]["permission"]["webfetch"], "deny")
        digest = self.m.config_sha256(cfg)
        self.assertEqual(len(digest), 64)

    def test_jsonc_load_preserves_semantics(self) -> None:
        raw = '{\n  // comment\n  "a": 1,\n  "b": [2,],\n}\n'
        value, source_hash, semantic_hash = self.m.load_jsonc_object(raw)
        self.assertEqual(value, {"a": 1, "b": [2]})
        self.assertEqual(len(source_hash), 64)
        self.assertEqual(len(semantic_hash), 64)
        self.assertNotEqual(source_hash, semantic_hash)

    def test_permission_blocked_markers(self) -> None:
        text = "permission requested: bash (Test-Path); auto-rejecting\nThe user rejected permission to use this specific tool call."
        self.assertTrue(self.m.permission_blocked_in_text(text))
        self.assertEqual(self.m.classify_denied_tool(text), "bash")


if __name__ == "__main__":
    unittest.main()
