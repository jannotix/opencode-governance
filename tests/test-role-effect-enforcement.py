#!/usr/bin/env python3
"""4.0.3 ROLE_EFFECT_ENFORCEMENT_V1_3 — installed plugin, shell/path/ingest negatives."""
from __future__ import annotations

import hashlib
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
PLUGIN_MJS = ROOT / "plugins" / "opencode-governance-effect-enforcement" / "index.mjs"
POLICY = ROOT / "governance-spec" / "effects" / "role-effect-policy.json"
INGEST = ROOT / "scripts" / "role-report-ingest.py"
INSTALLER = ROOT / "scripts" / "install-effect-plugin.py"


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


class EffectPluginUnitTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if not shutil.which("node"):
            raise unittest.SkipTest("node not available")
        cls.node = shutil.which("node")
        cls.plugin_url = PLUGIN_MJS.resolve().as_uri()

    def _run_enforce(self, role: str, tool: str, args: dict, env_extra: dict | None = None, active: bool = True) -> subprocess.CompletedProcess[str]:
        script = f"""
import Plugin from {json.dumps(self.plugin_url)};
const enforce = Plugin._enforce;
const loadPolicy = Plugin._loadPolicy;
const policy = loadPolicy();
const input = {{ tool: {json.dumps(tool)} }};
const output = {{ args: {json.dumps(args)} }};
try {{
  const r = enforce(policy, input, output);
  console.log(JSON.stringify({{status: r && r.status === 'INACTIVE' ? 'INACTIVE' : 'ALLOW', detail: r}}));
  process.exit(0);
}} catch (e) {{
  console.log(JSON.stringify({{status:'DENY', error: String(e.message || e)}}));
  process.exit(2);
}}
"""
        env = dict(os.environ)
        if active:
            env["OPENCODE_GOVERNANCE_EFFECT_ENFORCEMENT_ACTIVE"] = "1"
            env["OPENCODE_GOVERNANCE_ROLE"] = role
        else:
            env.pop("OPENCODE_GOVERNANCE_EFFECT_ENFORCEMENT_ACTIVE", None)
            env.pop("OPENCODE_GOVERNANCE_ROLE", None)
        env["OPENCODE_GOVERNANCE_EFFECT_POLICY"] = str(POLICY)
        if env_extra:
            env.update(env_extra)
        return subprocess.run(
            [self.node, "--input-type=module", "-e", script],
            capture_output=True,
            text=True,
            env=env,
        )

    def test_policy_schema_v1_1(self) -> None:
        body = json.loads(POLICY.read_text(encoding="utf-8"))
        self.assertEqual(body["schema"], "ROLE_EFFECT_ENFORCEMENT_V1_2")
        self.assertEqual(body["governance_version"], "4.0.4")

    def test_export_contract(self) -> None:
        r = subprocess.run(
            [
                self.node,
                "--input-type=module",
                "-e",
                f"import Plugin from {json.dumps(self.plugin_url)}; "
                f"console.log(JSON.stringify({{HOOK:Plugin.HOOK, SCHEMA:Plugin.SCHEMA, PLUGIN_ID:Plugin.PLUGIN_ID, PLUGIN_EXPORT_CONTRACT:Plugin.PLUGIN_EXPORT_CONTRACT}}));",
            ],
            capture_output=True,
            text=True,
            check=True,
        )
        data = json.loads(r.stdout.strip())
        self.assertEqual(data["HOOK"], "tool.execute.before")
        self.assertEqual(data["SCHEMA"], "ROLE_EFFECT_ENFORCEMENT_V1_3")
        self.assertIn("named_async", data["PLUGIN_EXPORT_CONTRACT"])

    def test_inactive_passthrough(self) -> None:
        r = self._run_enforce("architect", "edit", {"filePath": "src/x.js"}, active=False)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("INACTIVE", r.stdout)

    def test_reviewer_bash_denied(self) -> None:
        r = self._run_enforce("reviewer", "bash", {"command": "echo hi"})
        self.assertEqual(r.returncode, 2)

    def test_reviewer_edit_denied(self) -> None:
        r = self._run_enforce("reviewer", "edit", {"filePath": "src/app.php"})
        self.assertEqual(r.returncode, 2)

    def test_architect_source_write_denied(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            ws = pathlib.Path(td)
            (ws / ".ai").mkdir()
            r = self._run_enforce(
                "architect",
                "edit",
                {"filePath": str(ws / "Source_Code" / "app.php")},
                env_extra={
                    "OPENCODE_GOVERNANCE_WORKSPACE": str(ws),
                    "OPENCODE_GOVERNANCE_REPOSITORY": str(ws),
                },
            )
            self.assertEqual(r.returncode, 2)
            self.assertIn("GOVERNANCE", r.stdout.upper() + r.stderr.upper())

    def test_architect_governance_write_allowed(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            ws = pathlib.Path(td)
            (ws / ".ai").mkdir()
            target = ws / ".ai" / "STATUS.md"
            target.write_text("x\n", encoding="utf-8")
            r = self._run_enforce(
                "architect",
                "edit",
                {"filePath": str(target)},
                env_extra={
                    "OPENCODE_GOVERNANCE_WORKSPACE": str(ws),
                    "OPENCODE_GOVERNANCE_REPOSITORY": str(ws),
                },
            )
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)

    def test_external_ai_string_denied(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            ws = pathlib.Path(td)
            (ws / ".ai").mkdir()
            other = ws / "vendor" / ".ai" / "x.md"
            # path not under registered root — relative escape
            r = self._run_enforce(
                "architect",
                "edit",
                {"filePath": str(ws / "other.ai" / "x.md")},
                env_extra={
                    "OPENCODE_GOVERNANCE_WORKSPACE": str(ws),
                    "OPENCODE_GOVERNANCE_REPOSITORY": str(ws),
                },
            )
            self.assertEqual(r.returncode, 2)

    def test_traversal_ai_denied(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            ws = pathlib.Path(td)
            (ws / ".ai").mkdir()
            r = self._run_enforce(
                "architect",
                "edit",
                {"filePath": str(ws / ".ai" / ".." / "Source" / "x.js")},
                env_extra={
                    "OPENCODE_GOVERNANCE_WORKSPACE": str(ws),
                    "OPENCODE_GOVERNANCE_REPOSITORY": str(ws),
                },
            )
            self.assertEqual(r.returncode, 2)

    def test_executor_outside_denied(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = pathlib.Path(td)
            exec_root = root / "exec"
            exec_root.mkdir()
            r = self._run_enforce(
                "executor",
                "edit",
                {"filePath": str(root / "outside" / "app.php")},
                env_extra={"OPENCODE_GOVERNANCE_EXECUTION_ROOT": str(exec_root)},
            )
            self.assertEqual(r.returncode, 2)

    def test_shell_chain_bypass_denied(self) -> None:
        cases = [
            "echo x > source && git status",
            "git status && write-command",
            "write-command | git diff",
            "pwsh -Command Get-Process",
            "cmd /c echo hi",
            "bash -c 'echo hi'",
            "python -c 'print(1)'",
            "node -e 'console.log(1)'",
            "echo $(whoami)",
            "git status; rm -rf /",
        ]
        with tempfile.TemporaryDirectory() as td:
            repo = pathlib.Path(td)
            for cmd in cases:
                with self.subTest(cmd=cmd):
                    r = self._run_enforce(
                        "architect",
                        "bash",
                        {"command": cmd},
                        env_extra={
                            "OPENCODE_GOVERNANCE_WORKSPACE": str(repo),
                            "OPENCODE_GOVERNANCE_REPOSITORY": str(repo),
                        },
                    )
                    self.assertEqual(r.returncode, 2, cmd + " => " + r.stdout)

    def test_architect_exact_git_allow(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            repo = pathlib.Path(td).resolve()
            cmd = f'git -C {repo} status --porcelain'
            # On Windows path may need quotes in real shell; our tokenizer treats whole path as one token if unquoted without spaces
            r = self._run_enforce(
                "architect",
                "bash",
                {"command": cmd},
                env_extra={
                    "OPENCODE_GOVERNANCE_WORKSPACE": str(repo),
                    "OPENCODE_GOVERNANCE_REPOSITORY": str(repo),
                },
            )
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)

    def test_architect_git_without_C_denied(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            repo = pathlib.Path(td)
            r = self._run_enforce(
                "architect",
                "bash",
                {"command": "git status"},
                env_extra={
                    "OPENCODE_GOVERNANCE_WORKSPACE": str(repo),
                    "OPENCODE_GOVERNANCE_REPOSITORY": str(repo),
                },
            )
            self.assertEqual(r.returncode, 2)

    def test_secret_path_denied(self) -> None:
        r = self._run_enforce("architect", "read", {"filePath": ".env"})
        self.assertEqual(r.returncode, 2)

    def test_unknown_role_denied(self) -> None:
        r = self._run_enforce("not-a-role", "read", {"filePath": "x"})
        self.assertEqual(r.returncode, 2)

    def test_sibling_report_isolation(self) -> None:
        r = self._run_enforce("reviewer", "edit", {"filePath": ".ai/tasks/T/REVIEW_ARCHITECTURE.md"})
        self.assertEqual(r.returncode, 2)

    def test_legacy_cjs_rejected(self) -> None:
        cjs = ROOT / "plugins" / "opencode-governance-effect-enforcement" / "index.js"
        # package.json type=module: CommonJS entry is not the supported OpenCode load path.
        r = subprocess.run(
            [
                self.node,
                "-e",
                f"""
const fs=require('fs');
const text=fs.readFileSync({json.dumps(str(cjs))},'utf8');
if(!text.includes('LEGACY_CJS_REJECTED') && !text.includes('CommonJS')) process.exit(3);
console.log('legacy_cjs_marker_ok');
""",
            ],
            capture_output=True,
            text=True,
        )
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("legacy_cjs_marker_ok", r.stdout)


class EffectPluginInstallTests(unittest.TestCase):
    def test_clean_install_verify_uninstall(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            cfg = pathlib.Path(td) / "cfg"
            cfg.mkdir()
            # preserve unrelated plugin
            plugins = cfg / "plugins"
            plugins.mkdir()
            unrelated = plugins / "owner-plugin.mjs"
            unrelated.write_text("export const X=1\n", encoding="utf-8")
            inst = subprocess.run(
                [sys.executable, str(INSTALLER), "--config-dir", str(cfg), "--source-dir", str(ROOT / "scripts"), "install"],
                capture_output=True,
                text=True,
            )
            self.assertEqual(inst.returncode, 0, inst.stdout + inst.stderr)
            payload = json.loads(inst.stdout.strip().splitlines()[-1])
            self.assertEqual(payload["status"], "EFFECT_PLUGIN_INSTALLED")
            self.assertEqual(payload["self_test"]["status"], "EFFECT_PLUGIN_SELF_TEST_PASS")
            self.assertEqual("preserve" if False else unrelated.read_text(encoding="utf-8"), "export const X=1\n")
            ver = subprocess.run(
                [sys.executable, str(INSTALLER), "--config-dir", str(cfg), "verify"],
                capture_output=True,
                text=True,
            )
            self.assertEqual(ver.returncode, 0, ver.stdout + ver.stderr)
            # reinstall idempotent
            inst2 = subprocess.run(
                [sys.executable, str(INSTALLER), "--config-dir", str(cfg), "--source-dir", str(ROOT / "scripts"), "install"],
                capture_output=True,
                text=True,
            )
            self.assertEqual(inst2.returncode, 0, inst2.stdout + inst2.stderr)
            # ownership conflict
            conflict_cfg = pathlib.Path(td) / "conflict"
            conflict_cfg.mkdir()
            cplug = conflict_cfg / "plugins" / "opencode-governance-effect-enforcement"
            cplug.mkdir(parents=True)
            (cplug / "foreign.txt").write_text("nope", encoding="utf-8")
            bad = subprocess.run(
                [sys.executable, str(INSTALLER), "--config-dir", str(conflict_cfg), "--source-dir", str(ROOT / "scripts"), "install", "--skip-self-test"],
                capture_output=True,
                text=True,
            )
            self.assertNotEqual(bad.returncode, 0)
            self.assertIn("OWNERSHIP_CONFLICT", bad.stdout + bad.stderr)
            un = subprocess.run(
                [sys.executable, str(INSTALLER), "--config-dir", str(cfg), "uninstall"],
                capture_output=True,
                text=True,
            )
            self.assertEqual(un.returncode, 0, un.stdout + un.stderr)
            self.assertTrue(unrelated.is_file())
            self.assertFalse((plugins / "opencode-governance-effect-enforcement.mjs").exists())

    def test_hash_mismatch_verify_fails(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            cfg = pathlib.Path(td)
            subprocess.run(
                [sys.executable, str(INSTALLER), "--config-dir", str(cfg), "--source-dir", str(ROOT / "scripts"), "install"],
                check=True,
                capture_output=True,
                text=True,
            )
            index = cfg / "plugins" / "opencode-governance-effect-enforcement" / "index.mjs"
            index.write_text(index.read_text(encoding="utf-8") + "\n// tamper\n", encoding="utf-8")
            ver = subprocess.run(
                [sys.executable, str(INSTALLER), "--config-dir", str(cfg), "verify"],
                capture_output=True,
                text=True,
            )
            self.assertNotEqual(ver.returncode, 0)
            self.assertIn("HASH_MISMATCH", ver.stdout + ver.stderr)


class ReportIngestV2Tests(unittest.TestCase):
    def _envelope(self, role: str, task_id: str, body: str, **extra) -> dict:
        env = {
            "schema": "opencode-governance.role-report/v3",
            "role": role,
            "task_id": task_id,
            "packet_sha256": "ab" * 32,
            "candidate_identity": "cand1",
            "evidence_manifest_sha256": "cd" * 32,
            "report_body_sha256": sha256_text(body),
            "permission_policy_sha256": "ef" * 32,
            "verdict": "PASS",
            "secret_scan": "PASS",
        }
        env.update(extra)
        return env

    def _write_route_receipt(self, root: pathlib.Path, role: str, family: str) -> pathlib.Path:
        # Ingestion requires AUTHORITATIVE_ROUTE_RECEIPT_V1 on the production path.
        path = root / f"route-{role}.json"
        route_receipt = ROOT / "scripts" / "route-receipt.py"
        r = subprocess.run(
            [
                sys.executable, str(route_receipt), "emit",
                "--out", str(path),
                "--role", role,
                "--task-id", "T1",
                "--route-id", f"route-{role}",
                "--model", f"model-{family}",
                "--variant", "minimal",
                "--model-family", family,
                "--provider-route-identity", f"provider-{family}",
                "--packet-sha256", "ab" * 32,
                "--candidate-identity", "cand1",
                "--selection-policy-sha256", "0" * 64,
                "--launch-sha256", "1" * 64,
                "--role-process-receipt-sha256", "2" * 64,
                "--process-id", "123",
                "--session-id", "sess-test",
                "--started-at-utc", "2026-08-02T10:00:00Z",
                "--completed-at-utc", "2026-08-02T10:05:00Z",
            ],
            capture_output=True,
            text=True,
        )
        assert r.returncode == 0, r.stdout + r.stderr
        return path

    def test_ingest_and_chain(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = pathlib.Path(td)
            bodies = {
                "implementation-reviewer": ("# Implementation review\nVERDICT: PASS\n", "family-a"),
                "architecture-reviewer": ("# Architecture review\nVERDICT: PASS\n", "family-b"),
                "final-reviewer": ("# Final\nVERDICT: PASS\n", "family-c"),
            }
            for role, (body, family) in bodies.items():
                env = self._envelope(role, "T1", body)
                ep = root / f"{role}.json"
                bp = root / f"{role}.md"
                ep.write_text(json.dumps(env), encoding="utf-8")
                bp.write_text(body, encoding="utf-8")
                rr = self._write_route_receipt(root, role, family)
                r = subprocess.run(
                    [
                        sys.executable,
                        str(INGEST),
                        "ingest",
                        "--project-dir",
                        str(root),
                        "--envelope",
                        str(ep),
                        "--body",
                        str(bp),
                        "--route-receipt",
                        str(rr),
                    ],
                    capture_output=True,
                    text=True,
                )
                self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
            att = subprocess.run(
                [sys.executable, str(INGEST), "attest-chain", "--project-dir", str(root), "--task-id", "T1"],
                capture_output=True,
                text=True,
            )
            self.assertEqual(att.returncode, 0, att.stdout + att.stderr)
            payload = json.loads(att.stdout)
            self.assertEqual(payload["status"], "REVIEW_CHAIN_ATTESTED")
            self.assertEqual(payload["attestation"]["schema"], "REVIEW_CHAIN_ATTESTATION_V4")

    def test_task_id_traversal_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = pathlib.Path(td)
            body = "x\n"
            for bad in ["../escape", "a/b", "C:\\\\windows", "..", "a\\b", "task/../../x"]:
                env = self._envelope("implementation-reviewer", bad, body)
                ep = root / "e.json"
                bp = root / "b.md"
                ep.write_text(json.dumps(env), encoding="utf-8")
                bp.write_text(body, encoding="utf-8")
                r = subprocess.run(
                    [sys.executable, str(INGEST), "ingest", "--project-dir", str(root), "--envelope", str(ep), "--body", str(bp), "--route-receipt", str(self._write_route_receipt(root, "implementation-reviewer", "family-a"))],
                    capture_output=True,
                    text=True,
                )
                self.assertNotEqual(r.returncode, 0, bad)
                self.assertIn("TASK_ID", r.stdout + r.stderr)

    def test_duplicate_divergent_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = pathlib.Path(td)
            body = "first\n"
            env = self._envelope("implementation-reviewer", "T2", body)
            ep = root / "e.json"
            bp = root / "b.md"
            ep.write_text(json.dumps(env), encoding="utf-8")
            bp.write_text(body, encoding="utf-8")
            self.assertEqual(
                subprocess.run(
                    [sys.executable, str(INGEST), "ingest", "--project-dir", str(root), "--envelope", str(ep), "--body", str(bp), "--route-receipt", str(self._write_route_receipt(root, "implementation-reviewer", "family-a"))],
                    capture_output=True,
                    text=True,
                ).returncode,
                0,
            )
            body2 = "second\n"
            env2 = self._envelope("implementation-reviewer", "T2", body2)
            ep.write_text(json.dumps(env2), encoding="utf-8")
            bp.write_text(body2, encoding="utf-8")
            r = subprocess.run(
                [sys.executable, str(INGEST), "ingest", "--project-dir", str(root), "--envelope", str(ep), "--body", str(bp), "--route-receipt", str(self._write_route_receipt(root, "implementation-reviewer", "family-a"))],
                capture_output=True,
                text=True,
            )
            self.assertNotEqual(r.returncode, 0)
            self.assertIn("DUPLICATE", r.stdout + r.stderr)

    def test_chain_candidate_mismatch(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = pathlib.Path(td)
            for role, body, family, cand in [
                ("implementation-reviewer", "i\n", "family-a", "cand1"),
                ("architecture-reviewer", "a\n", "family-b", "cand2"),
                ("final-reviewer", "f\n", "family-c", "cand1"),
            ]:
                env = self._envelope(role, "T3", body, model_family=family, candidate_identity=cand)
                ep = root / f"{role}.json"
                bp = root / f"{role}.md"
                ep.write_text(json.dumps(env), encoding="utf-8")
                bp.write_text(body, encoding="utf-8")
                subprocess.run(
                    [sys.executable, str(INGEST), "ingest", "--project-dir", str(root), "--envelope", str(ep), "--body", str(bp), "--route-receipt", str(self._write_route_receipt(root, role, family))],
                    check=True,
                    capture_output=True,
                    text=True,
                )
            att = subprocess.run(
                [sys.executable, str(INGEST), "attest-chain", "--project-dir", str(root), "--task-id", "T3"],
                capture_output=True,
                text=True,
            )
            self.assertNotEqual(att.returncode, 0)
            self.assertIn("CANDIDATE", att.stdout + att.stderr)

    def test_family_collision(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = pathlib.Path(td)
            for role, body in [
                ("implementation-reviewer", "i\n"),
                ("architecture-reviewer", "a\n"),
                ("final-reviewer", "f\n"),
            ]:
                env = self._envelope(role, "T4", body, model_family="same-family")
                ep = root / f"{role}.json"
                bp = root / f"{role}.md"
                ep.write_text(json.dumps(env), encoding="utf-8")
                bp.write_text(body, encoding="utf-8")
                subprocess.run(
                    [sys.executable, str(INGEST), "ingest", "--project-dir", str(root), "--envelope", str(ep), "--body", str(bp), "--route-receipt", str(self._write_route_receipt(root, role, "same-family"))],
                    check=True,
                    capture_output=True,
                    text=True,
                )
            att = subprocess.run(
                [sys.executable, str(INGEST), "attest-chain", "--project-dir", str(root), "--task-id", "T4"],
                capture_output=True,
                text=True,
            )
            self.assertNotEqual(att.returncode, 0)
            self.assertIn("FAMILY_COLLISION", att.stdout + att.stderr)

    def test_body_tamper_detected_on_chain(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = pathlib.Path(td)
            for role, body, family in [
                ("implementation-reviewer", "i\n", "family-a"),
                ("architecture-reviewer", "a\n", "family-b"),
                ("final-reviewer", "f\n", "family-c"),
            ]:
                env = self._envelope(role, "T5", body, model_family=family)
                ep = root / f"{role}.json"
                bp = root / f"{role}.md"
                ep.write_text(json.dumps(env), encoding="utf-8")
                bp.write_text(body, encoding="utf-8")
                subprocess.run(
                    [sys.executable, str(INGEST), "ingest", "--project-dir", str(root), "--envelope", str(ep), "--body", str(bp), "--route-receipt", str(self._write_route_receipt(root, role, family))],
                    check=True,
                    capture_output=True,
                    text=True,
                )
            report = root / ".ai" / "tasks" / "T5" / "reports" / "REVIEW_IMPLEMENTATION.md"
            report.write_text("tampered\n", encoding="utf-8")
            att = subprocess.run(
                [sys.executable, str(INGEST), "attest-chain", "--project-dir", str(root), "--task-id", "T5"],
                capture_output=True,
                text=True,
            )
            self.assertNotEqual(att.returncode, 0)
            self.assertIn("TAMPER", att.stdout + att.stderr)


if __name__ == "__main__":
    unittest.main()
