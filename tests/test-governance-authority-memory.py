#!/usr/bin/env python3
"""Cross-platform regressions for governance authority, memory and evidence reuse."""
from __future__ import annotations

import json
import pathlib
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
AUTHORITY = ROOT / "scripts" / "governance-authority.py"
MEMORY = ROOT / "scripts" / "governance-memory.py"
EVIDENCE = ROOT / "scripts" / "governance-evidence.py"
SIMULATION = ROOT / "scripts" / "governance-simulation.py"


def run(script: pathlib.Path, *arguments: object, ok: bool = True) -> subprocess.CompletedProcess[str]:
    process = subprocess.run(
        [sys.executable, str(script), *map(str, arguments)],
        text=True,
        capture_output=True,
    )
    if ok and process.returncode:
        raise AssertionError(f"{process.stdout}\n{process.stderr}")
    return process


class AuthorityTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.temporary.name)
        (self.root / ".ai").mkdir()
        subprocess.run(["git", "init", "-q"], cwd=self.root, check=True)
        subprocess.run(["git", "config", "user.email", "test@example.invalid"], cwd=self.root, check=True)
        subprocess.run(["git", "config", "user.name", "Test"], cwd=self.root, check=True)
        (self.root / "a.txt").write_text("alpha\n", encoding="utf-8")
        subprocess.run(["git", "add", "a.txt"], cwd=self.root, check=True)
        subprocess.run(["git", "commit", "-qm", "base"], cwd=self.root, check=True)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def test_staged_projection_ignores_unstaged_bytes(self) -> None:
        (self.root / "a.txt").write_text("staged\n", encoding="utf-8")
        subprocess.run(["git", "add", "a.txt"], cwd=self.root, check=True)
        first = self.root / ".ai" / "first.json"
        run(AUTHORITY, "candidate", "freeze", "--project-dir", self.root, "--projection", "staged", "--output", first)
        (self.root / "a.txt").write_text("unstaged divergence\n", encoding="utf-8")
        second = self.root / ".ai" / "second.json"
        run(AUTHORITY, "candidate", "freeze", "--project-dir", self.root, "--projection", "staged", "--output", second)
        self.assertEqual(json.loads(first.read_text())["candidate_identity"], json.loads(second.read_text())["candidate_identity"])

    def test_workspace_receipt_detects_drift(self) -> None:
        candidate = self.root / ".ai" / "candidate.json"
        run(AUTHORITY, "candidate", "freeze", "--project-dir", self.root, "--projection", "workspace", "--output", candidate)
        bindings = {field: "a" * 64 for field in (
            "approved_requirements_hash",
            "execution_packet_hash",
            "verification_profile_hash",
            "evidence_manifest_hash",
            "implementation_review_hash",
            "architecture_review_hash",
            "final_adjudication_hash",
        )}
        bindings.update(
            task_id="T1",
            actual_model_families=["family-a", "family-b", "family-c"],
            reviewer_independence="PASS",
            final_verdict="PASS",
        )
        binding_path = self.root / ".ai" / "bindings.json"
        binding_path.write_text(json.dumps(bindings), encoding="utf-8")
        receipt = self.root / ".ai" / "receipt.json"
        run(AUTHORITY, "receipt", "issue", "--candidate", candidate, "--bindings", binding_path, "--output", receipt)
        self.assertIn("RECEIPT_VALID", run(AUTHORITY, "receipt", "validate", "--receipt", receipt, "--project-dir", self.root, "--gate", "pre-commit").stdout)
        (self.root / "a.txt").write_text("drift\n", encoding="utf-8")
        failure = run(AUTHORITY, "receipt", "validate", "--receipt", receipt, "--project-dir", self.root, "--gate", "pre-commit", ok=False)
        self.assertIn("APPROVAL_RECEIPT_MISMATCH", failure.stdout + failure.stderr)

    def test_receipt_rejects_family_conflict(self) -> None:
        candidate = self.root / ".ai" / "candidate.json"
        run(AUTHORITY, "candidate", "freeze", "--project-dir", self.root, "--projection", "commit", "--ref", "HEAD", "--output", candidate)
        bindings = {field: "b" * 64 for field in (
            "approved_requirements_hash",
            "execution_packet_hash",
            "verification_profile_hash",
            "evidence_manifest_hash",
            "implementation_review_hash",
            "architecture_review_hash",
            "final_adjudication_hash",
        )}
        bindings.update(task_id="T2", actual_model_families=["same", "same"], reviewer_independence="PASS", final_verdict="PASS")
        path = self.root / ".ai" / "bindings.json"
        path.write_text(json.dumps(bindings), encoding="utf-8")
        failure = run(AUTHORITY, "receipt", "issue", "--candidate", candidate, "--bindings", path, "--output", self.root / ".ai" / "receipt.json", ok=False)
        self.assertIn("MODEL_INDEPENDENCE_CONFLICT", failure.stdout + failure.stderr)

    def test_actionable_continuation_rejects_narrative_retry(self) -> None:
        state = self.root / ".ai" / "RUN_STATE.json"
        state.write_text(json.dumps({
            "top_level_command": "ai-workflow",
            "current_phase": "TASK_REVIEW",
            "next_required_phase": "PRODUCT_COMPLETENESS_RECONCILIATION",
            "terminal_reason": None,
            "next_action": {
                "kind": "execute",
                "command": "/ai-resume",
                "arguments": ["T1"],
                "expected_postcondition": "PRODUCT_COMPLETENESS_RECONCILIATION",
            },
        }), encoding="utf-8")
        self.assertIn("ACTIONABLE_CONTINUATION_VALID", run(AUTHORITY, "continuation", "validate", "--run-state", state).stdout)
        changed = json.loads(state.read_text())
        changed["next_action"]["command"] = "try again"
        state.write_text(json.dumps(changed), encoding="utf-8")
        failure = run(AUTHORITY, "continuation", "validate", "--run-state", state, ok=False)
        self.assertIn("NON_EXECUTABLE_CONTINUATION", failure.stdout + failure.stderr)

    def test_lenses_derive_from_risk(self) -> None:
        risk = self.root / ".ai" / "risk.json"
        risk.write_text(json.dumps({"SECURITY": "HIGH", "PUBLIC_CONTRACT": "HIGH"}), encoding="utf-8")
        result = json.loads(run(AUTHORITY, "lenses", "derive", "--risk-profile", risk).stdout)
        self.assertIn("AUTHORIZATION", result["architecture_security"])
        self.assertIn("PUBLIC_CONTRACT", result["architecture_security"])
        self.assertIn("CORRECTNESS", result["implementation"])


class MemoryAndEvidenceTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.temporary.name)
        self.database = self.root / "memory.db"
        run(MEMORY, "init", "--db", self.database)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def propose(self, task_id: str) -> str:
        result = run(
            MEMORY,
            "propose",
            "--db", self.database,
            "--project-id", "p1",
            "--task-id", task_id,
            "--topic-key", "architecture/auth-model",
            "--type", "ARCHITECTURE_DECISION",
            "--title", "Auth model",
            "--lesson", "What: scoped auth\nWhy: least privilege\nWhere: auth\nLearned: reject implicit admin",
            "--candidate-hash", "a" * 64,
            "--evidence-hash", "b" * 64,
        )
        return json.loads(result.stdout)["memory_id"]

    def test_memory_requires_final_reviewer_approval(self) -> None:
        memory_id = self.propose("T1")
        failure = run(MEMORY, "adjudicate", "--db", self.database, "--memory-id", memory_id, "--decision", "APPROVE", "--final-review-hash", "bad", ok=False)
        self.assertIn("INVALID_HASH", failure.stdout + failure.stderr)
        compact = json.loads(run(MEMORY, "search", "--db", self.database, "--project-id", "p1", "--query", "auth").stdout)
        self.assertEqual("CANDIDATE", compact["results"][0]["status"])

    def test_progressive_disclosure_and_supersession(self) -> None:
        first = self.propose("T1")
        run(MEMORY, "adjudicate", "--db", self.database, "--memory-id", first, "--decision", "APPROVE", "--final-review-hash", "c" * 64)
        second = self.propose("T2")
        run(MEMORY, "adjudicate", "--db", self.database, "--memory-id", second, "--decision", "APPROVE", "--final-review-hash", "d" * 64)
        compact = json.loads(run(MEMORY, "search", "--db", self.database, "--project-id", "p1", "--query", "auth").stdout)
        self.assertNotIn("lesson", compact["results"][0])
        self.assertEqual("SUPERSEDED", json.loads(run(MEMORY, "get", "--db", self.database, "--memory-id", first).stdout)["status"])
        self.assertEqual(first, json.loads(run(MEMORY, "get", "--db", self.database, "--memory-id", second).stdout)["supersedes"])

    def test_policy_promotion_requires_recurrence_and_owner(self) -> None:
        first = self.propose("T1")
        run(MEMORY, "adjudicate", "--db", self.database, "--memory-id", first, "--decision", "APPROVE", "--final-review-hash", "c" * 64)
        denied = run(MEMORY, "promote-policy", "--db", self.database, "--project-id", "p1", "--topic-key", "architecture/auth-model", "--severity", "REQUIRE", "--owner-authorized", "false", ok=False)
        self.assertIn("OWNER_AUTHORIZATION_REQUIRED", denied.stdout + denied.stderr)
        second = self.propose("T2")
        run(MEMORY, "adjudicate", "--db", self.database, "--memory-id", second, "--decision", "APPROVE", "--final-review-hash", "d" * 64)
        policy = json.loads(run(MEMORY, "promote-policy", "--db", self.database, "--project-id", "p1", "--topic-key", "architecture/auth-model", "--severity", "REQUIRE", "--owner-authorized", "true").stdout)
        self.assertEqual("ACTIVE_PROJECT_RULE", policy["status"])

    def test_evidence_reuse_invalidates_exact_dependency_change(self) -> None:
        dependencies = self.root / "dependencies.json"
        dependencies.write_text(json.dumps({"source_tree": "a" * 64, "test_command": "b" * 64, "toolchain": "c" * 64, "policies": "d" * 64}), encoding="utf-8")
        record = self.root / "record.json"
        run(EVIDENCE, "record", "--task-id", "T1", "--evidence-type", "TEST", "--outcome", "PASS", "--dependencies", dependencies, "--output", record)
        self.assertIn("EVIDENCE_REUSABLE", run(EVIDENCE, "validate", "--record", record, "--dependencies", dependencies).stdout)
        changed = json.loads(dependencies.read_text())
        changed["policies"] = "e" * 64
        dependencies.write_text(json.dumps(changed), encoding="utf-8")
        failure = run(EVIDENCE, "validate", "--record", record, "--dependencies", dependencies, ok=False)
        self.assertIn("EVIDENCE_STALE", failure.stdout + failure.stderr)


class SimulationTests(unittest.TestCase):
    def test_twelve_command_scenario_and_external_action_boundary(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = pathlib.Path(temporary) / "scenario.json"
            path.write_text(json.dumps({
                "name": "all-commands",
                "request": "exercise governance",
                "covers_commands": sorted({
                    "ai-init", "ai-audit", "ai-docs", "ai-discover", "ai-plan", "ai-execute",
                    "ai-review", "ai-workflow", "ai-status", "ai-resume", "ai-metrics", "ai-release",
                }),
                "steps": [{"tool": "bash", "arguments": {"command": "/ai-status"}}, {"assistant_text": "LOCAL_COMMITTED"}],
                "terminal": "LOCAL_COMMITTED",
            }), encoding="utf-8")
            result = json.loads(run(SIMULATION, "validate", "--scenario", path).stdout)
            self.assertEqual(12, result["covered_command_count"])
            scenario = json.loads(path.read_text())
            scenario["steps"] = [{"tool": "bash", "arguments": {"command": "git push origin main"}}]
            path.write_text(json.dumps(scenario), encoding="utf-8")
            failure = run(SIMULATION, "validate", "--scenario", path, ok=False)
            self.assertIn("FORBIDDEN_EXTERNAL_ACTION", failure.stdout + failure.stderr)


if __name__ == "__main__":
    unittest.main()
