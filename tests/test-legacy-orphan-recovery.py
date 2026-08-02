#!/usr/bin/env python3
"""3.7.6–3.7.7: evidence-bound legacy orphan recovery + Windows V1 forensic adapter."""
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
BUILDER_V2 = ROOT / "tests" / "fixtures" / "build-legacy-374-orphan-fixture.py"
BUILDER_V1 = ROOT / "tests" / "fixtures" / "build-legacy-windows-v1-forensic-fixture.py"
MODULE = ROOT / "scripts" / "legacy-architect-orphan-recovery.py"


def load_recovery():
    spec = importlib.util.spec_from_file_location("legacy_recovery", MODULE)
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(mod)
    return mod


def argparse_namespace(data: dict):
    return type("NS", (), data)()


class _RecoveryBase(unittest.TestCase):
    builder = BUILDER_V2
    prefix = "opencode-v376-legacy-"

    def setUp(self) -> None:
        self.mod = load_recovery()
        self.tmpdir = pathlib.Path(tempfile.mkdtemp(prefix=self.prefix))
        subprocess.run(
            [sys.executable, str(self.builder), str(self.tmpdir / "fixture")],
            check=True,
            capture_output=True,
        )
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
            "expected_allowlist": "",
            "expected_allowlist_hash": "",
            "expected_manifest_hash": "",
        }
        base.update(overrides)
        return argparse_namespace(base)

    def _rebuild(self, name: str = "rebuild") -> dict:
        fix = self.tmpdir / name
        if fix.exists():
            shutil.rmtree(fix)
        subprocess.run([sys.executable, str(self.builder), str(fix)], check=True, capture_output=True)
        return json.loads((fix / "SUMMARY.json").read_text(encoding="utf-8"))


class LegacyOrphanRecoveryV2Tests(_RecoveryBase):
    """Canonical CANONICAL_RECOVERY_EVIDENCE_V2 fixture (3.7.6 regressions)."""

    builder = BUILDER_V2
    prefix = "opencode-v376-v2-"

    def test_validate_only_no_mutation(self) -> None:
        s = self.summary
        before_meta = pathlib.Path(s["transaction_dir"], "meta.json").read_text(encoding="utf-8")
        before_status = pathlib.Path(s["workspace"], ".ai", "STATUS.md").read_text(encoding="utf-8")
        result = self.mod.run_recovery(self._args("validate-governance-only"))
        self.assertEqual(result["status"], "LEGACY_ORPHAN_RECOVERY_VALIDATED")
        self.assertEqual(result["source_evidence_format"], "CANONICAL_RECOVERY_EVIDENCE_V2")
        self.assertFalse(result["adoption_performed"])
        self.assertEqual(result["changeset"], "GOVERNANCE_ONLY_CHANGE")
        after_meta = pathlib.Path(s["transaction_dir"], "meta.json").read_text(encoding="utf-8")
        self.assertEqual(before_meta, after_meta)
        self.assertEqual(before_status, pathlib.Path(s["workspace"], ".ai", "STATUS.md").read_text(encoding="utf-8"))
        self.assertTrue(pathlib.Path(s["transaction_dir"]).is_dir())

    def test_adopt_writes_v2_receipt_and_archives(self) -> None:
        s = self._rebuild("adopt-fixture")
        cfg = self.tmpdir / "adopt-config"
        cfg.mkdir(exist_ok=True)
        result = self.mod.run_recovery(
            self._args(
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
        )
        self.assertTrue(result["adoption_performed"])
        self.assertEqual(result["status"], "ARCHITECT_RECOVERY_COMPLETE")
        self.assertFalse(pathlib.Path(s["transaction_dir"]).exists())
        receipt = pathlib.Path(result["receipt_path"])
        self.assertTrue(receipt.is_file())
        body = json.loads(receipt.read_text(encoding="utf-8"))
        self.assertEqual(body["schema"], "EVIDENCE_BOUND_RECOVERY_RECEIPT_V2")
        self.assertEqual(body["source_evidence_format"], "CANONICAL_RECOVERY_EVIDENCE_V2")
        self.assertEqual(body["evidence_bundle_sha256"], s["evidence_bundle_sha256"])
        self.assertEqual(body["next_command"], "/ai-execute")
        run_state = json.loads(
            (pathlib.Path(s["repository"]) / ".ai" / "tasks" / s["task_id"] / "RUN_STATE.json").read_text(encoding="utf-8")
        )
        self.assertEqual(run_state["state"], "READY_FOR_EXECUTION")
        self.assertTrue(pathlib.Path(result["archive_path"], "meta.json").is_file())

    def test_missing_evidence_path(self) -> None:
        with self.assertRaises(self.mod.RecoveryError) as ctx:
            self.mod.run_recovery(self._args("validate-governance-only", evidence_bundle=""))
        self.assertEqual(ctx.exception.code, "EVIDENCE_BUNDLE_PATH_REQUIRED")

    def test_missing_evidence_hash(self) -> None:
        with self.assertRaises(self.mod.RecoveryError) as ctx:
            self.mod.run_recovery(self._args("validate-governance-only", expected_evidence_bundle_hash=""))
        self.assertEqual(ctx.exception.code, "EVIDENCE_BUNDLE_HASH_REQUIRED")

    def test_wrong_bundle_hash(self) -> None:
        with self.assertRaises(self.mod.RecoveryError) as ctx:
            self.mod.run_recovery(self._args("validate-governance-only", expected_evidence_bundle_hash="ab" * 32))
        self.assertEqual(ctx.exception.code, "EVIDENCE_BUNDLE_HASH_MISMATCH")

    def test_tx_hash_mismatch(self) -> None:
        with self.assertRaises(self.mod.RecoveryError) as ctx:
            self.mod.run_recovery(self._args("validate-governance-only", expected_transaction_hash="cd" * 32))
        self.assertEqual(ctx.exception.code, "TRANSACTION_HASH_MISMATCH")

    def test_task_mismatch(self) -> None:
        with self.assertRaises(self.mod.RecoveryError) as ctx:
            self.mod.run_recovery(self._args("validate-governance-only", task_id="WRONG-TASK"))
        self.assertIn(ctx.exception.code, {"RECOVERY_TASK_MISMATCH", "TASK_ROOT_MISSING", "LEGACY_ALLOWLIST_DERIVATION_INCOMPLETE"})

    def test_head_mismatch(self) -> None:
        with self.assertRaises(self.mod.RecoveryError) as ctx:
            self.mod.run_recovery(self._args("validate-governance-only", expected_repository_head="0" * 40))
        self.assertEqual(ctx.exception.code, "REPOSITORY_HEAD_MISMATCH")

    def test_plan_hash_mismatch(self) -> None:
        with self.assertRaises(self.mod.RecoveryError) as ctx:
            self.mod.run_recovery(self._args("validate-governance-only", expected_plan_hash="11" * 32))
        self.assertEqual(ctx.exception.code, "PLAN_HASH_MISMATCH")

    def test_packet_hash_mismatch(self) -> None:
        with self.assertRaises(self.mod.RecoveryError) as ctx:
            self.mod.run_recovery(self._args("validate-governance-only", expected_execution_packet_hash="22" * 32))
        self.assertEqual(ctx.exception.code, "EXECUTION_PACKET_HASH_MISMATCH")

    def test_checkpoint_hash_mismatch(self) -> None:
        with self.assertRaises(self.mod.RecoveryError) as ctx:
            self.mod.run_recovery(self._args("validate-governance-only", expected_checkpoint_hash="33" * 32))
        self.assertEqual(ctx.exception.code, "CHECKPOINT_HASH_MISMATCH")

    def test_stdout_hash_mismatch(self) -> None:
        with self.assertRaises(self.mod.RecoveryError) as ctx:
            self.mod.run_recovery(self._args("validate-governance-only", expected_stdout_hash="aa" * 32))
        self.assertEqual(ctx.exception.code, "STDOUT_HASH_MISMATCH")

    def test_source_mutation_blocks(self) -> None:
        s = self._rebuild("mut-fixture")
        (pathlib.Path(s["repository"]) / "app" / "file.php").write_text("<?php // mutated\n", encoding="utf-8")
        with self.assertRaises(self.mod.RecoveryError) as ctx:
            self.mod.run_recovery(
                self._args(
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
            )
        self.assertIn(ctx.exception.code, {"WORKSPACE_INVENTORY_DRIFT", "GIT_WORKING_TREE_DIRTY"})

    def test_unrelated_ai_mutation_blocks(self) -> None:
        s = self._rebuild("unreg-fixture")
        other = pathlib.Path(s["workspace"]) / "vendor_pkg" / ".ai"
        other.mkdir(parents=True)
        (other / "x.md").write_text("nope\n", encoding="utf-8")
        with self.assertRaises(self.mod.RecoveryError) as ctx:
            self.mod.run_recovery(
                self._args(
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
            )
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
        bad = self.tmpdir / "tampered.zip"
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

    def test_classify_legacy(self) -> None:
        meta = json.loads(pathlib.Path(self.summary["transaction_dir"], "meta.json").read_text(encoding="utf-8"))
        self.assertEqual(self.mod.classify_transaction(meta), "legacy")

    def test_v2_parser_rejects_legacy_three_column_row(self) -> None:
        p = self.tmpdir / "bad-man.txt"
        p.write_text("attempt/stdout.log\t12\tab" * 0 + "attempt/stdout.log\t12\t" + "ab" * 32 + "\n", encoding="utf-8")
        with self.assertRaises(self.mod.RecoveryError) as ctx:
            self.mod.parse_manifest_v2(p)
        self.assertEqual(ctx.exception.code, "MANIFEST_V2_LEGACY_ROW")


class LegacyWindowsV1ForensicTests(_RecoveryBase):
    """LEGACY_PROJECT_STATE_FORENSICS_V1 Windows collector fixture (3.7.7)."""

    builder = BUILDER_V1
    prefix = "opencode-v377-v1-"

    def test_v1_validate_lifecycle(self) -> None:
        s = self.summary
        bundle_before = self.mod.sha256_file(pathlib.Path(s["evidence_bundle"]))
        before_meta = pathlib.Path(s["transaction_dir"], "meta.json").read_bytes()
        before_status = pathlib.Path(s["workspace"], ".ai", "STATUS.md").read_text(encoding="utf-8")
        result = self.mod.run_recovery(self._args("validate-governance-only"))
        self.assertEqual(result["status"], "LEGACY_ORPHAN_RECOVERY_VALIDATED")
        self.assertEqual(result["source_evidence_format"], "LEGACY_PROJECT_STATE_FORENSICS_V1")
        self.assertEqual(result["adapter_contract"], "LEGACY_FORENSIC_BUNDLE_V1_ADAPTER")
        self.assertEqual(result["changeset"], "GOVERNANCE_ONLY_CHANGE")
        self.assertFalse(result["application_source_changed"])
        self.assertFalse(result["adoption_performed"])
        self.assertEqual(result["next_command"], "/ai-execute")
        self.assertEqual(result["source_evidence_bundle_sha256"], s["evidence_bundle_sha256"])
        self.assertEqual(result["source_evidence_manifest_sha256"], s["evidence_manifest_sha256"])
        # original archive + transaction + governance unchanged
        self.assertEqual(self.mod.sha256_file(pathlib.Path(s["evidence_bundle"])), bundle_before)
        self.assertEqual(pathlib.Path(s["transaction_dir"], "meta.json").read_bytes(), before_meta)
        self.assertEqual(pathlib.Path(s["workspace"], ".ai", "STATUS.md").read_text(encoding="utf-8"), before_status)
        self.assertTrue(pathlib.Path(s["transaction_dir"]).is_dir())
        # no final recovery receipt on validate
        rec_dir = pathlib.Path(s["workspace"]) / ".ai" / "recovery"
        if rec_dir.is_dir():
            self.assertEqual(list(rec_dir.glob("EVIDENCE_BOUND_RECOVERY_*.json")), [])

    def test_v1_adopt_lifecycle(self) -> None:
        s = self._rebuild("adopt-v1")
        cfg = self.tmpdir / "adopt-cfg"
        cfg.mkdir(exist_ok=True)
        bundle_before = self.mod.sha256_file(pathlib.Path(s["evidence_bundle"]))
        result = self.mod.run_recovery(
            self._args(
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
        )
        self.assertEqual(result["status"], "ARCHITECT_RECOVERY_COMPLETE")
        self.assertTrue(result["adoption_performed"])
        self.assertFalse(pathlib.Path(s["transaction_dir"]).exists())
        self.assertEqual(self.mod.sha256_file(pathlib.Path(s["evidence_bundle"])), bundle_before)
        body = json.loads(pathlib.Path(result["receipt_path"]).read_text(encoding="utf-8"))
        self.assertEqual(body["schema"], "EVIDENCE_BOUND_RECOVERY_RECEIPT_V2")
        self.assertEqual(body["source_evidence_format"], "LEGACY_PROJECT_STATE_FORENSICS_V1")
        self.assertEqual(body["adapter_contract"], "LEGACY_FORENSIC_BUNDLE_V1_ADAPTER")
        self.assertEqual(body["source_evidence_bundle_sha256"], s["evidence_bundle_sha256"])
        self.assertEqual(body["source_evidence_manifest_sha256"], s["evidence_manifest_sha256"])
        self.assertTrue(body.get("allowlist_derivation_method"))
        self.assertTrue(body.get("canonicalization_receipt_sha256"))
        self.assertEqual(body["next_command"], "/ai-execute")
        run_state = json.loads(
            (pathlib.Path(s["repository"]) / ".ai" / "tasks" / s["task_id"] / "RUN_STATE.json").read_text(encoding="utf-8")
        )
        self.assertEqual(run_state["state"], "READY_FOR_EXECUTION")
        self.assertTrue(pathlib.Path(result["archive_path"], "meta.json").is_file())

    def test_unknown_legacy_header(self) -> None:
        p = self.tmpdir / "man.txt"
        p.write_text("UNKNOWN HEADER LINE\nCREATED_AT: x\nFILES:\na\t1\t" + "ab" * 32 + "\n", encoding="utf-8")
        with self.assertRaises(self.mod.RecoveryError) as ctx:
            self.mod.parse_manifest_v1(p)
        self.assertEqual(ctx.exception.code, "LEGACY_MANIFEST_UNKNOWN_HEADER")

    def test_missing_files_header(self) -> None:
        p = self.tmpdir / "man2.txt"
        # Headers only — no FILES: section at all
        p.write_text("TOR-004 PROJECT STATE CHANGED FORENSICS\nCREATED_AT: 2026-08-01T12:00:00Z\n", encoding="utf-8")
        with self.assertRaises(self.mod.RecoveryError) as ctx:
            self.mod.parse_manifest_v1(p)
        self.assertEqual(ctx.exception.code, "LEGACY_MANIFEST_MISSING_FILES_HEADER")

    def test_malformed_three_column_row(self) -> None:
        p = self.tmpdir / "man3.txt"
        p.write_text(
            "TOR-004 PROJECT STATE CHANGED FORENSICS\nCREATED_AT: x\nFILES:\nonly-two\tfields\n",
            encoding="utf-8",
        )
        with self.assertRaises(self.mod.RecoveryError) as ctx:
            self.mod.parse_manifest_v1(p)
        self.assertEqual(ctx.exception.code, "LEGACY_MANIFEST_ROW_MALFORMED")

    def test_incorrect_recorded_size(self) -> None:
        s = self.summary
        src = self.tmpdir / "fixture" / "bundle-src"
        man = (src / "MANIFEST.txt").read_text(encoding="utf-8")
        # Flip a size digit on first file row after FILES:
        lines = man.splitlines()
        for i, line in enumerate(lines):
            if "\t" in line and line.count("\t") == 2:
                parts = line.split("\t")
                parts[1] = str(int(parts[1]) + 1)
                lines[i] = "\t".join(parts)
                break
        (src / "MANIFEST.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
        bad = self.tmpdir / "size-bad.zip"
        with zipfile.ZipFile(bad, "w") as zf:
            for path in sorted(src.rglob("*")):
                if path.is_file():
                    zf.write(path, path.relative_to(src).as_posix())
        with self.assertRaises(self.mod.RecoveryError) as ctx:
            self.mod.open_evidence_bundle(
                bad,
                self.mod.sha256_file(bad),
                workspace=pathlib.Path(s["workspace"]),
                repository=pathlib.Path(s["repository"]),
                task_id=s["task_id"],
            )
        self.assertEqual(ctx.exception.code, "MANIFEST_SIZE_MISMATCH")

    def test_incorrect_recorded_hash(self) -> None:
        s = self.summary
        src = self.tmpdir / "fixture" / "bundle-src"
        man = (src / "MANIFEST.txt").read_text(encoding="utf-8")
        # corrupt a digest
        for dig in [s["stdout_sha256"], s["transaction_meta_sha256"]]:
            if dig in man:
                man = man.replace(dig, "ff" * 32)
                break
        (src / "MANIFEST.txt").write_text(man, encoding="utf-8")
        bad = self.tmpdir / "hash-bad.zip"
        with zipfile.ZipFile(bad, "w") as zf:
            for path in sorted(src.rglob("*")):
                if path.is_file():
                    zf.write(path, path.relative_to(src).as_posix())
        with self.assertRaises(self.mod.RecoveryError) as ctx:
            self.mod.open_evidence_bundle(
                bad,
                self.mod.sha256_file(bad),
                workspace=pathlib.Path(s["workspace"]),
                repository=pathlib.Path(s["repository"]),
                task_id=s["task_id"],
            )
        self.assertEqual(ctx.exception.code, "MANIFEST_HASH_MISMATCH")

    def test_duplicate_manifest_path(self) -> None:
        p = self.tmpdir / "dup.txt"
        dig = "ab" * 32
        p.write_text(
            f"TOR-004 PROJECT STATE CHANGED FORENSICS\nCREATED_AT: x\nFILES:\na.txt\t1\t{dig}\na.txt\t1\t{dig}\n",
            encoding="utf-8",
        )
        with self.assertRaises(self.mod.RecoveryError) as ctx:
            self.mod.parse_manifest_v1(p)
        self.assertEqual(ctx.exception.code, "MANIFEST_DUPLICATE_PATH")

    def test_unlisted_zip_entry(self) -> None:
        s = self.summary
        src = self.tmpdir / "fixture" / "bundle-src"
        (src / "sneaky.txt").write_text("x\n", encoding="utf-8")
        bad = self.tmpdir / "unlisted.zip"
        with zipfile.ZipFile(bad, "w") as zf:
            for path in sorted(src.rglob("*")):
                if path.is_file():
                    zf.write(path, path.relative_to(src).as_posix())
        with self.assertRaises(self.mod.RecoveryError) as ctx:
            self.mod.open_evidence_bundle(
                bad,
                self.mod.sha256_file(bad),
                workspace=pathlib.Path(s["workspace"]),
                repository=pathlib.Path(s["repository"]),
                task_id=s["task_id"],
            )
        self.assertEqual(ctx.exception.code, "MANIFEST_UNLISTED_ENTRY")

    def test_backslash_traversal_path(self) -> None:
        p = self.tmpdir / "trav.txt"
        dig = "ab" * 32
        p.write_text(
            f"TOR-004 PROJECT STATE CHANGED FORENSICS\nCREATED_AT: x\nFILES:\n..\\evil.txt\t1\t{dig}\n",
            encoding="utf-8",
        )
        with self.assertRaises(self.mod.RecoveryError) as ctx:
            self.mod.parse_manifest_v1(p)
        self.assertEqual(ctx.exception.code, "MANIFEST_PATH_UNSAFE")

    def test_absolute_drive_path(self) -> None:
        p = self.tmpdir / "abs.txt"
        dig = "ab" * 32
        p.write_text(
            f"TOR-004 PROJECT STATE CHANGED FORENSICS\nCREATED_AT: x\nFILES:\nC:/Windows/x.txt\t1\t{dig}\n",
            encoding="utf-8",
        )
        with self.assertRaises(self.mod.RecoveryError) as ctx:
            self.mod.parse_manifest_v1(p)
        self.assertEqual(ctx.exception.code, "MANIFEST_PATH_UNSAFE")

    def test_symlink_zip_entry(self) -> None:
        bad = self.tmpdir / "sym.zip"
        # Create a zip with a symlink external_attr if possible
        import stat as st
        import zipfile as zfmod

        with zfmod.ZipFile(bad, "w") as zf:
            info = zfmod.ZipInfo("link.txt")
            info.create_system = 3
            info.external_attr = (st.S_IFLNK | 0o777) << 16
            zf.writestr(info, b"/tmp/target")
            zf.writestr("MANIFEST.txt", "x")
        with self.assertRaises(self.mod.RecoveryError) as ctx:
            self.mod.open_evidence_bundle(bad, self.mod.sha256_file(bad))
        self.assertIn(ctx.exception.code, {"ZIP_SYMLINK_FORBIDDEN", "ZIP_TRAVERSAL", "MANIFEST_MISSING", "EVIDENCE_FORMAT_UNKNOWN"})

    def test_missing_legacy_transaction_path(self) -> None:
        s = self.summary
        src = self.tmpdir / "fixture" / "bundle-src"
        meta = src / "orphaned-transaction" / "meta.json"
        if meta.is_file():
            meta.unlink()
        # rebuild manifest without the meta path
        man_lines = [
            "TOR-004 PROJECT STATE CHANGED FORENSICS",
            "CREATED_AT: 2026-08-01T12:00:00Z",
            "",
            "FILES:",
        ]
        for path in sorted(src.rglob("*")):
            if path.is_file() and path.name != "MANIFEST.txt":
                rel = path.relative_to(src).as_posix()
                man_lines.append(f"{rel}\t{path.stat().st_size}\t{self.mod.sha256_file(path)}")
        (src / "MANIFEST.txt").write_text("\n".join(man_lines) + "\n", encoding="utf-8")
        bad = self.tmpdir / "no-tx.zip"
        with zipfile.ZipFile(bad, "w") as zf:
            for path in sorted(src.rglob("*")):
                if path.is_file():
                    zf.write(path, path.relative_to(src).as_posix())
        with self.assertRaises(self.mod.RecoveryError) as ctx:
            self.mod.open_evidence_bundle(
                bad,
                self.mod.sha256_file(bad),
                workspace=pathlib.Path(s["workspace"]),
                repository=pathlib.Path(s["repository"]),
                task_id=s["task_id"],
            )
        self.assertIn(
            ctx.exception.code,
            {"LEGACY_TRANSACTION_META_MISSING", "EVIDENCE_FORMAT_UNKNOWN", "EVIDENCE_FORMAT_AMBIGUOUS"},
        )

    def test_missing_legacy_attempt_log(self) -> None:
        s = self.summary
        src = self.tmpdir / "fixture" / "bundle-src"
        stdout = src / "attempt-logs" / "attempt-1.stdout.log"
        if stdout.is_file():
            stdout.unlink()
        man_lines = [
            "TOR-004 PROJECT STATE CHANGED FORENSICS",
            "CREATED_AT: 2026-08-01T12:00:00Z",
            "",
            "FILES:",
        ]
        for path in sorted(src.rglob("*")):
            if path.is_file() and path.name != "MANIFEST.txt":
                rel = path.relative_to(src).as_posix()
                man_lines.append(f"{rel}\t{path.stat().st_size}\t{self.mod.sha256_file(path)}")
        (src / "MANIFEST.txt").write_text("\n".join(man_lines) + "\n", encoding="utf-8")
        bad = self.tmpdir / "no-stdout.zip"
        with zipfile.ZipFile(bad, "w") as zf:
            for path in sorted(src.rglob("*")):
                if path.is_file():
                    zf.write(path, path.relative_to(src).as_posix())
        with self.assertRaises(self.mod.RecoveryError) as ctx:
            self.mod.open_evidence_bundle(
                bad,
                self.mod.sha256_file(bad),
                workspace=pathlib.Path(s["workspace"]),
                repository=pathlib.Path(s["repository"]),
                task_id=s["task_id"],
            )
        self.assertIn(ctx.exception.code, {"LEGACY_ATTEMPT_STDOUT_MISSING", "EVIDENCE_FORMAT_UNKNOWN"})

    def test_malformed_tsv_header(self) -> None:
        p = self.tmpdir / "bad.tsv"
        p.write_text("WRONG\tHEADER\n", encoding="utf-8")
        with self.assertRaises(self.mod.RecoveryError) as ctx:
            self.mod.parse_tsv_inventory(p)
        self.assertEqual(ctx.exception.code, "TSV_HEADER_INVALID")

    def test_malformed_tsv_row(self) -> None:
        p = self.tmpdir / "badrow.tsv"
        hdr = "TYPE\tRELATIVE_PATH\tSIZE\tATTRIBUTES\tLAST_WRITE_UTC\tSHA256_OR_TARGET\n"
        p.write_text(hdr + "FILE\tonly\tthree\n", encoding="utf-8")
        with self.assertRaises(self.mod.RecoveryError) as ctx:
            self.mod.parse_tsv_inventory(p)
        self.assertEqual(ctx.exception.code, "TSV_ROW_MALFORMED")

    def test_duplicate_tsv_path(self) -> None:
        p = self.tmpdir / "dup.tsv"
        dig = "ab" * 32
        hdr = "TYPE\tRELATIVE_PATH\tSIZE\tATTRIBUTES\tLAST_WRITE_UTC\tSHA256_OR_TARGET\n"
        row = f"FILE\ta.txt\t1\tA\t2026-01-01T00:00:00Z\t{dig}\n"
        p.write_text(hdr + row + row, encoding="utf-8")
        with self.assertRaises(self.mod.RecoveryError) as ctx:
            self.mod.parse_tsv_inventory(p)
        self.assertEqual(ctx.exception.code, "TSV_DUPLICATE_PATH")

    def test_non_managed_inventory_drift(self) -> None:
        s = self._rebuild("drift-v1")
        (pathlib.Path(s["repository"]) / "app" / "file.php").write_text("<?php // drift\n", encoding="utf-8")
        with self.assertRaises(self.mod.RecoveryError) as ctx:
            self.mod.run_recovery(
                self._args(
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
            )
        self.assertIn(ctx.exception.code, {"WORKSPACE_INVENTORY_DRIFT", "GIT_WORKING_TREE_DIRTY"})

    def test_unsafe_link_in_non_managed_inventory(self) -> None:
        dig = "ab" * 32
        hdr = "TYPE\tRELATIVE_PATH\tSIZE\tATTRIBUTES\tLAST_WRITE_UTC\tSHA256_OR_TARGET\n"
        rows = [
            hdr.strip(),
            f"LINK\tapp/link\t0\tL\t2026-01-01T00:00:00Z\t/tmp/x",
            f"FILE\tapp/file.php\t1\tA\t2026-01-01T00:00:00Z\t{dig}",
        ]
        p = self.tmpdir / "link.tsv"
        p.write_text("\n".join(rows) + "\n", encoding="utf-8")
        rows_parsed = self.mod.parse_tsv_inventory(p)
        with self.assertRaises(self.mod.RecoveryError) as ctx:
            self.mod.tsv_to_workspace_files(rows_parsed, [".ai", "Source_Code/.ai"])
        self.assertEqual(ctx.exception.code, "TSV_LINK_IN_NON_MANAGED")

    def test_owner_allowlist_mismatch(self) -> None:
        s = self.summary
        allow = self.tmpdir / "owner-allow.json"
        allow.write_text(json.dumps({"paths": [".ai/STATUS.md"]}) + "\n", encoding="utf-8")
        with self.assertRaises(self.mod.RecoveryError) as ctx:
            self.mod.run_recovery(
                self._args(
                    "validate-governance-only",
                    expected_allowlist=str(allow),
                    expected_allowlist_hash=self.mod.sha256_file(allow),
                )
            )
        self.assertEqual(ctx.exception.code, "OWNER_ALLOWLIST_MISMATCH")

    def test_stdout_hash_mismatch_v1(self) -> None:
        with self.assertRaises(self.mod.RecoveryError) as ctx:
            self.mod.run_recovery(self._args("validate-governance-only", expected_stdout_hash="aa" * 32))
        self.assertEqual(ctx.exception.code, "STDOUT_HASH_MISMATCH")

    def test_application_source_drift(self) -> None:
        s = self._rebuild("app-drift")
        (pathlib.Path(s["repository"]) / "app" / "file.php").write_text("<?php // app drift\n", encoding="utf-8")
        with self.assertRaises(self.mod.RecoveryError) as ctx:
            self.mod.run_recovery(
                self._args(
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
            )
        self.assertIn(ctx.exception.code, {"WORKSPACE_INVENTORY_DRIFT", "GIT_WORKING_TREE_DIRTY"})

    def test_unrelated_nested_ai_drift(self) -> None:
        s = self._rebuild("nested-ai")
        other = pathlib.Path(s["workspace"]) / "vendor_pkg" / ".ai"
        other.mkdir(parents=True)
        (other / "x.md").write_text("nope\n", encoding="utf-8")
        with self.assertRaises(self.mod.RecoveryError) as ctx:
            self.mod.run_recovery(
                self._args(
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
            )
        self.assertEqual(ctx.exception.code, "WORKSPACE_INVENTORY_DRIFT")

    def test_adapter_temp_cleanup_on_success(self) -> None:
        # After validate, no opencode-gov-evidence-* or opencode-gov-canon-* should remain from this run.
        # We cannot assert global temp emptiness; assert working roots from open_evidence_bundle are cleaned by run_recovery.
        import tempfile as tf

        before = set(pathlib.Path(tf.gettempdir()).glob("opencode-gov-*"))
        self.mod.run_recovery(self._args("validate-governance-only"))
        after = set(pathlib.Path(tf.gettempdir()).glob("opencode-gov-*"))
        leaked = after - before
        # filter to dirs still present
        leaked = {p for p in leaked if p.exists()}
        self.assertEqual(leaked, set(), f"temp leak: {leaked}")

    def test_task_artifact_hash_mismatch(self) -> None:
        with self.assertRaises(self.mod.RecoveryError) as ctx:
            self.mod.run_recovery(self._args("validate-governance-only", expected_plan_hash="11" * 32))
        self.assertEqual(ctx.exception.code, "PLAN_HASH_MISMATCH")


if __name__ == "__main__":
    unittest.main()
