#!/usr/bin/env python3
"""OpenCode Governance 4.0.3 — dedicated negative + positive test matrix (Section 17).

Covers the deterministic (non-live-model) subset of the required matrix:
  * apply_patch / multiedit path parsing (STRICT_PATCH_PATH_CONTRACT_V1)
  * Executor command broker (EXECUTOR_COMMAND_BROKER_V1)
  * Route receipt schema strictness (AUTHORITATIVE_ROUTE_RECEIPT_V1)
  * Tool capability manifest (TOOL_CAPABILITY_MANIFEST_V1)
  * Review Chain V4 + transactional report commit revalidation
  * Report transaction commit marker / rollback
"""
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
ROUTE_RECEIPT = ROOT / "scripts" / "route-receipt.py"
MANIFEST_TOOL = ROOT / "scripts" / "tool-capability-manifest.py"
INGEST = ROOT / "scripts" / "role-report-ingest.py"
GOVERNED_LAUNCH = ROOT / "scripts" / "governed-role-launch.py"


def sha256_text(t: str) -> str:
    return hashlib.sha256(t.encode("utf-8")).hexdigest()


def sha256_file(p: pathlib.Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def node_available() -> str | None:
    return shutil.which("node")


@unittest.skipUnless(node_available(), "node not available")
class PatchPathTests(unittest.TestCase):
    """S-008: apply_patch / multiedit path parsing — STRICT_PATCH_PATH_CONTRACT_V1."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.node = node_available()
        cls.plugin_url = PLUGIN_MJS.resolve().as_uri()

    def _extract(self, args: dict) -> dict:
        script = (
            f"import P from {json.dumps(self.plugin_url)}; "
            f"console.log(JSON.stringify(P._extractPatchPaths({json.dumps(args)})));"
        )
        r = subprocess.run([self.node, "--input-type=module", "-e", script],
                           capture_output=True, text=True, check=True)
        return json.loads(r.stdout)

    def test_unified_diff_paths_extracted(self) -> None:
        diff = "diff --git a/src/app.js b/src/app.js\n--- a/src/app.js\n+++ b/src/app.js\n@@\n-old\n+new\n"
        out = self._extract({"patch": diff})
        self.assertIn("src/app.js", out["paths"])

    def test_dev_null_new_file(self) -> None:
        diff = "--- /dev/null\n+++ b/new.txt\n@@\n+content\n"
        out = self._extract({"patch": diff})
        self.assertIn("new.txt", out["paths"])

    def test_rename_paths_extracted(self) -> None:
        diff = "rename from old/name.js\nrename to new/name.js\n"
        out = self._extract({"patch": diff})
        self.assertIn("old/name.js", out["paths"])
        self.assertIn("new/name.js", out["paths"])

    def test_multiedit_edits_array(self) -> None:
        args = {"edits": [{"filePath": "a.js"}, {"filePath": "b.js"}, {"path": "c.js"}]}
        out = self._extract(args)
        self.assertEqual(set(out["paths"]), {"a.js", "b.js", "c.js"})

    def test_direct_path_keys(self) -> None:
        out = self._extract({"filePath": "x.js"})
        self.assertIn("x.js", out["paths"])

    def test_traversal_target_caught_at_enforce(self) -> None:
        """Executor enforce rejects traversal targets extracted from a patch."""
        env = dict(os.environ)
        env["OPENCODE_GOVERNANCE_EFFECT_ENFORCEMENT_ACTIVE"] = "1"
        env["OPENCODE_GOVERNANCE_ROLE"] = "executor"
        env["OPENCODE_GOVERNANCE_EFFECT_POLICY"] = str(POLICY)
        env["OPENCODE_GOVERNANCE_EXECUTION_ROOT"] = str(pathlib.Path(tempfile.gettempdir()))
        script = (
            f"import P from {json.dumps(self.plugin_url)}; "
            "const policy = P._loadPolicy(); "
            "const input = { tool: 'apply_patch' }; "
            "const output = { args: { patch: '--- a/x.js\\n+++ b/../escape.js\\n@@\\n+x\\n' } }; "
            "try { P._enforce(policy, input, output, {}); console.log('ALLOWED'); } "
            "catch (e) { console.log('DENIED:' + String(e.message || e).split(':')[0]); }"
        )
        r = subprocess.run([self.node, "--input-type=module", "-e", script],
                           capture_output=True, text=True, env=env)
        self.assertIn("DENIED", r.stdout, r.stderr)
        # Traversal in an apply_patch target is rejected as outside the execution root.
        self.assertIn("OUTSIDE_EXECUTION_ROOT", r.stdout)

    def test_combined_diff_paths_extracted(self) -> None:
        """diff --cc / --combined headers are parsed, not silently skipped."""
        out = self._extract({"patch": "diff --combined src/merged.js\nindex ..\n@@@ \n@@@ \n-old\n+new\n+++ b/src/merged.js\n"})
        self.assertIn("src/merged.js", out["paths"])

    def test_git_quoted_path_unquoted(self) -> None:
        """Paths git quotes (spaces/special) are unquoted before containment."""
        out = self._extract({"patch": '+++ "b/weird path.js"\n@@\n+x\n'})
        self.assertIn("weird path.js", out["paths"])

    def test_unextracted_patch_payload_fails_closed(self) -> None:
        """An edit tool carrying a patch-like payload from which NO path can be
        extracted must fail closed (S-008), not silently skip path checks."""
        out = self._extract({"patch": "this is a patch but has no recognizable headers"}, )
        # without tool context extractPatchPaths returns ok=True; the fail-closed
        # flag is set only when tool is provided. Verify the tool-aware path:
        script = (
            f"import P from {json.dumps(self.plugin_url)}; "
            "console.log(JSON.stringify(P._extractPatchPaths({patch:'no headers here'}, {tool:'apply_patch'})));"
        )
        r = subprocess.run([self.node, "--input-type=module", "-e", script],
                           capture_output=True, text=True, check=True)
        result = json.loads(r.stdout)
        self.assertFalse(result["ok"], result)
        self.assertEqual(result["reason"], "PATCH_PATHS_UNEXTRACTED")


@unittest.skipUnless(node_available(), "node not available")
class ExecutorBrokerTests(unittest.TestCase):
    """S-007: EXECUTOR_COMMAND_BROKER_V1 — deterministic command classification."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.node = node_available()
        cls.plugin_url = PLUGIN_MJS.resolve().as_uri()

    def _classify(self, cmd: str) -> dict:
        script = (
            f"import P from {json.dumps(self.plugin_url)}; "
            f"console.log(JSON.stringify(P._classifyShell({json.dumps(cmd)}, {{bash_mode:'execution_root_only'}}, {{execution_root:'/tmp/exec', repository:'/tmp/repo', workspace:'/tmp/ws'}})));"
        )
        r = subprocess.run([self.node, "--input-type=module", "-e", script],
                           capture_output=True, text=True, check=True)
        return json.loads(r.stdout)

    def test_git_commit_denied(self) -> None:
        r = self._classify("git commit -m x")
        self.assertFalse(r["allow"])
        self.assertIn("DENIED_GIT", r["reason"])

    def test_git_push_denied(self) -> None:
        r = self._classify("git push origin main")
        self.assertFalse(r["allow"])

    def test_git_reset_denied(self) -> None:
        r = self._classify("git reset --hard HEAD~1")
        self.assertFalse(r["allow"])

    def test_rm_denied(self) -> None:
        self.assertFalse(self._classify("rm -rf foo")["allow"])

    def test_npm_denied(self) -> None:
        self.assertFalse(self._classify("npm install")["allow"])

    def test_docker_denied(self) -> None:
        self.assertFalse(self._classify("docker build .")["allow"])

    def test_interpreter_denied(self) -> None:
        self.assertFalse(self._classify("python evil.py")["allow"])
        self.assertFalse(self._classify("bash -c whoami")["allow"])

    def test_readonly_git_allowed(self) -> None:
        self.assertTrue(self._classify("git status")["allow"])
        self.assertTrue(self._classify("git diff")["allow"])

    def test_unknown_git_subcmd_denied(self) -> None:
        r = self._classify("git stash")
        self.assertFalse(r["allow"])

    def test_test_command_allowed(self) -> None:
        self.assertTrue(self._classify("pytest tests/")["allow"])


class RouteReceiptTests(unittest.TestCase):
    """S-014: AUTHORITATIVE_ROUTE_RECEIPT_V1 strict schema."""

    def _emit(self, td: pathlib.Path, **overrides) -> dict:
        out = td / "receipt.json"
        base = dict(
            out=str(out), role="executor", task_id="T1", route_id="r1", model="m",
            variant="minimal", model_family="f", provider_route_identity="p1",
            packet_sha256="ab" * 32, candidate_identity="cand1",
            selection_policy_sha256="0" * 64, launch_sha256="1" * 64,
            role_process_receipt_sha256="2" * 64, process_id=123, session_id="s1",
            started_at_utc="2026-08-02T10:00:00Z", completed_at_utc="2026-08-02T10:05:00Z",
        )
        base.update(overrides)
        args = [sys.executable, str(ROUTE_RECEIPT), "emit"]
        for k, v in base.items():
            args += [f"--{k.replace('_', '-')}", str(v)]
        r = subprocess.run(args, capture_output=True, text=True)
        return {"rc": r.returncode, "stdout": r.stdout, "stderr": r.stderr, "out": out}

    def test_valid_receipt_emits(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            r = self._emit(pathlib.Path(td))
            self.assertEqual(r["rc"], 0, r["stderr"])

    def test_missing_field_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            r = self._emit(pathlib.Path(td), model_family="")
            self.assertNotEqual(r["rc"], 0)
            self.assertIn("FIELD_MISSING", r["stderr"])

    def test_invalid_sha256_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            r = self._emit(pathlib.Path(td), packet_sha256="not-a-hash")
            self.assertNotEqual(r["rc"], 0)
            self.assertIn("SHA256_INVALID", r["stderr"])

    def test_role_mismatch_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            r = self._emit(pathlib.Path(td), role="executor")
            self.assertEqual(r["rc"], 0)
            # validate with a different expected role
            v = subprocess.run([sys.executable, str(ROUTE_RECEIPT), "validate",
                                "--receipt", str(r["out"]), "--expected-role", "reviewer"],
                               capture_output=True, text=True)
            self.assertNotEqual(v.returncode, 0)
            self.assertIn("ROLE_MISMATCH", v.stderr)

    def test_packet_mismatch_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            r = self._emit(pathlib.Path(td))
            v = subprocess.run([sys.executable, str(ROUTE_RECEIPT), "validate",
                                "--receipt", str(r["out"]), "--expected-packet", "cd" * 32],
                               capture_output=True, text=True)
            self.assertNotEqual(v.returncode, 0)
            self.assertIn("PACKET_MISMATCH", v.stderr)


class ToolManifestTests(unittest.TestCase):
    """S-018: TOOL_CAPABILITY_MANIFEST_V1."""

    def test_valid_manifest(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            out = pathlib.Path(td) / "manifest.json"
            tools = json.dumps([
                {"name": "db_query", "connector": "mcp", "version": "1.0.0",
                 "effect_classes": ["READ"], "network_behaviour": "none",
                 "external_side_effects": "none", "path_fields": ["query"]},
            ])
            r = subprocess.run([sys.executable, str(MANIFEST_TOOL), "emit", "--out", str(out), "--tools-json", tools],
                               capture_output=True, text=True)
            self.assertEqual(r.returncode, 0, r.stderr)
            v = subprocess.run([sys.executable, str(MANIFEST_TOOL), "validate", "--manifest", str(out)],
                               capture_output=True, text=True)
            self.assertEqual(v.returncode, 0, v.stderr)

    def test_unknown_effect_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            out = pathlib.Path(td) / "manifest.json"
            tools = json.dumps([
                {"name": "x", "connector": "mcp", "version": "1",
                 "effect_classes": ["NUKE_EVERYTHING"], "network_behaviour": "none",
                 "external_side_effects": "none"},
            ])
            r = subprocess.run([sys.executable, str(MANIFEST_TOOL), "emit", "--out", str(out), "--tools-json", tools],
                               capture_output=True, text=True)
            self.assertNotEqual(r.returncode, 0)
            self.assertIn("EFFECT_UNKNOWN", r.stderr)

    def test_missing_network_behaviour_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            out = pathlib.Path(td) / "manifest.json"
            tools = json.dumps([
                {"name": "x", "connector": "mcp", "version": "1",
                 "effect_classes": ["READ"], "external_side_effects": "none"},
            ])
            r = subprocess.run([sys.executable, str(MANIFEST_TOOL), "emit", "--out", str(out), "--tools-json", tools],
                               capture_output=True, text=True)
            self.assertNotEqual(r.returncode, 0)
            self.assertIn("NETWORK_BEHAVIOUR_MISSING", r.stderr)


class ReportTransactionTests(unittest.TestCase):
    """S-016: DETERMINISTIC_ROLE_REPORT_TRANSACTION_V1 — commit marker + rollback."""

    def _setup_project(self, td: pathlib.Path) -> pathlib.Path:
        project = td / "proj"
        (project / ".ai" / "tasks" / "T1" / "reports").mkdir(parents=True)
        return project

    def _route_receipt(self, td: pathlib.Path, role: str, family: str) -> pathlib.Path:
        out = td / f"route-{role}.json"
        subprocess.run([sys.executable, str(ROUTE_RECEIPT), "emit", "--out", str(out),
                        "--role", role, "--task-id", "T1", "--route-id", f"r-{role}",
                        "--model", f"m-{family}", "--variant", "minimal", "--model-family", family,
                        "--provider-route-identity", "p1", "--packet-sha256", "ab" * 32,
                        "--candidate-identity", "cand1", "--selection-policy-sha256", "0" * 64,
                        "--launch-sha256", "1" * 64, "--role-process-receipt-sha256", "2" * 64,
                        "--process-id", "1", "--session-id", "s1",
                        "--started-at-utc", "2026-08-02T10:00:00Z",
                        "--completed-at-utc", "2026-08-02T10:05:00Z"],
                       check=True, capture_output=True)
        return out

    def _ingest(self, project: pathlib.Path, role: str, body: str, td: pathlib.Path, family: str) -> dict:
        env = {
            "schema": "opencode-governance.role-report/v3", "role": role, "task_id": "T1",
            "packet_sha256": "ab" * 32, "candidate_identity": "cand1",
            "evidence_manifest_sha256": "cd" * 32, "report_body_sha256": sha256_text(body),
            "permission_policy_sha256": "ef" * 32, "verdict": "PASS", "secret_scan": "PASS",
            "model_family": family,
        }
        ep = td / f"{role}.env.json"
        bp = td / f"{role}.md"
        ep.write_text(json.dumps(env), encoding="utf-8")
        bp.write_text(body, encoding="utf-8")
        rr = self._route_receipt(td, role, family)
        r = subprocess.run([sys.executable, str(INGEST), "ingest", "--project-dir", str(project),
                            "--envelope", str(ep), "--body", str(bp), "--route-receipt", str(rr)],
                           capture_output=True, text=True)
        assert r.returncode == 0, r.stderr
        return json.loads(r.stdout.strip().splitlines()[-1])

    def test_commit_marker_written(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            td = pathlib.Path(td)
            project = self._setup_project(td)
            self._ingest(project, "implementation-reviewer", "# impl\nVERDICT: PASS\n", td, "family-a")
            tx_dirs = list((project / ".ai" / "tasks" / "T1" / "reports" / ".transactions").glob("*"))
            self.assertTrue(tx_dirs, "transaction dir not created")
            commit_markers = list(tx_dirs[0].glob("COMMITTED"))
            self.assertTrue(commit_markers, "COMMITTED marker not written")
            journal = (tx_dirs[0] / "journal.json").read_text(encoding="utf-8")
            for state in ("PREPARED", "VALIDATED", "COMMITTING", "COMMITTED"):
                self.assertIn(state, journal)

    def test_chain_v4_revalidates_and_includes_revalidation(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            td = pathlib.Path(td)
            project = self._setup_project(td)
            self._ingest(project, "implementation-reviewer", "# impl\n", td, "family-a")
            self._ingest(project, "architecture-reviewer", "# arch\n", td, "family-b")
            self._ingest(project, "final-reviewer", "# final\n", td, "family-c")
            att = subprocess.run([sys.executable, str(INGEST), "attest-chain",
                                  "--project-dir", str(project), "--task-id", "T1"],
                                 capture_output=True, text=True)
            self.assertEqual(att.returncode, 0, att.stderr)
            payload = json.loads(att.stdout.strip().splitlines()[-1])
            self.assertEqual(payload["attestation"]["schema"], "REVIEW_CHAIN_ATTESTATION_V4")
            self.assertIn("revalidation", payload["attestation"])
            self.assertEqual(len(payload["attestation"]["revalidation"]), 3)
            for rv in payload["attestation"]["revalidation"]:
                self.assertTrue(rv.get("report_body_sha256_ok"))

    def test_body_tamper_breaks_chain(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            td = pathlib.Path(td)
            project = self._setup_project(td)
            self._ingest(project, "implementation-reviewer", "# impl\n", td, "family-a")
            self._ingest(project, "architecture-reviewer", "# arch\n", td, "family-b")
            self._ingest(project, "final-reviewer", "# final\n", td, "family-c")
            # Tamper with a committed body.
            (project / ".ai" / "tasks" / "T1" / "reports" / "REVIEW_IMPLEMENTATION.md").write_text("TAMPERED\n", encoding="utf-8")
            att = subprocess.run([sys.executable, str(INGEST), "attest-chain",
                                  "--project-dir", str(project), "--task-id", "T1"],
                                 capture_output=True, text=True)
            self.assertNotEqual(att.returncode, 0)
            self.assertIn("BODY_TAMPER", att.stderr)


class LaunchV3Tests(unittest.TestCase):
    """GOVERNED_ROLE_LAUNCH_CONTRACT_V3 — schema + binding fields."""

    def test_launch_is_v3(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            out = pathlib.Path(td) / "launch.json"
            r = subprocess.run([sys.executable, str(GOVERNED_LAUNCH), "write",
                                "--out", str(out), "--role", "executor",
                                "--expected-agent", "executor",
                                "--workspace", td, "--repository", td,
                                "--execution-root", td, "--task-id", "T1",
                                "--packet-sha256", "ab" * 32],
                               capture_output=True, text=True)
            self.assertEqual(r.returncode, 0, r.stderr)
            payload = json.loads(r.stdout.strip().splitlines()[-1])
            body = payload["launch"]
            self.assertEqual(body["schema"], "GOVERNED_ROLE_LAUNCH_CONTRACT_V3")
            self.assertEqual(body["version"], "4.0.3")
            self.assertTrue(body["nonce"])
            self.assertIn("tool_capability_manifest_sha256", body)
            self.assertIn("route", body)


@unittest.skipUnless(node_available(), "node not available")
class HostAckBindingTests(unittest.TestCase):
    """S-001 blocker fix: the host-ack nonce must be cryptographically bound to
    the emitted READY. A forged ack with a wrong nonce must be rejected."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.node = node_available()
        cls.plugin_url = PLUGIN_MJS.resolve().as_uri()

    def _run_enforce_with_ack(self, ack_nonce: str) -> str:
        """Drive the plugin through writeReady -> readHostAck -> enforce, with a
        caller-controlled ack nonce, and return stdout (ALLOWED or DENIED:...)."""
        # A launch with a real nonce so ready_nonce is derived (production path).
        launch = {"schema": "GOVERNED_ROLE_LAUNCH_CONTRACT_V3", "launch_id": "L1",
                  "nonce": "abc123", "_launch_sha256": "deadbeef"}
        script = (
            f"import P from {json.dumps(self.plugin_url)}; "
            "import fs from 'node:fs'; import path from 'node:path'; import os from 'node:os'; "
            "const td = fs.mkdtempSync(path.join(os.tmpdir(), 'ack-')); "
            "const hs = path.join(td, 'ready.json'); const ack = path.join(td, 'ack.json'); "
            "process.env.OPENCODE_GOVERNANCE_EFFECT_ENFORCEMENT_ACTIVE='1'; "
            "process.env.OPENCODE_GOVERNANCE_ROLE='executor'; "
            "process.env.OPENCODE_GOVERNANCE_EFFECT_POLICY=" + json.dumps(str(POLICY)) + "; "
            "process.env.OPENCODE_GOVERNANCE_HANDSHAKE_PATH=hs; "
            "process.env.OPENCODE_GOVERNANCE_REQUIRE_HOST_ACK='1'; "
            "process.env.OPENCODE_GOVERNANCE_HOST_ACK_PATH=ack; "
            "process.env.OPENCODE_GOVERNANCE_EXECUTION_ROOT=td; "
            "process.env.OPENCODE_GOVERNANCE_SESSION_ID='s1'; "
            "const ready = P._writeReady({}, " + json.dumps(launch) + ", P._loadPolicy()); "
            "fs.writeFileSync(ack, JSON.stringify({schema:'GOVERNED_ROLE_HOST_ACK_V1',ready_nonce:" + json.dumps(ack_nonce) + ",process_id:process.pid,session_id:'s1'})); "
            "try { P._enforce(P._loadPolicy(), {tool:'read', args:{path:'x'}}, {args:{path:'x'}}, {}); console.log('ALLOWED'); } "
            "catch(e){ console.log('DENIED:'+String(e.message||e)); }"
        )
        r = subprocess.run([self.node, "--input-type=module", "-e", script],
                           capture_output=True, text=True, check=True)
        return r.stdout.strip()

    def test_forged_ack_nonce_rejected(self) -> None:
        """A wrong-nonce ack must NOT open the gate (S-001 binding)."""
        out = self._run_enforce_with_ack("forged-wrong-nonce")
        self.assertIn("DENIED", out, out)
        self.assertIn("NONCE_MISMATCH", out)


class EnvelopeDowngradeTests(unittest.TestCase):
    """S-014 blocker fix: caller-supplied envelope flags must NOT downgrade the
    production route-receipt / schema requirements."""

    def _route_receipt(self, td: pathlib.Path, role: str) -> pathlib.Path:
        out = td / f"route-{role}.json"
        subprocess.run([sys.executable, str(ROUTE_RECEIPT), "emit", "--out", str(out),
                        "--role", role, "--task-id", "T1", "--route-id", "r1", "--model", "m",
                        "--variant", "minimal", "--model-family", "f", "--provider-route-identity", "p1",
                        "--packet-sha256", "ab" * 32, "--candidate-identity", "cand1",
                        "--selection-policy-sha256", "0" * 64, "--launch-sha256", "1" * 64,
                        "--role-process-receipt-sha256", "2" * 64, "--process-id", "1", "--session-id", "s1",
                        "--started-at-utc", "2026-08-02T10:00:00Z",
                        "--completed-at-utc", "2026-08-02T10:05:00Z"],
                       check=True, capture_output=True)
        return out

    def test_accept_legacy_route_receipt_in_envelope_ignored(self) -> None:
        """A caller setting accept_legacy_route_receipt=true in the envelope must
        NOT bypass AUTHORITATIVE_ROUTE_RECEIPT_V1 on the production path."""
        with tempfile.TemporaryDirectory() as td:
            td = pathlib.Path(td)
            project = td / "proj"
            (project / ".ai" / "tasks" / "T1" / "reports").mkdir(parents=True)
            # A loose/legacy route receipt (NOT authoritative schema).
            loose_rr = td / "loose-route.json"
            loose_rr.write_text(json.dumps({"route_id": "r1", "model_family": "f", "role": "implementation-reviewer"}), encoding="utf-8")
            body = "# impl\n"
            env_obj = {
                "schema": "opencode-governance.role-report/v3", "role": "implementation-reviewer",
                "task_id": "T1", "packet_sha256": "ab" * 32, "candidate_identity": "cand1",
                "evidence_manifest_sha256": "cd" * 32, "report_body_sha256": sha256_text(body),
                "permission_policy_sha256": "ef" * 32, "verdict": "PASS", "secret_scan": "PASS",
                "model_family": "f", "accept_legacy_route_receipt": True,
            }
            ep = td / "env.json"; bp = td / "body.md"
            ep.write_text(json.dumps(env_obj), encoding="utf-8"); bp.write_text(body, encoding="utf-8")
            r = subprocess.run([sys.executable, str(INGEST), "ingest", "--project-dir", str(project),
                                "--envelope", str(ep), "--body", str(bp), "--route-receipt", str(loose_rr)],
                               capture_output=True, text=True)
            self.assertNotEqual(r.returncode, 0, r.stdout + r.stderr)
            self.assertIn("AUTHORITATIVE_ROUTE_RECEIPT_V1", r.stderr)


class TransactionRollbackTests(unittest.TestCase):
    """S-016 blocker fix: rollback must restore prior committed artifacts."""

    def test_rollback_restores_prior_body(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            td = pathlib.Path(td)
            project = td / "proj"
            reports = project / ".ai" / "tasks" / "T1" / "reports"
            reports.mkdir(parents=True)
            dest = reports / "REVIEW_IMPLEMENTATION.md"
            meta = reports / "REVIEW_IMPLEMENTATION.ingest.json"
            prior_body = b"# prior committed\n"
            prior_meta = b'{"prior": true}\n'
            dest.write_bytes(prior_body)
            meta.write_bytes(prior_meta)
            from importlib import util as _util
            spec = _util.spec_from_file_location("_ing", INGEST)
            mod = _util.module_from_spec(spec)
            spec.loader.exec_module(mod)
            tx_dir = reports / ".transactions" / "tx-test"
            tx_dir.mkdir(parents=True)
            # Simulate a partial new body written to dest before failure.
            dest.write_bytes(b"# uncommitted new\n")
            mod._rollback_transaction(tx_dir, dest, meta, prior_dest=prior_body, prior_meta=prior_meta)
            self.assertEqual(dest.read_bytes(), prior_body, "prior body not restored on rollback")
            self.assertEqual(meta.read_bytes(), prior_meta, "prior meta not restored on rollback")
            self.assertFalse(tx_dir.exists(), "tx dir not cleaned up")

    def test_rollback_removes_created_dest_when_no_prior(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            td = pathlib.Path(td)
            project = td / "proj"
            reports = project / ".ai" / "tasks" / "T1" / "reports"
            reports.mkdir(parents=True)
            dest = reports / "REVIEW_IMPLEMENTATION.md"
            meta = reports / "REVIEW_IMPLEMENTATION.ingest.json"
            dest.write_bytes(b"# uncommitted\n")
            from importlib import util as _util
            spec = _util.spec_from_file_location("_ing", INGEST)
            mod = _util.module_from_spec(spec)
            spec.loader.exec_module(mod)
            tx_dir = reports / ".transactions" / "tx-test"
            tx_dir.mkdir(parents=True)
            mod._rollback_transaction(tx_dir, dest, meta, prior_dest=None, prior_meta=None)
            self.assertFalse(dest.exists(), "newly-created dest should be removed when no prior existed")


if __name__ == "__main__":
    unittest.main()
