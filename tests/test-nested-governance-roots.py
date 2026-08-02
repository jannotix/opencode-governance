#!/usr/bin/env python3
"""Unit tests for WORKSPACE_REPOSITORY_ROOT_CONTRACT_V1 and git -C permissions (3.7.5)."""
from __future__ import annotations

import importlib.util
import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


def load(name: str, path: pathlib.Path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class NestedRootContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.rc = load("workspace_repository_root_contract", ROOT / "scripts" / "workspace-repository-root-contract.py")
        cls.hc = load("architect_headless_contract", ROOT / "scripts" / "architect-headless-contract.py")

    def test_git_c_readonly_allowed(self) -> None:
        for command in (
            "git -C /tmp/repo rev-parse HEAD",
            "git -C /tmp/repo status --porcelain",
            "git -C /tmp/repo branch --show-current",
            "git -C /tmp/repo remote -v",
            "git -C /tmp/repo rev-list --count HEAD",
            "git -C /tmp/repo ls-files",
            "Get-FileHash -LiteralPath .ai/STATUS.md",
        ):
            with self.subTest(command=command):
                self.assertEqual(self.hc.evaluate_bash_permission(command), "allow")

    def test_git_c_write_denied(self) -> None:
        for command in (
            "git -C /tmp/repo push origin main",
            "git -C /tmp/repo add .",
            "git -C /tmp/repo commit -m x",
            "git -C /tmp/repo reset --hard",
            "git -C /tmp/repo checkout -b x",
        ):
            with self.subTest(command=command):
                self.assertEqual(self.hc.evaluate_bash_permission(command), "deny")

    def test_nested_resolution_and_fingerprint_excludes_managed_roots(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            ws = pathlib.Path(directory)
            repo = ws / "Source_Code"
            (ws / ".ai").mkdir()
            (repo / ".ai").mkdir(parents=True)
            (repo / "app").mkdir()
            (ws / ".ai" / "STATUS.md").write_text("workspace\n", encoding="utf-8")
            (repo / ".ai" / "STATUS.md").write_text("repo\n", encoding="utf-8")
            (repo / "app" / "file.php").write_text("<?php\n", encoding="utf-8")
            subprocess.run(["git", "init"], cwd=repo, check=True, capture_output=True)
            resolved = self.rc.resolve_roots(workspace_dir=str(ws))
            self.assertEqual(pathlib.Path(resolved["repository_root"]).resolve(), repo.resolve())
            self.assertEqual(len(resolved["managed_governance_roots"]), 2)
            managed = [m["canonical_path"] for m in resolved["managed_governance_roots"]]
            before = self.rc.project_state_fingerprint(ws, repo, managed)
            (ws / ".ai" / "STATUS.md").write_text("workspace-2\n", encoding="utf-8")
            (repo / ".ai" / "tasks").mkdir()
            (repo / ".ai" / "tasks" / "TASK").mkdir()
            (repo / ".ai" / "tasks" / "TASK" / "RUN_STATE.json").write_text("{}", encoding="utf-8")
            after_gov = self.rc.project_state_fingerprint(ws, repo, managed)
            self.assertEqual(before, after_gov)
            (repo / "app" / "file.php").write_text("changed\n", encoding="utf-8")
            after_app = self.rc.project_state_fingerprint(ws, repo, managed)
            self.assertNotEqual(before, after_app)

    def test_ambiguous_and_outside(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            ws = pathlib.Path(directory)
            a = ws / "a"
            b = ws / "b"
            a.mkdir()
            b.mkdir()
            subprocess.run(["git", "init"], cwd=a, check=True, capture_output=True)
            subprocess.run(["git", "init"], cwd=b, check=True, capture_output=True)
            with self.assertRaises(self.rc.RootContractError) as ctx:
                self.rc.resolve_roots(workspace_dir=str(ws))
            self.assertEqual(ctx.exception.code, "REPOSITORY_ROOT_AMBIGUOUS")
        with tempfile.TemporaryDirectory() as directory:
            ws = pathlib.Path(directory) / "ws"
            repo = pathlib.Path(directory) / "repo"
            ws.mkdir()
            repo.mkdir()
            with self.assertRaises(self.rc.RootContractError) as ctx:
                self.rc.resolve_roots(workspace_dir=str(ws), repository_dir=str(repo))
            self.assertEqual(ctx.exception.code, "REPOSITORY_ROOT_OUTSIDE_WORKSPACE")

    def test_multi_root_snapshot_restore(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            base = pathlib.Path(directory)
            ws_ai = base / "ws" / ".ai"
            repo_ai = base / "repo" / ".ai"
            ws_ai.mkdir(parents=True)
            repo_ai.mkdir(parents=True)
            (ws_ai / "STATUS.md").write_text("w1\n", encoding="utf-8")
            (repo_ai / "STATUS.md").write_text("r1\n", encoding="utf-8")
            roots = [
                {"canonical_path": str(ws_ai), "role": "workspace_governance"},
                {"canonical_path": str(repo_ai), "role": "repository_governance"},
            ]
            tx = base / "tx"
            tx.mkdir()
            recorded = self.rc.snapshot_managed_roots(tx, roots)
            (ws_ai / "STATUS.md").write_text("w2\n", encoding="utf-8")
            (repo_ai / "STATUS.md").write_text("r2\n", encoding="utf-8")
            self.rc.restore_managed_roots(recorded)
            self.assertEqual((ws_ai / "STATUS.md").read_text(encoding="utf-8"), "w1\n")
            self.assertEqual((repo_ai / "STATUS.md").read_text(encoding="utf-8"), "r1\n")

    def test_unrelated_ai_not_excluded(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            ws = pathlib.Path(directory)
            (ws / ".ai").mkdir()
            (ws / ".ai" / "STATUS.md").write_text("ok\n", encoding="utf-8")
            other = ws / "vendor_pkg" / ".ai"
            other.mkdir(parents=True)
            (other / "x.md").write_text("1\n", encoding="utf-8")
            managed = [str((ws / ".ai").resolve())]
            before = self.rc.project_state_fingerprint(ws, ws, managed)
            (other / "x.md").write_text("2\n", encoding="utf-8")
            after = self.rc.project_state_fingerprint(ws, ws, managed)
            self.assertNotEqual(before, after)


if __name__ == "__main__":
    unittest.main()
