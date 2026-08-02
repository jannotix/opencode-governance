#!/usr/bin/env python3
"""3.7.6: evidence-bound legacy 3.7.4 orphan recovery regressions."""
from __future__ import annotations

import importlib.util
import json
import pathlib
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
BUILDER = ROOT / "tests" / "fixtures" / "build-legacy-374-orphan-fixture.py"
MODULE = ROOT / "scripts" / "legacy-architect-orphan-recovery.py"


def load_recovery():
    spec = importlib.util.spec_from_file_location("legacy_recovery", MODULE)
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(mod)
    return mod


class LegacyOrphanRecoveryTests(unittest.TestCase):
    def setUp(self) -> None:
        self.mod = load_recovery()
        self.tmpdir = pathlib.Path(tempfile.mkdtemp(prefix="opencode-v376-legacy-"))
        subprocess.run([sys.executable, str(BUILDER), str(self.tmpdir / "fixture")], check=True, capture_output=True)
        self.summary = json.loads((self.tmpdir / "fixture" / "SUMMARY.json").read_text(encoding="utf-8"))

    def tearDown(self) -> None:
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def _args(self, decision: str, **overrides):
        s = self.summary
        base = {
            "decision": decision,
            "workspace": s["workspace"],
            "repository": s["repository"],
            "task_id": s["task_id"],
            "transaction_dir": s["transaction_dir"],
            "config_dir": str(self.tmpdir / "config"),
            "evidence_bundle": s["evidence_bundle"],
            "expected_transaction_hash": s["transaction_meta_sha256"],
            "expected_evidence_bundle_hash": s["evidence_bundle_sha256"],
            "expected_repository_head": s["repository_head"],
            "expected_plan_hash": s["plan_sha256"],
            "expected_execution_packet_hash": s["execution_packet_sha256"],
            "expected_checkpoint_hash": s["checkpoint_sha256"],
            "expected_arguments_hash": s["arguments_sha256"],
            "expected_stdout_hash": s["stdout_sha256"],
            "expected_stderr_hash": s["stderr_sha256"],
            "expected_state": "READY_FOR_EXECUTION",
            "archive_dir": "",
            "keep_transaction": False,
            "expected_plan_id": "",
            "expected_packet_id": "",
            "json_result": False,
        }
        base.update(overrides)
        return argparse_namespace(base)

    def test_validate_only_no_mutation(self) -> None:
        s = self.summary
        before_meta = pathlib.Path(s["transaction_dir"], "meta.json").read_text(encoding="utf-8")
        before_status = pathlib.Path(s["workspace"], ".ai", "STATUS.md").read_text(encoding="utf-8")
        args = self._args("validate-governance-only")
        result = self.mod.run_recovery(args)
        self.assertEqual(result["status"], "LEGACY_ORPHAN_RECOVERY_VALIDATED")
        self.assertFalse(result["adoption_performed"])
        self.assertEqual(result["changeset"], "GOVERNANCE_ONLY_CHANGE")
        after_meta = pathlib.Path(s["transaction_dir"], "meta.json").read_text(encoding="utf-8")
        self.assertEqual(before_meta, after_meta)
        self.assertEqual(before_status, pathlib.Path(s["workspace"], ".ai", "STATUS.md").read_text(encoding="utf-8"))
        self.assertTrue(pathlib.Path(s["transaction_dir"]).is_dir())

    def test_adopt_writes_v2_receipt_and_archives(self) -> None:
        # rebuild clean fixture for adopt
        fix = self.tmpdir / "adopt-fixture"
        if fix.exists():
            shutil.rmtree(fix)
        subprocess.run([sys.executable, str(BUILDER), str(fix)], check=True, capture_output=True)
        s = json.loads((fix / "SUMMARY.json").read_text(encoding="utf-8"))
        cfg = self.tmpdir / "adopt-config"
        cfg.mkdir(exist_ok=True)
        args = self._args(
            "adopt-governance-only",
            workspace=s["workspace"],
            repository=s["repository"],
            task_id=s["task_id"],
            transaction_dir=s["transaction_dir"],
            config_dir=str(cfg),
            evidence_bundle=s["evidence_bundle"],
            expected_transaction_hash=s["transaction_meta_sha256"],
            expected_evidence_bundle_hash=s["evidence_bundle_sha256"],
            expected_repository_head=s["repository_head"],
            expected_plan_hash=s["plan_sha256"],
            expected_execution_packet_hash=s["execution_packet_sha256"],
            expected_checkpoint_hash=s["checkpoint_sha256"],
            expected_arguments_hash=s["arguments_sha256"],
            expected_stdout_hash=s["stdout_sha256"],
            expected_stderr_hash=s["stderr_sha256"],
        )
        result = self.mod.run_recovery(args)
        self.assertTrue(result["adoption_performed"])
        self.assertEqual(result["status"], "ARCHITECT_RECOVERY_COMPLETE")
        self.assertFalse(pathlib.Path(s["transaction_dir"]).exists())
        receipt = pathlib.Path(result["receipt_path"])
        self.assertTrue(receipt.is_file())
        body = json.loads(receipt.read_text(encoding="utf-8"))
        self.assertEqual(body["schema"], "EVIDENCE_BOUND_RECOVERY_RECEIPT_V2")
        self.assertEqual(body["decision"], "adopt-governance-only")
        self.assertEqual(body["transaction_meta_sha256"], s["transaction_meta_sha256"])
        self.assertEqual(body["evidence_bundle_sha256"], s["evidence_bundle_sha256"])
        self.assertEqual(body["changeset_classification"], "GOVERNANCE_ONLY_CHANGE")
        self.assertTrue(body["owner_authorized"])
        self.assertEqual(body["next_command"], "/ai-execute")
        # advanced state retained
        run_state = json.loads(
            (pathlib.Path(s["repository"]) / ".ai" / "tasks" / s["task_id"] / "RUN_STATE.json").read_text(encoding="utf-8")
        )
        self.assertEqual(run_state["state"], "READY_FOR_EXECUTION")
        self.assertTrue(pathlib.Path(result["archive_path"], "meta.json").is_file())

    def test_missing_evidence_path(self) -> None:
        args = self._args("validate-governance-only", evidence_bundle="")
        with self.assertRaises(self.mod.RecoveryError) as ctx:
            self.mod.run_recovery(args)
        self.assertEqual(ctx.exception.code, "EVIDENCE_BUNDLE_PATH_REQUIRED")

    def test_missing_evidence_hash(self) -> None:
        args = self._args("validate-governance-only", expected_evidence_bundle_hash="")
        with self.assertRaises(self.mod.RecoveryError) as ctx:
            self.mod.run_recovery(args)
        self.assertEqual(ctx.exception.code, "EVIDENCE_BUNDLE_HASH_REQUIRED")

    def test_wrong_bundle_hash(self) -> None:
        args = self._args("validate-governance-only", expected_evidence_bundle_hash="ab" * 32)
        with self.assertRaises(self.mod.RecoveryError) as ctx:
            self.mod.run_recovery(args)
        self.assertEqual(ctx.exception.code, "EVIDENCE_BUNDLE_HASH_MISMATCH")

    def test_tx_hash_mismatch(self) -> None:
        args = self._args("validate-governance-only", expected_transaction_hash="cd" * 32)
        with self.assertRaises(self.mod.RecoveryError) as ctx:
            self.mod.run_recovery(args)
        self.assertEqual(ctx.exception.code, "TRANSACTION_HASH_MISMATCH")

    def test_task_mismatch(self) -> None:
        args = self._args("validate-governance-only", task_id="WRONG-TASK")
        with self.assertRaises(self.mod.RecoveryError) as ctx:
            self.mod.run_recovery(args)
        self.assertIn(ctx.exception.code, {"RECOVERY_TASK_MISMATCH", "TASK_ROOT_MISSING"})

    def test_head_mismatch(self) -> None:
        args = self._args("validate-governance-only", expected_repository_head="0" * 40)
        with self.assertRaises(self.mod.RecoveryError) as ctx:
            self.mod.run_recovery(args)
        self.assertEqual(ctx.exception.code, "REPOSITORY_HEAD_MISMATCH")

    def test_plan_hash_mismatch(self) -> None:
        args = self._args("validate-governance-only", expected_plan_hash="11" * 32)
        with self.assertRaises(self.mod.RecoveryError) as ctx:
            self.mod.run_recovery(args)
        self.assertEqual(ctx.exception.code, "PLAN_HASH_MISMATCH")

    def test_packet_hash_mismatch(self) -> None:
        args = self._args("validate-governance-only", expected_execution_packet_hash="22" * 32)
        with self.assertRaises(self.mod.RecoveryError) as ctx:
            self.mod.run_recovery(args)
        self.assertEqual(ctx.exception.code, "EXECUTION_PACKET_HASH_MISMATCH")

    def test_checkpoint_hash_mismatch(self) -> None:
        args = self._args("validate-governance-only", expected_checkpoint_hash="33" * 32)
        with self.assertRaises(self.mod.RecoveryError) as ctx:
            self.mod.run_recovery(args)
        self.assertEqual(ctx.exception.code, "CHECKPOINT_HASH_MISMATCH")

    def test_source_mutation_blocks(self) -> None:
        fix = self.tmpdir / "mut-fixture"
        if fix.exists():
            shutil.rmtree(fix)
        subprocess.run([sys.executable, str(BUILDER), str(fix)], check=True, capture_output=True)
        s = json.loads((fix / "SUMMARY.json").read_text(encoding="utf-8"))
        app = pathlib.Path(s["repository"]) / "app" / "file.php"
        app.write_text("<?php // mutated\n", encoding="utf-8")
        args = self._args(
            "validate-governance-only",
            workspace=s["workspace"],
            repository=s["repository"],
            task_id=s["task_id"],
            transaction_dir=s["transaction_dir"],
            evidence_bundle=s["evidence_bundle"],
            expected_transaction_hash=s["transaction_meta_sha256"],
            expected_evidence_bundle_hash=s["evidence_bundle_sha256"],
            expected_repository_head=s["repository_head"],
            expected_plan_hash=s["plan_sha256"],
            expected_execution_packet_hash=s["execution_packet_sha256"],
            expected_checkpoint_hash=s["checkpoint_sha256"],
            expected_arguments_hash=s["arguments_sha256"],
            expected_stdout_hash=s["stdout_sha256"],
            expected_stderr_hash=s["stderr_sha256"],
        )
        with self.assertRaises(self.mod.RecoveryError) as ctx:
            self.mod.run_recovery(args)
        self.assertIn(ctx.exception.code, {"WORKSPACE_INVENTORY_DRIFT", "GIT_WORKING_TREE_DIRTY"})

    def test_unrelated_ai_mutation_blocks(self) -> None:
        fix = self.tmpdir / "unreg-fixture"
        if fix.exists():
            shutil.rmtree(fix)
        subprocess.run([sys.executable, str(BUILDER), str(fix)], check=True, capture_output=True)
        s = json.loads((fix / "SUMMARY.json").read_text(encoding="utf-8"))
        other = pathlib.Path(s["workspace"]) / "vendor_pkg" / ".ai"
        other.mkdir(parents=True)
        (other / "x.md").write_text("nope\n", encoding="utf-8")
        args = self._args(
            "validate-governance-only",
            workspace=s["workspace"],
            repository=s["repository"],
            task_id=s["task_id"],
            transaction_dir=s["transaction_dir"],
            evidence_bundle=s["evidence_bundle"],
            expected_transaction_hash=s["transaction_meta_sha256"],
            expected_evidence_bundle_hash=s["evidence_bundle_sha256"],
            expected_repository_head=s["repository_head"],
            expected_plan_hash=s["plan_sha256"],
            expected_execution_packet_hash=s["execution_packet_sha256"],
            expected_checkpoint_hash=s["checkpoint_sha256"],
            expected_arguments_hash=s["arguments_sha256"],
            expected_stdout_hash=s["stdout_sha256"],
            expected_stderr_hash=s["stderr_sha256"],
        )
        with self.assertRaises(self.mod.RecoveryError) as ctx:
            self.mod.run_recovery(args)
        self.assertEqual(ctx.exception.code, "WORKSPACE_INVENTORY_DRIFT")

    def test_zip_traversal_rejected(self) -> None:
        bad = self.tmpdir / "evil.zip"
        with zipfile.ZipFile(bad, "w") as zf:
            zf.writestr("../evil.txt", "x")
            zf.writestr("MANIFEST.txt", "x")
        with self.assertRaises(self.mod.RecoveryError) as ctx:
            self.mod.open_evidence_bundle(bad, self.mod.sha256_file(bad))
        self.assertEqual(ctx.exception.code, "ZIP_TRAVERSAL")

    def test_manifest_tamper_rejected(self) -> None:
        s = self.summary
        # copy zip, rewrite MANIFEST inside
        bad = self.tmpdir / "tampered.zip"
        shutil.copy2(s["evidence_bundle"], bad)
        # rebuild zip with wrong manifest hash line
        src = self.tmpdir / "fixture" / "bundle-src"
        man = (src / "MANIFEST.txt").read_text(encoding="utf-8")
        (src / "MANIFEST.txt").write_text(man.replace(s["stdout_sha256"], "ff" * 32), encoding="utf-8")
        with zipfile.ZipFile(bad, "w") as zf:
            for path in sorted(src.rglob("*")):
                if path.is_file():
                    zf.write(path, path.relative_to(src).as_posix())
        digest = self.mod.sha256_file(bad)
        with self.assertRaises(self.mod.RecoveryError) as ctx:
            self.mod.open_evidence_bundle(bad, digest)
        self.assertEqual(ctx.exception.code, "MANIFEST_HASH_MISMATCH")
    def test_stdout_hash_mismatch(self) -> None:
        args = self._args("validate-governance-only", expected_stdout_hash="aa" * 32)
        with self.assertRaises(self.mod.RecoveryError) as ctx:
            self.mod.run_recovery(args)
        self.assertEqual(ctx.exception.code, "STDOUT_HASH_MISMATCH")

    def test_classify_legacy(self) -> None:
        meta = json.loads(pathlib.Path(self.summary["transaction_dir"], "meta.json").read_text(encoding="utf-8"))
        self.assertEqual(self.mod.classify_transaction(meta), "legacy")


def argparse_namespace(data: dict):
    return type("NS", (), data)()


if __name__ == "__main__":
    unittest.main()
