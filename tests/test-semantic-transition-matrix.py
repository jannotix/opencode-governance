#!/usr/bin/env python3
"""Generated-from-spec positive + required negative transition matrix (3.8.0)."""
from __future__ import annotations

import json
import pathlib
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
CORE = ROOT / "scripts" / "workflow-continuation.py"
sys.path.insert(0, str(ROOT / "scripts"))
from generated import governance_contract_data as G  # noqa: E402


def run_gate(state: dict) -> tuple[int, dict]:
    with tempfile.TemporaryDirectory(prefix="sem-matrix-") as d:
        path = pathlib.Path(d) / "RUN_STATE.json"
        path.write_text(json.dumps(state), encoding="utf-8")
        r = subprocess.run(
            [sys.executable, str(CORE), "--run-state", str(path), "--expected-command", "ai-workflow"],
            capture_output=True,
            text=True,
        )
        payload = json.loads(r.stdout) if r.stdout.strip() else {}
        return r.returncode, payload


def base_state(frm: str, to: str, command: str, post: str) -> dict:
    st = {
        "top_level_command": "ai-workflow",
        "current_phase": frm,
        "next_required_phase": to,
        "terminal_reason": None,
        "lifecycle_mode": "STANDARD",
        "next_action": {
            "kind": "execute" if command else "human_decision",
            "command": command or None,
            "arguments": [],
            "expected_postcondition": post,
            "decision_required": "owner scope approval" if not command else None,
            "available_choices": ["APPROVE", "REJECT"] if not command else None,
        },
    }
    if not command:
        st["next_action"] = {
            "kind": "human_decision",
            "decision_required": "owner scope approval",
            "available_choices": ["APPROVE", "REJECT"],
        }
    return st


def enrich(state: dict, transition: dict) -> dict:
    arts = list(transition.get("required_artifacts") or [])
    recs = list(transition.get("required_receipts") or [])
    if arts:
        state["present_artifacts"] = arts
    if recs:
        state["present_receipts"] = recs
    if transition.get("required_candidate_state") == "FROZEN":
        state["frozen_candidate"] = "cand"
        state["candidate_state"] = "FROZEN"
    if transition.get("required_owner_decision"):
        state["owner_decision"] = {"decision": "APPROVE"}
    if transition.get("required_review_state") == "FINAL_PASS":
        state["final_verdict"] = "PASS"
    if transition.get("required_review_state") == "BOTH_INDEPENDENT_REPORTS":
        state["review_reports"] = {"implementation": "ok", "architecture": "ok"}
    if transition.get("attempt_consumed"):
        state["attempt_consumed"] = True
        if isinstance(state.get("next_action"), dict):
            state["next_action"]["attempt_consumed"] = True
    return state


class PositiveTransitionMatrix(unittest.TestCase):
    def test_every_permitted_transition(self) -> None:
        failures = []
        for tr in G.TRANSITIONS:
            frm, to, cmd = tr["from"], tr["to"], tr.get("command") or ""
            post = tr.get("required_postcondition") or to
            state = enrich(base_state(frm, to, cmd, post), tr)
            code, payload = run_gate(state)
            if code != 3 or payload.get("decision") != "CONTINUE_REQUIRED":
                failures.append((tr["transition_id"], code, payload.get("error"), payload))
        self.assertEqual(failures, [], msg=f"positive failures: {failures[:5]}")


class NegativeTransitionMatrix(unittest.TestCase):
    def test_unknown_current_phase(self) -> None:
        code, payload = run_gate(
            {
                "top_level_command": "ai-workflow",
                "current_phase": "NOT_A_REAL_PHASE",
                "next_required_phase": "IDEA_INTAKE",
                "terminal_reason": None,
                "next_action": {
                    "kind": "execute",
                    "command": "/ai-init",
                    "arguments": [],
                    "expected_postcondition": "IDEA_INTAKE",
                },
            }
        )
        self.assertEqual(code, 2)
        self.assertEqual(payload["error"], "UNKNOWN_WORKFLOW_PHASE")

    def test_unknown_successor(self) -> None:
        code, payload = run_gate(
            {
                "top_level_command": "ai-workflow",
                "current_phase": "AUDIT_PASS",
                "next_required_phase": "NO_SUCH_PHASE",
                "terminal_reason": None,
                "next_action": {
                    "kind": "execute",
                    "command": "/ai-init",
                    "arguments": [],
                    "expected_postcondition": "NO_SUCH_PHASE",
                },
            }
        )
        self.assertEqual(code, 2)
        self.assertIn(payload["error"], {"UNKNOWN_SUCCESSOR_PHASE", "DISALLOWED_SUCCESSOR", "TRANSITION_NOT_DEFINED"})

    def test_disallowed_successor(self) -> None:
        code, payload = run_gate(
            {
                "top_level_command": "ai-workflow",
                "current_phase": "AUDIT_PASS",
                "next_required_phase": "IMPLEMENTING",
                "terminal_reason": None,
                "next_action": {
                    "kind": "execute",
                    "command": "/ai-execute",
                    "arguments": [],
                    "expected_postcondition": "IMPLEMENTING",
                    "attempt_consumed": True,
                },
                "present_artifacts": ["EXECUTION_PACKET"],
            }
        )
        self.assertEqual(code, 2)
        self.assertIn(payload["error"], {"DISALLOWED_SUCCESSOR", "TRANSITION_NOT_DEFINED"})

    def test_wrong_command(self) -> None:
        code, payload = run_gate(
            {
                "top_level_command": "ai-workflow",
                "current_phase": "AUDIT_PASS",
                "next_required_phase": "IDEA_INTAKE",
                "terminal_reason": None,
                "next_action": {
                    "kind": "execute",
                    "command": "/ai-release",
                    "arguments": [],
                    "expected_postcondition": "IDEA_INTAKE",
                },
            }
        )
        self.assertEqual(code, 2)
        self.assertIn(payload["error"], {"TRANSITION_COMMAND_MISMATCH", "TRANSITION_NOT_DEFINED"})

    def test_wrong_postcondition(self) -> None:
        code, payload = run_gate(
            {
                "top_level_command": "ai-workflow",
                "current_phase": "AUDIT_PASS",
                "next_required_phase": "IDEA_INTAKE",
                "terminal_reason": None,
                "next_action": {
                    "kind": "execute",
                    "command": "/ai-init",
                    "arguments": [],
                    "expected_postcondition": "IMPLEMENTING",
                },
            }
        )
        self.assertEqual(code, 2)
        self.assertEqual(payload["error"], "TRANSITION_POSTCONDITION_MISMATCH")

    def test_missing_artifact(self) -> None:
        # READY_FOR_EXECUTION -> PRE_CHANGE requires EXECUTION_PACKET
        code, payload = run_gate(
            {
                "top_level_command": "ai-workflow",
                "current_phase": "READY_FOR_EXECUTION",
                "next_required_phase": "PRE_CHANGE_SAFEPOINT_WHEN_REQUIRED",
                "terminal_reason": None,
                "next_action": {
                    "kind": "execute",
                    "command": "/ai-execute",
                    "arguments": [],
                    "expected_postcondition": "PRE_CHANGE_SAFEPOINT_WHEN_REQUIRED",
                },
            }
        )
        self.assertEqual(code, 2)
        self.assertEqual(payload["error"], "REQUIRED_ARTIFACT_MISSING")

    def test_stale_artifact(self) -> None:
        code, payload = run_gate(
            {
                "top_level_command": "ai-workflow",
                "current_phase": "READY_FOR_EXECUTION",
                "next_required_phase": "PRE_CHANGE_SAFEPOINT_WHEN_REQUIRED",
                "terminal_reason": None,
                "task_id": "T1",
                "artifacts": {"EXECUTION_PACKET": {"task_id": "T1", "stale": True}},
                "next_action": {
                    "kind": "execute",
                    "command": "/ai-execute",
                    "arguments": [],
                    "expected_postcondition": "PRE_CHANGE_SAFEPOINT_WHEN_REQUIRED",
                },
            }
        )
        self.assertEqual(code, 2)
        self.assertEqual(payload["error"], "ARTIFACT_STALE")

    def test_wrong_task_artifact(self) -> None:
        code, payload = run_gate(
            {
                "top_level_command": "ai-workflow",
                "current_phase": "READY_FOR_EXECUTION",
                "next_required_phase": "PRE_CHANGE_SAFEPOINT_WHEN_REQUIRED",
                "terminal_reason": None,
                "task_id": "T1",
                "artifacts": {"EXECUTION_PACKET": {"task_id": "OTHER"}},
                "next_action": {
                    "kind": "execute",
                    "command": "/ai-execute",
                    "arguments": [],
                    "expected_postcondition": "PRE_CHANGE_SAFEPOINT_WHEN_REQUIRED",
                },
            }
        )
        self.assertEqual(code, 2)
        self.assertEqual(payload["error"], "ARTIFACT_TASK_MISMATCH")

    def test_missing_receipt(self) -> None:
        code, payload = run_gate(
            {
                "top_level_command": "ai-workflow",
                "current_phase": "DUAL_REVIEW_COMPLETE",
                "next_required_phase": "FINAL_ADJUDICATION",
                "terminal_reason": None,
                "candidate_state": "FROZEN",
                "frozen_candidate": "c",
                "present_artifacts": ["EXECUTION_PACKET"],
                "next_action": {
                    "kind": "execute",
                    "command": "/ai-review",
                    "arguments": [],
                    "expected_postcondition": "FINAL_ADJUDICATION",
                },
            }
        )
        self.assertEqual(code, 2)
        self.assertIn(payload["error"], {"REQUIRED_RECEIPT_MISSING", "REVIEW_STATE_MISMATCH"})

    def test_blocker_with_successor(self) -> None:
        code, payload = run_gate(
            {
                "top_level_command": "ai-workflow",
                "current_phase": "BLOCKED",
                "next_required_phase": "IDEA_INTAKE",
                "terminal_reason": "blocked",
            }
        )
        self.assertEqual(code, 2)
        self.assertEqual(payload["error"], "BLOCKER_NEXT_PHASE_FORBIDDEN")

    def test_blocker_with_executable_action(self) -> None:
        code, payload = run_gate(
            {
                "top_level_command": "ai-workflow",
                "current_phase": "BLOCKED",
                "next_required_phase": None,
                "terminal_reason": "blocked",
                "next_action": {
                    "kind": "execute",
                    "command": "/ai-plan",
                    "arguments": [],
                    "expected_postcondition": "X",
                },
            }
        )
        self.assertEqual(code, 2)
        self.assertEqual(payload["error"], "BLOCKER_EXECUTABLE_ACTION_FORBIDDEN")

    def test_terminal_success_with_successor(self) -> None:
        code, payload = run_gate(
            {
                "top_level_command": "ai-workflow",
                "current_phase": "LOCAL_COMMITTED",
                "next_required_phase": "IDEA_INTAKE",
                "terminal_reason": None,
            }
        )
        self.assertEqual(code, 2)
        self.assertEqual(payload["error"], "SUCCESS_TERMINAL_FIELDS_INVALID")

    def test_terminal_success_with_reason(self) -> None:
        code, payload = run_gate(
            {
                "top_level_command": "ai-workflow",
                "current_phase": "LOCAL_COMMITTED",
                "next_required_phase": None,
                "terminal_reason": "oops",
            }
        )
        self.assertEqual(code, 2)
        self.assertEqual(payload["error"], "SUCCESS_TERMINAL_FIELDS_INVALID")

    def test_implementation_without_packet(self) -> None:
        code, payload = run_gate(
            {
                "top_level_command": "ai-workflow",
                "current_phase": "PRE_CHANGE_SAFEPOINT_WHEN_REQUIRED",
                "next_required_phase": "IMPLEMENTING",
                "terminal_reason": None,
                "attempt_consumed": True,
                "next_action": {
                    "kind": "execute",
                    "command": "/ai-execute",
                    "arguments": [],
                    "expected_postcondition": "IMPLEMENTING",
                    "attempt_consumed": True,
                },
            }
        )
        self.assertEqual(code, 2)
        self.assertEqual(payload["error"], "REQUIRED_ARTIFACT_MISSING")

    def test_planning_executor_claim(self) -> None:
        code, payload = run_gate(
            {
                "top_level_command": "ai-workflow",
                "current_phase": "OPERATIONAL_PLANNING",
                "next_required_phase": "READY_FOR_EXECUTION",
                "terminal_reason": None,
                "executor_started": True,
                "next_action": {
                    "kind": "execute",
                    "command": "/ai-plan",
                    "arguments": [],
                    "expected_postcondition": "READY_FOR_EXECUTION",
                },
            }
        )
        self.assertEqual(code, 2)
        self.assertEqual(payload["error"], "PLANNING_EXECUTOR_START_CLAIM_FORBIDDEN")

    def test_attempt_mismatch(self) -> None:
        code, payload = run_gate(
            {
                "top_level_command": "ai-workflow",
                "current_phase": "PRE_CHANGE_SAFEPOINT_WHEN_REQUIRED",
                "next_required_phase": "IMPLEMENTING",
                "terminal_reason": None,
                "present_artifacts": ["EXECUTION_PACKET"],
                "attempt_consumed": False,
                "next_action": {
                    "kind": "execute",
                    "command": "/ai-execute",
                    "arguments": [],
                    "expected_postcondition": "IMPLEMENTING",
                    "attempt_consumed": False,
                },
            }
        )
        self.assertEqual(code, 2)
        self.assertIn(payload["error"], {"ATTEMPT_CONSUMPTION_MISMATCH", "ATTEMPT_CONSUMPTION_UNDECLARED"})

    def test_missing_owner_decision(self) -> None:
        # human decision edge PRODUCT_SCOPE_APPROVAL -> HUMAN_INPUT_REQUIRED
        code, payload = run_gate(
            {
                "top_level_command": "ai-workflow",
                "current_phase": "PRODUCT_SCOPE_APPROVAL",
                "next_required_phase": "HUMAN_INPUT_REQUIRED",
                "terminal_reason": None,
                "next_action": {
                    "kind": "human_decision",
                    "decision_required": "scope",
                    "available_choices": ["APPROVE"],
                },
            }
        )
        self.assertEqual(code, 2)
        self.assertEqual(payload["error"], "OWNER_DECISION_REQUIRED")


class GeneratorFreshness(unittest.TestCase):
    def test_generated_fresh(self) -> None:
        r = subprocess.run(
            [sys.executable, str(ROOT / "scripts" / "generate-governance-contract.py"), "--root", str(ROOT), "--check"],
            capture_output=True,
            text=True,
        )
        self.assertEqual(r.returncode, 0, r.stderr + r.stdout)


class AuthorityEquivalence(unittest.TestCase):
    def test_authority_matches_gate(self) -> None:
        import importlib.util

        path = ROOT / "scripts" / "governance-authority.py"
        spec = importlib.util.spec_from_file_location("gov_auth", path)
        mod = importlib.util.module_from_spec(spec)
        assert spec.loader
        spec.loader.exec_module(mod)
        state = enrich(
            base_state("AUDIT_PASS", "IDEA_INTAKE", "/ai-init", "IDEA_INTAKE"),
            G.find_transition("AUDIT_PASS", "IDEA_INTAKE", "/ai-init") or {},
        )
        code, payload = run_gate(state)
        self.assertEqual(code, 3)
        auth = mod.validate_continuation(state)
        self.assertEqual(auth["status"], "ACTIONABLE_CONTINUATION_VALID")
        self.assertEqual(auth["next_required_phase"], "IDEA_INTAKE")


if __name__ == "__main__":
    unittest.main()
