#!/usr/bin/env python3
"""Installer, verifier and conservative uninstall regressions for v3.6 runtime."""
from __future__ import annotations

import json
import pathlib
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
INSTALLER = ROOT / "scripts" / "governance-runtime-install.py"
AGENTS = (
    "architect",
    "build",
    "plan",
    "executor",
    "reviewer",
    "reviewer-architecture",
    "final-reviewer",
)
COMMANDS = (
    "ai-review",
    "ai-workflow",
    "ai-resume",
    "ai-release",
    "ai-status",
    "ai-metrics",
)
TOOLS = (
    "governance-authority.py",
    "governance-memory.py",
    "governance-evidence.py",
    "governance-simulation.py",
)


def run(*arguments: object, ok: bool = True) -> subprocess.CompletedProcess[str]:
    process = subprocess.run(
        [sys.executable, str(INSTALLER), *map(str, arguments)],
        text=True,
        capture_output=True,
    )
    if ok and process.returncode:
        raise AssertionError(f"{process.stdout}\n{process.stderr}")
    return process


class RuntimeInstallerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.config = pathlib.Path(self.temporary.name) / "config"
        (self.config / "agents").mkdir(parents=True)
        (self.config / "commands").mkdir()
        (self.config / "opencode-governance-tools").mkdir()
        for name in AGENTS:
            (self.config / "agents" / f"{name}.md").write_text(
                f"---\ndescription: {name}\n---\n\n## Core invariants\n\nBASE-{name}\n",
                encoding="utf-8",
            )
        for name in COMMANDS:
            (self.config / "commands" / f"{name}.md").write_text(
                f"---\ndescription: {name}\n---\n\nBASE-{name}\n",
                encoding="utf-8",
            )
        self.unrelated = self.config / "opencode-governance-tools" / "owner-tool.txt"
        self.unrelated.write_text("preserve", encoding="utf-8")

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def install(self) -> None:
        run("install", "--source-dir", ROOT / "scripts", "--config-dir", self.config)

    def test_install_verify_is_idempotent_and_hash_bound(self) -> None:
        self.install()
        first_manifest = json.loads((self.config / "opencode-governance-runtime.json").read_text())
        self.assertEqual("3.6.0", first_manifest["governance_version"])
        self.assertEqual("3.4.4", first_manifest["base_governance_version"])
        self.assertEqual(4, len(first_manifest["managed_tools"]))
        run("verify", "--config-dir", self.config)
        self.install()
        run("verify", "--config-dir", self.config)
        for name in AGENTS:
            text = (self.config / "agents" / f"{name}.md").read_text()
            self.assertEqual(1, text.count("## GOVERNANCE_AUTHORITY_V1"))
            self.assertEqual(1, text.count("## GOVERNED_ENGINEERING_MEMORY_V2"))
            self.assertEqual(1, text.count("## EVIDENCE_REUSE_LEDGER_V1"))
        for name in TOOLS:
            self.assertTrue((self.config / "opencode-governance-tools" / name).is_file())
        self.assertEqual("preserve", self.unrelated.read_text())
        self.assertGreaterEqual(len(list((self.config / "backups").glob("opencode-governance-runtime-*"))), 2)

    def test_verify_rejects_tool_drift(self) -> None:
        self.install()
        authority = self.config / "opencode-governance-tools" / "governance-authority.py"
        authority.write_text(authority.read_text() + "\n# drift\n", encoding="utf-8")
        failure = run("verify", "--config-dir", self.config, ok=False)
        self.assertIn("RUNTIME_TOOL_INTEGRITY_FAILURE", failure.stdout + failure.stderr)

    def test_uninstall_removes_only_managed_overlay(self) -> None:
        self.install()
        run("uninstall", "--config-dir", self.config)
        self.assertFalse((self.config / "opencode-governance-runtime.json").exists())
        for name in TOOLS:
            self.assertFalse((self.config / "opencode-governance-tools" / name).exists())
        self.assertEqual("preserve", self.unrelated.read_text())
        for name in AGENTS:
            text = (self.config / "agents" / f"{name}.md").read_text()
            self.assertIn(f"BASE-{name}", text)
            self.assertNotIn("GOVERNANCE_AUTHORITY_V1", text)
        for name in COMMANDS:
            text = (self.config / "commands" / f"{name}.md").read_text()
            self.assertIn(f"BASE-{name}", text)
            self.assertNotIn("GOVERNANCE_RUNTIME", text)

    def test_refuses_incomplete_base_installation(self) -> None:
        (self.config / "agents" / "executor.md").unlink()
        failure = run("install", "--source-dir", ROOT / "scripts", "--config-dir", self.config, ok=False)
        self.assertIn("BASE_AGENT_MISSING", failure.stdout + failure.stderr)
        self.assertFalse((self.config / "opencode-governance-runtime.json").exists())


if __name__ == "__main__":
    unittest.main()
