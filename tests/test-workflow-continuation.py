#!/usr/bin/env python3
"""3.8.0 semantic workflow continuation regressions (shape + transition table)."""
from __future__ import annotations

import json
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
CORE = ROOT / "scripts" / "workflow-continuation.py"
GEN = ROOT / "scripts" / "generated" / "governance_contract_data.py"

sys.path.insert(0, str(ROOT / "scripts"))
from generated import governance_contract_data as G  # noqa: E402


def run_gate(state: dict[str, object], expected_command: str = "ai-workflow") -> tuple[int, dict[str, object], str]:
    with tempfile.TemporaryDirectory(prefix="opencode-workflow-continuation-") as directory:
        path = pathlib.Path(directory) / "RUN_STATE.json"
        path.write_text(json.dumps(state, indent=2) + "\n", encoding="utf-8")
        result = subprocess.run(
            [sys.executable, str(CORE), "--run-state", str(path), "--expected-command", expected_command],
            text=True,
            capture_output=True,
        )
        payload: dict[str, object] = {}
        if result.stdout.strip():
            payload = json.loads(result.stdout)
        return result.returncode, payload, result.stderr


def action_for(frm: str, to: str) -> dict[str, object]:
    t = G.find_transition(frm, to, None)
    # Prefer execute transitions
    for tr in G.TRANSITIONS:
        if tr["from"] == frm and tr["to"] == to and tr.get("command"):
            t = tr
            break
    assert t is not None, (frm, to)
    cmd = t.get("command") or "/ai-workflow"
    post = t.get("required_postcondition") or to
    body: dict[str, object] = {
        "kind": "execute",
        "command": cmd,
        "arguments": [],
        "expected_postcondition": post,
    }
    if t.get("attempt_consumed"):
        body["attempt_consumed"] = True
    return body


def continuing(phase: str, next_phase: str, **extra: object) -> dict[str, object]:
    state: dict[str, object] = {
        "top_level_command": "ai-workflow",
        "current_phase": phase,
        "next_required_phase": next_phase,
        "terminal_reason": None,
        "next_action": action_for(phase, next_phase),
        "lifecycle_mode": "STANDARD",
    }
    # Satisfy common artifact/receipt requirements for known transitions
    t = None
    for tr in G.TRANSITIONS:
        if tr["from"] == phase and tr["to"] == next_phase and tr.get("command"):
            t = tr
            break
    if t:
        arts = list(t.get("required_artifacts") or [])
        recs = list(t.get("required_receipts") or [])
        if arts:
            state["present_artifacts"] = arts
        if recs:
            state["present_receipts"] = recs
        if t.get("required_candidate_state") == "FROZEN":
            state["frozen_candidate"] = "cand-test"
            state["candidate_state"] = "FROZEN"
        if t.get("required_owner_decision"):
            state["owner_decision"] = {"decision": "APPROVE"}
        if t.get("required_review_state") == "FINAL_PASS":
            state["final_verdict"] = "PASS"
        if t.get("attempt_consumed"):
            state["attempt_consumed"] = True
            state["next_action"]["attempt_consumed"] = True  # type: ignore[index]
    state.update(extra)
    return state


def main() -> None:
    assert GEN.is_file(), "generated contract missing"
    code, payload, _ = run_gate(continuing("AUDIT_PASS", "IDEA_INTAKE"))
    assert code == 3, payload
    assert payload["decision"] == "CONTINUE_REQUIRED"
    assert payload["current_phase"] == "AUDIT_PASS"
    assert payload["next_required_phase"] == "IDEA_INTAKE"
    assert payload["next_action_kind"] == "execute"
    assert payload.get("semantic") == "PASS"

    for phase, next_phase in (
        ("BASELINE_DEFECT", "BASELINE_VALIDATED"),
        ("DISCOVERY_DEFECT", "ADAPTIVE_PRODUCT_DISCOVERY"),
        ("PASS", "PRODUCT_COMPLETENESS_RECONCILIATION"),
        ("IMPLEMENTATION_DEFECT", "IMPLEMENTING"),
        ("PLAN_DEFECT", "CONTEXT_ROUTING"),
        ("PRODUCT_DEFECT", "IMPLEMENTING"),
        ("NOT_READY_FOR_PRODUCTION", "VALIDATED_LEARNING"),
    ):
        code, payload, _ = run_gate(continuing(phase, next_phase))
        assert code == 3, (phase, payload)
        assert payload["decision"] == "CONTINUE_REQUIRED"

    code, payload, _ = run_gate(
        {
            "top_level_command": "ai-workflow",
            "current_phase": "AUDIT_PASS",
            "next_required_phase": "IDEA_INTAKE",
            "terminal_reason": None,
        }
    )
    assert code == 2
    assert payload["error"] == "ACTIONABLE_CONTINUATION_REQUIRED"

    code, payload, _ = run_gate(
        {
            "top_level_command": "ai-workflow",
            "current_phase": "LOCAL_COMMITTED",
            "next_required_phase": None,
            "terminal_reason": None,
        }
    )
    assert code == 0
    assert payload["decision"] == "TERMINAL_ALLOWED"

    code, payload, _ = run_gate(
        {
            "top_level_command": "ai-workflow",
            "current_phase": "HUMAN_INPUT_REQUIRED",
            "next_required_phase": None,
            "terminal_reason": "A material product decision requires owner approval.",
        }
    )
    assert code == 0
    assert payload["decision"] == "TERMINAL_ALLOWED"

    # Wrong command for a defined edge
    bad = continuing("AUDIT_PASS", "IDEA_INTAKE")
    bad["next_action"] = {
        "kind": "execute",
        "command": "/ai-execute",
        "arguments": [],
        "expected_postcondition": "IDEA_INTAKE",
    }
    code, payload, _ = run_gate(bad)
    assert code == 2
    assert payload["error"] in {"TRANSITION_NOT_DEFINED", "TRANSITION_COMMAND_MISMATCH", "DISALLOWED_SUCCESSOR"}

    # Disallowed successor
    code, payload, _ = run_gate(
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
            },
        }
    )
    assert code == 2
    assert payload["error"] in {"DISALLOWED_SUCCESSOR", "TRANSITION_NOT_DEFINED"}

    print("PASS: semantic workflow continuation regressions")


if __name__ == "__main__":
    main()
