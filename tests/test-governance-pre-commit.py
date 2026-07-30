#!/usr/bin/env python3
"""Cross-platform regressions for the staged approval-receipt Git gate."""
from __future__ import annotations

import json
import pathlib
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
AUTHORITY = ROOT / "scripts" / "governance-authority.py"
GATE = ROOT / "scripts" / "governance-pre-commit.py"
HASH_FIELDS = (
    "approved_requirements_hash",
    "execution_packet_hash",
    "verification_profile_hash",
    "evidence_manifest_hash",
    "implementation_review_hash",
    "architecture_review_hash",
    "final_adjudication_hash",
)


def run(script: pathlib.Path, *arguments: object, ok: bool = True) -> subprocess.CompletedProcess[str]:
    process = subprocess.run(
        [sys.executable, str(script), *map(str, arguments)],
        text=True,
        capture_output=True,
    )
    if ok and process.returncode:
        raise AssertionError(process.stdout + process.stderr)
    return process


class PreCommitGateTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.temporary.name)
        (self.root / ".ai").mkdir()
        subprocess.run(["git", "init", "-q"], cwd=self.root, check=True)
        subprocess.run(["git", "config", "user.email", "test@example.invalid"], cwd=self.root, check=True)
        subprocess.run(["git", "config", "user.name", "Test"], cwd=self.root, check=True)
        (self.root / "app.txt").write_text("base\n", encoding="utf-8")
        subprocess.run(["git", "add", "app.txt"], cwd=self.root, check=True)
        subprocess.run(["git", "commit", "-qm", "base"], cwd=self.root, check=True)
        (self.root / "app.txt").write_text("approved\n", encoding="utf-8")
        subprocess.run(["git", "add", "app.txt"], cwd=self.root, check=True)
        self.receipt = self.root / ".ai" / "approval-receipt.json"
        candidate = self.root / ".ai" / "candidate.json"
        bindings = self.root / ".ai" / "bindings.json"
        run(AUTHORITY, "candidate", "freeze", "--project-dir", self.root, "--projection", "staged", "--output", candidate)
        values = {field: "a" * 64 for field in HASH_FIELDS}
        values.update(
            task_id="T-PRECOMMIT",
            actual_model_families=["implementation-family", "architecture-family", "final-family"],
            reviewer_independence="PASS",
            final_verdict="PASS",
        )
        bindings.write_text(json.dumps(values), encoding="utf-8")
        run(AUTHORITY, "receipt", "issue", "--candidate", candidate, "--bindings", bindings, "--output", self.receipt)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def test_install_arm_and_validate_exact_index(self) -> None:
        run(GATE, "install", "--project-dir", self.root)
        run(GATE, "arm", "--project-dir", self.root, "--receipt", self.receipt, "--authority-tool", AUTHORITY)
        result = run(GATE, "validate", "--project-dir", self.root)
        self.assertIn("RECEIPT_VALID", result.stdout)
        hook = pathlib.Path(subprocess.run(
            ["git", "rev-parse", "--git-path", "hooks/pre-commit"],
            cwd=self.root,
            check=True,
            text=True,
            capture_output=True,
        ).stdout.strip())
        hook = hook if hook.is_absolute() else self.root / hook
        self.assertIn("OPENCODE GOVERNANCE PRE-COMMIT START", hook.read_text())

    def test_index_drift_blocks_commit(self) -> None:
        run(GATE, "arm", "--project-dir", self.root, "--receipt", self.receipt, "--authority-tool", AUTHORITY)
        (self.root / "app.txt").write_text("different staged bytes\n", encoding="utf-8")
        subprocess.run(["git", "add", "app.txt"], cwd=self.root, check=True)
        failure = run(GATE, "validate", "--project-dir", self.root, ok=False)
        self.assertIn("APPROVAL_RECEIPT_MISMATCH", failure.stdout + failure.stderr)

    def test_install_and_uninstall_preserve_existing_hook(self) -> None:
        hook_value = subprocess.run(
            ["git", "rev-parse", "--git-path", "hooks/pre-commit"],
            cwd=self.root,
            check=True,
            text=True,
            capture_output=True,
        ).stdout.strip()
        hook = pathlib.Path(hook_value)
        hook = hook if hook.is_absolute() else self.root / hook
        hook.parent.mkdir(parents=True, exist_ok=True)
        hook.write_text("#!/usr/bin/env sh\necho owner-hook\n", encoding="utf-8")
        run(GATE, "install", "--project-dir", self.root)
        run(GATE, "install", "--project-dir", self.root)
        self.assertEqual(1, hook.read_text().count("OPENCODE GOVERNANCE PRE-COMMIT START"))
        run(GATE, "uninstall", "--project-dir", self.root)
        text = hook.read_text()
        self.assertIn("echo owner-hook", text)
        self.assertNotIn("OPENCODE GOVERNANCE PRE-COMMIT", text)

    def test_arm_rejects_receipt_outside_ai(self) -> None:
        outside = self.root / "outside.json"
        outside.write_text(self.receipt.read_text(), encoding="utf-8")
        failure = run(GATE, "arm", "--project-dir", self.root, "--receipt", outside, "--authority-tool", AUTHORITY, ok=False)
        self.assertIn("RECEIPT_OUTSIDE_GOVERNANCE_STATE", failure.stdout + failure.stderr)


if __name__ == "__main__":
    unittest.main()
