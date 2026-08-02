#!/usr/bin/env python3
"""Canonical 3.6 capability installation and manifest regressions."""
from __future__ import annotations

import json
import pathlib
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
HELPER = ROOT / "scripts" / "governance-capabilities.py"
AGENTS = (
    "architect", "build", "plan", "executor", "reviewer",
    "reviewer-architecture", "final-reviewer",
)
COMMANDS = (
    "ai-init", "ai-audit", "ai-docs", "ai-discover", "ai-plan",
    "ai-execute", "ai-review", "ai-workflow", "ai-status", "ai-resume",
    "ai-metrics", "ai-release",
)
BASE_TOOLS = (
    "architect-attempt.ps1", "architect-attempt.sh", "architect-headless-contract.py",
    "executor-attempt.ps1", "executor-attempt.sh",
    "context-intelligence.ps1", "context-intelligence.sh",
    "context-intelligence.py", "workflow-continuation.ps1",
    "workflow-continuation.py",
)
CAPABILITY_TOOLS = (
    "governance-authority.py", "governance-memory.py",
    "governance-evidence.py", "governance-simulation.py",
    "governance-pre-commit.py",
)


def run(*arguments: object, ok: bool = True) -> subprocess.CompletedProcess[str]:
    process = subprocess.run(
        [sys.executable, str(HELPER), *map(str, arguments)],
        text=True,
        capture_output=True,
    )
    if ok and process.returncode:
        raise AssertionError(f"{process.stdout}\n{process.stderr}")
    return process


class GovernanceCapabilitiesTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.config = (pathlib.Path(self.temporary.name) / "config").resolve()
        self.tools = self.config / "opencode-governance-tools"
        (self.config / "agents").mkdir(parents=True)
        (self.config / "commands").mkdir()
        self.tools.mkdir()
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
        for name in BASE_TOOLS:
            (self.tools / name).write_text(f"BASE-{name}\n", encoding="utf-8")
        self.manifest_path = self.config / "opencode-governance-routing.json"
        self.routing = {
            "schema_version": "1.0",
            "governance_version": "3.4.4",
            "architect_runner_version": "3.4.4",
            "context_intelligence_version": "3.4.4",
            "workflow_continuation_version": "3.4.4",
            "settings": {"sentinel": "preserve-settings"},
            "roles": {"sentinel": "preserve-roles"},
            "managed_aliases": [],
            "managed_tools": [str(self.tools / name) for name in BASE_TOOLS],
        }
        self.manifest_path.write_text(json.dumps(self.routing, indent=2) + "\n", encoding="utf-8")
        self.unrelated = self.tools / "owner-tool.txt"
        self.unrelated.write_text("preserve", encoding="utf-8")

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def install(self) -> dict[str, object]:
        run("install", "--source-dir", ROOT / "scripts", "--config-dir", self.config)
        return json.loads(self.manifest_path.read_text(encoding="utf-8"))

    def test_install_uses_one_canonical_manifest_and_preserves_routing(self) -> None:
        manifest = self.install()
        self.assertFalse((self.config / "opencode-governance-runtime.json").exists())
        self.assertEqual("3.7.6", manifest["governance_version"])
        self.assertEqual("3.7.6", manifest["architect_runner_version"])
        self.assertEqual("3.7.6", manifest["context_intelligence_version"])
        self.assertEqual("3.7.6", manifest["workflow_continuation_version"])
        self.assertEqual("1.0", manifest["candidate_authority_version"])
        self.assertEqual("2.0", manifest["governed_memory_version"])
        self.assertEqual("1.0", manifest["evidence_reuse_version"])
        self.assertEqual("1.0", manifest["simulation_harness_version"])
        self.assertEqual("1.0", manifest["pre_commit_receipt_gate_version"])
        self.assertEqual(self.routing["settings"], manifest["settings"])
        self.assertEqual(self.routing["roles"], manifest["roles"])
        self.assertEqual(16, len(manifest["managed_tools"]))
        self.assertEqual(set(CAPABILITY_TOOLS), set(manifest["capability_tool_hashes"]))
        self.assertTrue(manifest["capability_section_hashes"])
        run("verify", "--config-dir", self.config)

    def test_verify_rejects_managed_section_drift(self) -> None:
        self.install()
        path = self.config / "agents" / "architect.md"
        path.write_text(path.read_text(encoding="utf-8").replace("GOVERNANCE_AUTHORITY_VERSION: 1", "GOVERNANCE_AUTHORITY_VERSION: drift"), encoding="utf-8")
        failure = run("verify", "--config-dir", self.config, ok=False)
        self.assertIn("CAPABILITY_SECTION_INTEGRITY_FAILURE", failure.stdout + failure.stderr)

    def test_uninstall_removes_only_capabilities_and_preserves_base(self) -> None:
        self.install()
        run("uninstall", "--config-dir", self.config)
        manifest = json.loads(self.manifest_path.read_text(encoding="utf-8"))
        self.assertEqual("3.4.4", manifest["governance_version"])
        self.assertEqual([str(self.tools / name) for name in BASE_TOOLS], manifest["managed_tools"])
        for name in CAPABILITY_TOOLS:
            self.assertFalse((self.tools / name).exists())
        for name in BASE_TOOLS:
            self.assertTrue((self.tools / name).exists())
        self.assertEqual("preserve", self.unrelated.read_text(encoding="utf-8"))
        self.assertNotIn("GOVERNANCE_AUTHORITY_V1", (self.config / "agents" / "architect.md").read_text(encoding="utf-8"))

    def test_install_is_idempotent(self) -> None:
        first = self.install()
        second = self.install()
        self.assertEqual(first["settings"], second["settings"])
        self.assertEqual(first["roles"], second["roles"])
        for name in AGENTS:
            text = (self.config / "agents" / f"{name}.md").read_text(encoding="utf-8")
            self.assertEqual(1, text.count("## GOVERNANCE_AUTHORITY_V1"))


if __name__ == "__main__":
    unittest.main()
